sudo apt install default-jdk

git clone https://github.com/carlosandres-mendez/operativos.git

cd operativos/
cd sockets/

vim HTTPServer.java
#Cambiar el address a 0.0.0.0

javac --release 8 HTTPServer.java

sudo java HTTPServer

probe con localhost:5000/linux.jpg