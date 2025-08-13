#!/bin/bash
sudo apt update -y
sudo apt upgrade -y
sudo apt install apache2 -y

if [ -d "/var/www/operativos" ]; then
    echo "El directorio existe."
else
    sudo mkdir /var/www/operativos
fi

if [ ! -f "/var/www/operativos/index.html" ]; then
    sudo touch /var/www/operativos/index.html
    echo "hola" | sudo tee /var/www/operativos/index.html > /dev/null
else
    echo "El archivo ya existe."
fi

sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/operativos.conf
sudo sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/operativos|g' /etc/apache2/sites-availab>sudo a2dissite 000-default.conf
sudo a2ensite operativos.conf
sudo systemctl reload apache2