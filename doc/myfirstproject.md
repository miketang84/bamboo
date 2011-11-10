#A New Bamboo Project

##Introduction 
###Creating a Project
To begin, open a terminal, navigate to a folder where you have rights to create files and check whether there is a *settings.lua* file in the current directory. If not, you can create a new one, which are just the directory of your mongrel2 server and directory of bamboo installed, like the following example:
	
	monserver_dir = "/home/fisk/workspace/monserver/"
	bamboo_dir = "/usr/local/share/lua/5.1/bamboo/" 
	
After that, just type:
	
	bamboo createapp myfirstapp
	
This will create a Bamboo application called myfirstapp in a directory called *myfirstapp*. After you create the myfirstapp application, switch to its folder to continue work directly in that application:
	
	cd myfirstapp
	
In any case, Bamboo will create a folder in your working directory called myfirstapp. Open up that folder and explore its contents. Here is a basic rundown on the function of each folder that Bamboo creates in a new application by default. 

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
Each project or application has a configuration file *settings.lua*. Now Bamboo web framework builds on the top of Mongrel2 and Redis, so the database to use and Mongrel2-related information on bamboo side should be specified in this configuration file. Also, Bamboo itself should be expressed clearly. The typical example follows as:
	
	project_name = "myfirstapp"	
	-- Mongrel2 info 
	monserver_dir = "/home/fisk/workspace/monserver/"		-- location of instances of Mongrel2 web server
	sender_id = 'f322e744-c075-4f54-a561-a6367dde466c'		-- unique id of Mongrel2 server instance
	config_db = 'conf/config.sqlite'		-- data source of Mongrel2 web server, after loading mongrel2.conf into server
	
	-- Bamboo info
	bamboo_dir = "/usr/local/share/lua/5.1/bamboo/"		-- location of Bamboo web framework
	io_threads = 1										-- number of threads work with ZMQ
	views = "views/"									-- location of templates where Bamboo searching for when rendering
	
	-- Redis info 
	WHICH_DB = 15	     					-- which database the project use, Bind_IP and port should be added here later
	

