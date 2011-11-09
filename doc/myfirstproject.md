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
		
		
###Configuration per Project
Each project or application has a configuration file settings.lua. Now Bamboo web framework builds on the top of Mongrel2 and Redis, so the database to use should be specified in a configuration file. Also, Mongrel2-related and Bamboo itself should be expressed clearly. The typical example follows as:
	
	project_name = "blog"	
	-- Mongrel2 info 
	monserver_dir = "/home/fisk/workspace/monserver/"			-- location of Mongrel2 web server
	sender_id = 'f322e744-c075-4f54-a561-a6367dde466c'			-- unique id of Mongrel2 server
	config_db = 'conf/config.sqlite'							-- data source of Mongrel2 web server, after loading mongrel2.conf into server
	
	-- Bamboo info
	bamboo_dir = "/usr/local/share/lua/5.1/bamboo/"			-- location of Bamboo web framework
	io_threads = 1											-- single thread
	views = "views/"										-- the location of templates that Bamboo searching for when 
	
	-- Redis info 
	WHICH_DB = 15											-- which database the project use, Bind_IP and port should be added later
	
###Configuring Mongrel2 Web Server
Rake is a general-purpose command-runner that Rails uses for many things. You can see the list of available rake commands in your application by running rake -T.

	static_apptest = Dir( base='sites/apptest/', index_file='index.html', default_ctype='text/plain')

	handler_apptest = Handler(send_spec='tcp://127.0.0.1:10001',
		            send_ident='ba06f707-8647-46b9-b7f7-e641d6419909',
		            recv_spec='tcp://127.0.0.1:10002', recv_ident='')

	main = Server(
		uuid="505417b8-1de4-454f-98b6-07eb9225cca1"
		access_log="/logs/access.log"
		error_log="/logs/error.log"
		chroot="./"
		pid_file="/run/mongrel2.pid"
		default_host="apptest"
		name="main"
		port=6767
		hosts=[ 
			Host(   name="apptest", 
		            routes={ 
						'/': handler_apptest,
		                '/favicon.ico': static_apptest,
		                '/media/': static_apptest
		            } 
		    )
		]
	)


	settings = {	"zeromq.threads": 1, 
			'limits.content_length': 20971520, 
			'upload.temp_store': '/tmp/mongrel2.upload.XXXXXX' 
	}

	servers = [main]
