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
	├── models										# place where puting source code files of model definitions
	├── plugins										# plugins directory
	├── settings.lua								# project setting file
	└── views										# place where puting views/template (html) files
		└── index.html
		
		
###Configuration per Project
Each project or application has a configuration file *settings.lua*. Now Bamboo web framework builds on the top of Mongrel2 and Redis, so the database to use should be specified in a configuration file. Also, Mongrel2-related and Bamboo itself should be expressed clearly. The typical example follows as:
	
	project_name = "blog"	
	-- Mongrel2 info 
	monserver_dir = "/home/fisk/workspace/monserver/"		-- location of Mongrel2 web server
	sender_id = 'f322e744-c075-4f54-a561-a6367dde466c'		-- unique id of Mongrel2 server
	config_db = 'conf/config.sqlite'		-- data source of Mongrel2 web server, after loading mongrel2.conf into server
	
	-- Bamboo info
	bamboo_dir = "/usr/local/share/lua/5.1/bamboo/"		-- location of Bamboo web framework
	io_threads = 1										-- number of threads work with ZMQ
	views = "views/"									-- location of templates where Bamboo searching for when rendering
	
	-- Redis info 
	WHICH_DB = 15	     					-- which database the project use, Bind_IP and port should be added here later
	

###Configuring Mongrel2 Web Server
To have Mongrel2-related sqlite database file, we still need a configuration of Mongrel2 web servers. Each sqlite database can contain several servers and each server has many hosts. Each server could be treated as independent process. The name of each host is corresponding to the project_name in setting.lua above. For detail, you can refer to [Mongrel manual](http://mongrel2.org/static/mongrel2-manual.html). Here one typical example is showed in the following:

	# location of static pages
	static_blog = Dir( base='sites/blog/', index_file='index.html', default_ctype='text/plain') 
	
	# corresponding to each Bamboo process
	handler_blog = Handler(send_spec='tcp://127.0.0.1:10001',
		            send_ident='ba06f707-8647-46b9-b7f7-e641d6419909',
		            recv_spec='tcp://127.0.0.1:10002', recv_ident='')
	
	# each server instance  within independent process
	main = Server(
		uuid="505417b8-1de4-454f-98b6-07eb98f5cca1"
		access_log="/logs/access.log"
		error_log="/logs/error.log"
		chroot="./"
		pid_file="/run/mongrel2.pid"
		default_host="blog"
		name="main"
		port=6767
		hosts=[ 
			Host(   name="blog", 
		            routes={ 
						'/': handler_blog,
		                '/favicon.ico': static_blog,
		                '/media/': static_blog
		            } 
		    )
		]
	)


	settings = {	"zeromq.threads": 1, 
					'limits.content_length': 20971520, 
					'upload.temp_store': '/tmp/mongrel2.upload.XXXXXX' 
	}

	servers = [main]
	
After excuting the script of `m2sh load -config conf/mongrel2.conf` and `m2sh start -db conf/config.sqlite`, the configuration information and running status of web servers could be pulled out from the specific sqlite database. This is a better place for administrators to manage many web servers. Now you can test whether the configuration works or not. 


The Bamboo web framework provides a set of command lines for convenience.

	bamboo createapp myproject				-- generate several folds for each application
	bamboo createplugin plugin_name			-- create a plugin for better reuse
	bamboo createmodel Modelname			-- create a model Scaffold
	bamboo initdb initial_data_filename		-- initializing the database that configed in setting.lua by data file
	bamboo pushdb new_data_filename			-- fill in more data into database
	bamboo clearmodel Modelname				-- delete all details of the specific model-related data
	bamboo shell 							-- open the interactive mode of bamboo for 
	








