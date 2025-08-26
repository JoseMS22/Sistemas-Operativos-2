# --- CONFIGURACIÓN DE SUDO ---
# Se configura un log dedicado para sudo y se exige que sudo siempre se ejecute desde un TTY
echo 'Defaults logfile="/var/log/sudo.log"' | sudo EDITOR='tee -a' visudo
echo 'Defaults requiretty' | sudo EDITOR='tee -a' visudo

# --- ACTUALIZACIONES AUTOMÁTICAS ---
# Se habilitan actualizaciones automáticas con reinicio nocturno programado (En la pantalla que saldrá darle al yes)
sudo dpkg-reconfigure -plow unattended-upgrades
sudo tee /etc/apt/apt.conf.d/51-hardening >/dev/null <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF


# --- LOGS DEL SISTEMA ---
# Se configura journald para guardar logs de forma persistente, comprimidos y con límite de 500MB
sudo sed -i 's/^#\?Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
sudo sed -i 's/^#\?Compress=.*/Compress=yes/' /etc/systemd/journald.conf
sudo sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald


# --- FIREWALL (NFTABLES) INSTALACIÓN ---
# Se instalan y habilitan nftables (firewall moderno de Linux)
sudo apt-get update && sudo apt-get install -y nftables
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y nftables
sudo systemctl enable --now nftables


# --- PARÁMETROS DE KERNEL (sysctl) ---
# Se endurece la red (no aceptar redirects, syncookies, etc.)
# Se limitan colas de red para evitar DoS, se deshabilitan core dumps, etc.
sudo tee /etc/sysctl.d/90-hardening.conf >/dev/null <<'EOF'
# Configuración de red IPv4
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# IPv6 (endurecido, no deshabilitado)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Límites de memoria para evitar ataques DoS
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 250000

# Seguridad del kernel
fs.suid_dumpable = 0
kernel.randomize_va_space = 2
EOF

# Añade solo el tuning para HAProxy en un archivo nuevo
sudo tee /etc/sysctl.d/90-haproxy-tuning.conf >/dev/null <<'EOF'
net.core.somaxconn = 4096
net.ipv4.ip_local_port_range = 1024 65000
# (opcional, útil en picos de conexiones)
net.ipv4.tcp_max_syn_backlog = 8192
EOF

sudo sysctl --system


# --- ENDURECIMIENTO DE DIRECTORIOS TEMPORALES ---
# Agregar a fstab solo si no existe
grep -qE '^[^#]*\s/tmp\s+tmpfs' /etc/fstab || \
  echo 'tmpfs /tmp     tmpfs defaults,rw,nosuid,nodev,noexec,mode=1777 0 0' | sudo tee -a /etc/fstab

grep -qE '^[^#]*\s/var/tmp\s+tmpfs' /etc/fstab || \
  echo 'tmpfs /var/tmp tmpfs defaults,rw,nosuid,nodev,noexec,mode=1777 0 0' | sudo tee -a /etc/fstab

sudo systemctl daemon-reexec
mountpoint -q /tmp     && sudo mount -o remount /tmp     || sudo mount /tmp
mountpoint -q /var/tmp && sudo mount -o remount /var/tmp || sudo mount /var/tmp



# --- APPARMOR ---
# Se revisa y habilita AppArmor (control de acceso obligatorio)
sudo aa-status | head -n 5
sudo systemctl enable --now apparmor


# --- FAIL2BAN ---
# Se instala y configura Fail2Ban para proteger SSH (baneo de 1h tras 5 intentos fallidos en 10 min)
sudo apt install -y fail2ban
sudo tee /etc/fail2ban/jail.d/sshd-hardening.conf >/dev/null <<'EOF'
[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
findtime = 10m
bantime  = 1h
backend  = systemd
EOF
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd


# --- AUDITD ---
# Se instala auditd para auditoría de eventos críticos y se cargan reglas focalizadas
sudo apt install -y auditd audispd-plugins
sudo systemctl enable --now auditd
sudo tee /etc/audit/rules.d/hardening.rules >/dev/null <<'EOF'
-w /etc/passwd    -p wa -k identity
-w /etc/group     -p wa -k identity
-w /etc/shadow    -p wa -k identity
-w /etc/sudoers   -p wa -k sudo
-w /etc/sudoers.d/ -p wa -k sudo
-w /var/log/auth.log -p wa -k auth
EOF
sudo augenrules --load
sudo systemctl restart auditd


# --- AIDE ---
# Se instala AIDE (herramienta de verificación de integridad), se inicializa la base de datos
# y se programa un chequeo diario a las 04:00
sudo apt install -y aide
sudo aideinit
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
echo '0 4 * * * root /usr/bin/aide --config=/etc/aide/aide.conf --check > /var/log/aide/last-check.log 2>&1' | sudo tee /etc/cron.d/aide-check


# --- FIREWALL FINAL (NFTABLES) ---
# Política restrictiva: DROP por defecto.
# Permite: SSH (rate limit), ICMP limitado, HAProxy 80/443 (público),
# MariaDB/Galera y Redis SOLO desde la red interna, y tráfico de bridges Docker.
sudo tee /etc/nftables.conf >/dev/null <<'EOF'
flush ruleset

table inet filter {
  set cluster_cidr {
    type ipv4_addr
    flags interval
    elements = { 172.31.16.0/20 }
  }

  chain input {
    type filter hook input priority filter; policy drop;

    # Básico
    ct state established,related accept
    iif "lo" accept

    # ICMP (ping) limitado
    ip protocol icmp limit rate 5/second accept

    # SSH abierto a todos (temporal; reforzado con Fail2ban)
    tcp dport 22 ct state new limit rate 30/minute accept

    # === HAProxy (público) ===
    tcp dport { 80, 443 } accept
    # (Opcional) stats/admin de HAProxy si lo usas:
    # tcp dport 8404 accept

    # === MariaDB/MySQL (Galera) ===
    # Clientes app internos
    ip saddr @cluster_cidr tcp dport 3306 accept
    # Tráfico entre nodos Galera
    ip saddr @cluster_cidr tcp dport { 4567, 4568, 4444 } accept
    ip saddr @cluster_cidr udp dport 4567 accept

    # === Redis ===
    ip saddr @cluster_cidr tcp dport 6379 accept
    # (Opcional) Redis Cluster / Sentinel:
    # ip saddr @cluster_cidr tcp dport 16379 accept
    # ip saddr @cluster_cidr tcp dport 26379 accept

    counter drop
  }

  chain forward {
    type filter hook forward priority filter; policy drop;
    # Permitir tráfico de/entre bridges de Docker
    ct state established,related accept
    iifname { "docker0", "br-*" } accept
    oifname { "docker0", "br-*" } accept
    counter drop
  }

  chain output {
    type filter hook output priority filter; policy accept;
  }
}
EOF

# Validar, cargar y habilitar firewall
sudo nft -c -f /etc/nftables.conf
sudo nft -f /etc/nftables.conf
sudo nft list ruleset
sudo systemctl enable --now nftables
sudo systemctl restart nftables
sudo systemctl status nftables --no-pager
