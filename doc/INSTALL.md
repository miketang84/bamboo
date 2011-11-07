Bamboo Installation
===================

## Prerequisites

- lua5.1 (if have no it, use `apt-get install lua5.1` to install it in Ubuntu/Debian.)

## Use Installation Tool

- Download bamboo installation tool BAMBOO_INSTALL_v1.x.tar.gz from [an url];
- Extract the package and execute the installation script;
	tar xvf BAMOO_INSTALL_v1.0rc0.tar.gz && cd BAMBOO_INSTALL
	./bamboo_installer
- When you see 'Congratulations! Install Bamboo Successfully.', this installation is OK.

## Test

- Start mongrel2 server;
	cd ~/workspace/monserver
	bamboo loadconfig
	bamboo startserver main
  If mongrel2 server occupy this terminal, open a new terminal before next step;	
- Start redis server, it will run as a deamon;
	cd ~
	redis-server /etc/redis.conf
- Create apptest project and start it;
	cd ~/workspace
	bamboo createapp apptest
	cd ~/workspace/apptest
	bamboo start
  If this step goes smoothly, you will see what like follows:
  CONNECTING / 45564ef2-ca84-a0b5-9a60-0592c290ebd0 tcp://127.0.0.1:9999 tcp://127.0.0.1:9998				  
- Open the web browser and input `http://localhost:6767` and enter, you will see 'Welcome to Bamboo.';
- END.

