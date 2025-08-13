# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update


#Instalar Docker packages
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

#Verificar
sudo docker run hello-world


----------------------------------------------
#Crear red
docker network create misitio-net

#Crear contenedor de BD
docker run -d --name misitiodb \
  --network misitio-net \
  -e MYSQL_ROOT_PASSWORD=jose.123 \
  -e MYSQL_USER=jose \
  -e MYSQL_PASSWORD=jose.123 \
  -e MYSQL_DATABASE=misitiodb \
  -v websitedbvolume:/var/lib/mysql \
  mariadb:latest

docker ps
docker volume ls
docker volume inspect websitedbvolume

#Crear directorio para el servidor
mkdir public_html

#Crear el index.html
echo '<h1>Hola desde Docker!</h1>' > public_html/index.html

#Crear el contenerdor del servidor
docker run -d --name sitio \
  --network misitio-net \
  -p 8081:80 \
  -v $(pwd)/public_html:/var/www/html \
  php:apache

#Probar en
http://localhost:8081