###Configuring Mongrel2 Web Server
To have Mongrel2-related sqlite database file, we still need a configuration of Mongrel2 web servers. Each sqlite database can contain several servers and each server could have many hosts. Each server could be treated as independent process. The name of each host is corresponding to the project_name in setting.lua above. For detail, you can refer to [Mongrel manual](http://mongrel2.org/static/mongrel2-manual.html). Here one typical example is showed in the following:

	# location of static pages
	static_myfirstapp = Dir( base='sites/myfirstapp/', index_file='index.html', default_ctype='text/plain') 
	
	# corresponding to each Bamboo process
	handler_myfirstapp = Handler(send_spec='tcp://127.0.0.1:10001',
		            send_ident='ba06f707-8647-46b9-b7f7-e641d6419909',
		            recv_spec='tcp://127.0.0.1:10002', recv_ident='')
	
	# each server instance  within independent process
	main = Server(
		uuid="505417b8-1de4-454f-98b6-07eb98f5cca1"
		access_log="/logs/access.log"
		error_log="/logs/error.log"		-- relative path w.r.t. chroot 
		chroot="./"						-- the directory of running mongrel2 instance by m2sh start  
		pid_file="/run/mongrel2.pid"
		default_host="myfirstapp"
		name="main"   
		port=6767
		hosts=[ 
			Host(   name="myfirstapp", 
		            routes={ 
						'/': handler_myfirstapp,
		                '/favicon.ico': static_myfirstapp,
		                '/media/': static_myfirstapp
		            } 
		    )
		]
	)


	settings = {	"zeromq.threads": 1, 
					'limits.content_length': 20971520, 
					'upload.temp_store': '/tmp/mongrel2.upload.XXXXXX' 
	}

	servers = [main]
	
Executing the following scripts under the directory of monserver_dir, 
	
	mkdir sites/myfirstapp			-- later mounting the media file under myfirstapp/ into this location 
	m2sh load -config conf/mongrel2.conf -db conf/config.sqlite	 	-- loading  config file into sqlite database 
	sudo m2sh start -db conf/config.sqlite -name main				-- launching mongrel web server of "main"
	
then configuration information and running status of web servers could be pulled out from the specific sqlite database by `m2sh` scripting. This is a better place for administrators to manage many web servers. Now you can test whether the configuration works or not. 
	
	redis-server /etc/redis.conf		-- start the database server of redis 
	cd myfirstapp_dir
	sudo bamboo start 					-- launching the applicaiton of myfirstapp
	
After typing `http://localhost:6767/` in the browser, it works well if the `Welcome to Bamboo` shows up. In addition to `bamboo createapp myproject`, the Bamboo web framework provides a set of command lines for convenience.

	bamboo createapp myproject				-- generate several folds for each application
	bamboo createplugin plugin_name			-- create a plugin for better reuse
	bamboo createmodel Modelname			-- create a model Scaffold
	bamboo initdb initial_data_filename		-- initializing the database that configed in setting.lua by data file
	bamboo pushdb new_data_filename			-- fill in more data into database
	bamboo clearmodel Modelname				-- delete all details of the specific model-related data
	bamboo shell 							-- open the interactive mode of bamboo for working with database
	


## Procedures of Development of Projects
In the *myfirstapp*, there are two pages totally, homepage and resultpage. In the homepage, it presents a form for collecting user information. After clicking the submit button, *myfirstapp* would save the information that you input into redis database server. At the same time, it will jump to the resultpage that shows your information up after pulling data from database. Usually, we construct data models for applications firstly. 

####Model Components
As for the current application, there is only one model MYUser. To reuse code as much as possible, Bamboo provides models.user model for specific users to inherit from. You can implement such model as the following class `MYUser`, which mainly contains fields and constructor [init() function]. For more details, you can refer to chapter [Model]().

	module(..., package.seeall)

	local User = require 'bamboo.models.user'		-- import another model/class

	local MYUser = User:extend {
		__tag = 'Bamboo.Model.User.MYUser';
		__name = 'MYUser';
		__desc = 'Generitic MYUser definition';
		__indexfd = 'name';							-- all instances of MYUser indexed by name field 
		__fields = {								-- several fields, that is, name, age and gender
			['name'] = {},
			['age'] = {},
			['gender'] = {},

		};
	
		init = function (self, t)				    -- constructor of MYUser class
			if not t then return self end
		
			self.name = t.name
			self.age = t.age
			self.gender = t.gender
		
			return self
		end;

	}

	return MYUser


After defining the MYUser model, you can use the common model API that Bamboo provides to read/write MYUser-related data very easily. Sometimes, You should implement specific methods for your own use cases, like activity-feeding module in SNS website. Now instance method myuser_obj:save() and class method MYUser:all() are used within handler functions of the **controller components**. 


####View Components


	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
		<meta name="keywords" content=" "/>
		<meta name="description" content=" "/>
		<meta http-equiv="Content-Language" content="utf-8" />
		
	 
		<script>
		</script>
		
		<title> Form Process </title>
	</head>

	<body>

	<div class="container">
		{[ 'page' ]}

	</div>
		

	</body>
	</html>
	

form.html

	{: 'index.html' :}

	{[ ======= 'page' ========

		<form action="/form_submit/">
			Name: <input type="text" name="name" /> <br/>
			Age: <input type="text" name="age" /> <br/>
			Gender: <input type="text" name="gender" /> <br/>
			<button type="submit">Submit</button>
		</form>

	]}



result.html

	{: 'index.html' :}

	{[ ======= 'page' ========
	<style>
	table td{
		border: 1px solid black;
	}
	</style>


	The database have the following data:

	<table>
		<tr><th>Name</th><th>Age</th><th>Gender</th></tr>
		{% for _, v in ipairs(all_persons) do%}
		<tr><td>{{v.name}}</td><td>{{v.age}}</td><td>{{v.gender}}</td></tr>
		{% end %}
	</table>

	Click <a href="/"> here </a> to return form page.

	]}
####Controller Components



	require 'bamboo'

	local View = require 'bamboo.view'
	local Form = require 'bamboo.form'

	local MYUser = require 'models.myuser'

	local function index(web, req)
		web:page(View("form.html"){})
	end

	local function form_submit(web, req)
		local params = Form:parse(req)
		DEBUG(params)
	
		local person = MYUser(params)
		-- save person object to db
		person:save()
	
		-- retreive all person instance from db
		local all_persons = MYUser:all()
	
		web:html("result.html", {all_persons = all_persons})
	end


	URLS = { '/',
		['/'] = index,
		['/index/'] = index,
		['/form_submit/'] = form_submit,
	
	}


