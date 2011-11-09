#A New Bamboo Project

##Introduction 
###Creating a Project
To begin, open a terminal, navigate to a folder where you have rights to create files and check whether there is a settings.lua file in the current directory. If not, you can create a new one like the following example, which are just the directory of your mongrel2 server and directory of bamboo installed:
	
	monserver_dir = "/home/fisk/workspace/monserver/"
	bamboo_dir = "/usr/local/share/lua/5.1/bamboo/" 
	
After that, just type:
	
	bamboo createapp blog
	
This will create a Bamboo application called Blog in a directory called *blog*. After you create the blog application, switch to its folder to continue work directly in that application:
	
	cd blog
	
In any case, Bamboo will create a folder in your working directory called blog. Open up that folder and explore its contents. Here is a basic rundown on the function of each folder that Bamboo creates in a new application by default. 

	One project										# This project's directory
	├── app											# control code directory
	│   └── handler_entry.lua						# entry file
	├── initial										# place where put db's initial data
	├── media										# static files directory
	│   ├── css
	│   ├── images
	│   ├── js
	│   ├── plugins
	│   └── uploads
	├── models										# place where put model defined files
	├── plugins										# plugins directory
	├── settings.lua								# project setting file
	└── views										# place where put views (html) files
		└── index.html
		
		
###Configuring a Database 
Just about every Bamboo application will interact with a database. The database to use is specified in a configuration file, config/database.yml. If you open this file in a new Rails application, you’ll see a default database configuration using SQLite3. The file contains sections for three different environments in which Rails can run by default:

    The development environment is used on your development computer as you interact manually with the application.
    The test environment is used to run automated tests.
    The production environment is used when you deploy your application for the world to use.

###Creating the Database
Rake is a general-purpose command-runner that Rails uses for many things. You can see the list of available rake commands in your application by running rake -T.

