
return {

    createapp = function(settings)
        local appname = settings[1] or 'bambooapp'
		readSettings(config)
		local lgserver_dir = config.lgserver_dir
		local bamboo_dir = config.bamboo_dir

		-- create directory
        assert(posix.stat(appname) == nil, '[Error] Some file or directory of this name exists！')
        posix.mkdir(appname)

		-- copy files
        local cmdstr = ('cp -rf %s/src/cmd_tmpls/createapp/* ./%s/'):format(bamboo_dir, appname)
        os.execute(cmdstr)

--[=[
	-- create media directory and later copy files to it
        local mediadir = ('%s/sites/%s'):format(lgserver_dir, appname)
        --os.execute(('mkdir -p %s'):format(mediadir))
		os.execute(('ln -sdf $(pwd)/%s/media %s'):format(appname, mediadir))

        -- do mount --bind
        -- os.execute(('sudo mount -B %s/media %s'):format(appname, mediadir))        
        -- modify the md5 string in settings.lua
        local fd = io.open(('%s/settings.lua'):format(appname), 'r')
	local ctx = fd:read('*all')
	fd:close()

	ctx = ([[
project_name = "%s"
host = "%s"
]]):format(appname, appname) .. ctx
		
	local md5str = makeMD5()
	ctx = ctx:gsub('####', md5str)

	local fd = io.open(('%s/settings.lua'):format(appname), 'w')
	fd:write(ctx)
	fd:close()
	
	-- modify the lgserver config file template string
	local fd = io.open(('%s/monconfig.lua'):format(appname), 'r')
	local ctx = fd:read('*all')
	fd:close()

	ctx = ctx:gsub('%$PROJECT_NAME%$', appname)

	local fd = io.open(('%s/monconfig.lua'):format(appname), 'w')
	fd:write(ctx)
	fd:close()
--]=]	
		
        print(('[OK] Successfully created application %s.'):format(appname))
    end;
    
    createplugin = function(settings)
        local plugin_name = settings[1] or 'bambooplugin'
   		readSettings(config)
        local appname = config.project_name
		local lgserver_dir = config.lgserver_dir
		local bamboo_dir = config.bamboo_dir
        
        -- create dir
        assert(posix.stat(plugin_name) == nil, '[Error] Some file or directory has this name already！')
        posix.mkdir(plugin_name)

        local cmdstr = ('cp -rf %s/src/cmd_tmpls/createplugin/* ./%s/'):format(bamboo_dir, plugin_name)
        os.execute(cmdstr)

        local mediadir = ('%s/sites/%s/plugins/%s/'):format(lgserver_dir, appname, plugin_name)
        os.execute(('mkdir -p %s'):format(mediadir))
        
        local cmdstr = ('cp -rf %s/src/cmd_tmpls/pluginmedia/*  %s'):format(bamboo_dir, mediadir)
        os.execute(cmdstr)

        os.execute(('ln -sdf %s %s/media'):format(mediadir, plugin_name)) 
        
        print(('[OK] Successfully created plugin %s.'):format(plugin_name))  
    end;
    
    createmodel = function(settings)
        local model_name = settings[1] or 'bamboomodel'
   		readSettings(config)
		local bamboo_dir = config.bamboo_dir
        
        local newfile = ('./%s.lua'):format(model_name:lower())
        local cmdstr = ('cp -rf %s/src/cmd_tmpls/createmodel/newmodel.lua %s'):format(bamboo_dir, newfile)
        os.execute(cmdstr)

        local fd = io.open(newfile, 'r')
		local ctx = fd:read('*all')
		fd:close()
		model_name = model_name:sub(1, 1):upper() + model_name:sub(2):lower()
		ctx = ctx:gsub('%$MODEL', model_name)

		local fd = io.open(newfile, 'w')
		fd:write(ctx)
		fd:close()
        
        print(('[OK] Successfully created model %s.'):format(model_name))  
    end;
	
	createcontroller = function(settings)
        local controller_name = settings[1] or 'bamboocontroller'
		controller_name = controller_name:lower()
   		readSettings(config)
		local bamboo_dir = config.bamboo_dir
        
        local newfile = ('./%s.lua'):format(controller_name + '_controller')
        local cmdstr = ('cp -rf %s/src/cmd_tmpls/createcontroller/newcontroller.lua %s'):format(bamboo_dir, newfile)
        os.execute(cmdstr)

        local fd = io.open(newfile, 'r')
		local ctx = fd:read('*all')
		fd:close()
		ctx = ctx:gsub('%$CONTROLLER', controller_name)
		local controller_model = controller_name:sub(1, 1):upper() + controller_name:sub(2):lower()
		ctx = ctx:gsub('%$MODEL', controller_model)
		
		local fd = io.open(newfile, 'w')
		fd:write(ctx)
		fd:close()
        
        print(('[OK] Successfully created controller %s.'):format(controller_name))  
    end;
    
    initdb = function (settings)
        local data_file = settings[1] or 'initial.data'

        local env = setmetatable({}, {__index=_G})
        setfenv(assert(loadfile(data_file)), env)()
        assert(env['DATA'], '[ERROR] There must be DATA variable in initial data file.')

        local params = {
            host = env.DB_HOST or settings.db_host or '127.0.0.1',
            port = env.DB_PORT or settings.db_port or 6379,
        }
        local which = env.WHICH_DB or settings.which_db or 0

        local redis_db = redis.connect(params)
        if env.AUTH then redis_db:auth(env.AUTH) end
        redis_db:select(which)
        
        for k, v in pairs(env.DATA) do
            if type(v) ~= 'table' then
				-- store the string
                redis_db:set(tostring(k), tostring(v))
            else
            	-- store the item
                for kk, vv in pairs(v) do
                    redis_db:hset(tostring(k), tostring(kk), tostring(vv))
                end

                -- k is the format of User:1
				local model_name, num = k:match('([%w_]+):(%d+)')
				if model_name and type(tonumber(num)) == 'number' then
					-- update the latest __counter value of that model
					local key_list = redis_db:keys(model_name + ':[0-9]*')
					redis_db:set(model_name + ':__counter', #key_list)
					-- add item zset cache 
					-- maybe we should delete the same score item first
					redis_db:zremrangebyscore(model_name + ':__index', num, num)
					-- add it
					local indexfd
					if env.Indexes and env.Indexes[model_name] and v[env.Indexes[model_name]] then indexfd = env.Indexes[model_name] end
					redis_db:zadd(model_name + ':__index', num, indexfd and v[indexfd] or num)
				end
            end

        end

        BAMBOO_DB = redis_db
        if env.SCRIPTS then
			for _, script in ipairs(env.SCRIPTS) do
				-- load the external code in initial data file
				local f = assert(loadstring(script))
				-- execute it
				f()
			end
        end
        
        print('OK')
    end;

	-- push new data to database
    pushdb = function (settings)
        local data_file = settings[1] or 'initial.data'

        local env = setmetatable({}, {__index=_G})
        setfenv(assert(loadfile(data_file)), env)()
        assert(env['DATA'], '[ERROR] There must be DATA variable in initial data file.')

        local params = {
            host = env.DB_HOST or settings.db_host or '127.0.0.1',
            port = env.DB_PORT or settings.db_port or 6379,
        }
        local which = env.WHICH_DB or settings.which_db or 0

        local redis_db = redis.connect(params)
        redis_db:select(which)
        -- Global variable BAMBOO_DB, to use bamboo's model function, must specify it
        BAMBOO_DB = redis_db

		local childenv = {}
		setfenv(assert(loadfile('app/handler_entry.lua') or loadfile('../app/handler_entry.lua')), setmetatable(childenv, {__index=_G}))()

		for k, v in pairs(DATA) do
			if type(v) == 'table' then
				local model = bamboo.getModelByName(k)
				for i, item in ipairs(v) do
					local ori_obj = model:getByName(item.name)
					assert(isFalse(ori_obj), ("[ERROR] The same name object %s exists."):format(item.name))
				end
			end
		end

		-- we have ensure no same name key exists
		for k, v in pairs(DATA) do
			if type(v) == 'table' then
				local model = bamboo.getModelByName(k)
				local obj
	
				for i, item in ipairs(v) do
					print(item.name)
					obj = model(item)
					obj:save()
				end
			else
				-- do nothing now
			end
		end
        
        print('OK')
    end;

    clearmodel = function (settings)
		local model_name = settings[1]
		assert(model_name, '[ERROR] model_name must be specified!')
        
        local params = {
            host = settings.db_host or '127.0.0.1',
            port = settings.db_port or 6379,
        }
        local which = settings.which_db or 0

        local redis_db = redis.connect(params)
        if config.AUTH then redis_db:auth(config.AUTH) end
		redis_db:select(which)

		local key_list = redis_db:keys( model_name + ':*')
		for i, v in ipairs(key_list) do
			print(v)
			redis_db:del(v)
		end

		print('OK.')
    end;

    clearrule = function (settings)
        readSettings(config)
        local params = {
            host = settings.db_host or config.DB_HOST or '127.0.0.1',
            port = settings.db_port or config.DB_PORT or 6379,
        }
        local which = settings.which_db or config.WHICH_DB or 0
	
        local redis_db = redis.connect(params)
        if config.AUTH then redis_db:auth(config.AUTH) end
		redis_db:select(which)

		local key_list = redis_db:keys( '_RULE*')
		for i, v in ipairs(key_list) do
			print(v)
			redis_db:del(v)
		end

		print('OK.')
    end;

	
    shell = function (settings)
   		readSettings(config)
		local bamboo_dir = config.bamboo_dir

		local shell_file = bamboo_dir + '/src/bin/shell.lua'
		local host = settings.db_host or config.DB_HOST or '127.0.0.1'
        local port = settings.db_port or config.DB_PORT or 6379
        local which = settings.which_db or config.WHICH_DB or 0

        os.execute('lua -i ' + shell_file + (' %s %s %s'):format(host, port, which))

        print('Return.')
		
    end;
    
	startserver = function (settings)
		local servername = settings[1]
		local config_file = settings.config_file or 'config.lua'
		local _config = {}
		setfenv(assert(loadfile(config_file), "Failed to load the lgserver's config: " .. config_file), _config)()
		
		if not servername then
			print("You can start the following servers:")
			print('', 'all')
			for _, server in ipairs(_config.servers) do
				print('', server.name)
			end
		elseif servername == 'all' then
			print("================== Ready to start servers ===================")
			for _, server in ipairs(_config.servers) do
				assert(server and server.name, '[ERROR] server or server.name is nil.')
				os.execute(('lgserver %s %s'):format(config_file, server.name))
			end
			print("OK.")
		else
			print("================== Ready to start server ===================")
			for _, server in ipairs(_config.servers) do
				if server and server.name == servername then
					os.execute(('lgserver %s %s'):format(config_file, server.name))
				end
			end
			print("OK.")
		end
		
	end;
	
	stopserver = function (settings)
		local servername = settings[1]
		local config_file = settings.config_file or 'config.lua'
		local _config = {}
		setfenv(assert(loadfile(config_file), "Failed to load the lgserver's config: " .. config_file), _config)()
					
		if not servername then
			print("You can stop the following servers:")
			print('', 'all')
			for _, server in ipairs(_config.servers) do
				print('', server.name)
			end
		elseif servername == 'all' then
			print("==== Ready to stop servers ====")
			for _, server in ipairs(_config.servers) do
				--os.execute(('m2sh stop --db %s -name %s'):format(config_db, server.name))
			end
			print("OK.")
		else
			print("==== Ready to stop server ====")
			for _, server in ipairs(_config.servers) do
				if server and server.name == servername then
					--os.execute(('m2sh stop --db %s -name %s'):format(config_db, server.name))
				end
			end
			print("OK.")
		end
		
	end;
    
	importadmin = function (settings)
		readSettings(config)
		local lgserver_dir = config.lgserver_dir
		local bamboo_dir = config.bamboo_dir

		-- copy admin files to app
		local cmdstr = ('cp -rf %s/src/cmd_tmpls/admin ./'):format(bamboo_dir)
        os.execute(cmdstr)
		-- move the admin static files to media
		local cmdstr = 'mv ./admin/media ./media/admin'
        os.execute(cmdstr)
		
		print('OK.')
	end;
	
    createsuperuser = function (settings)
		  readSettings(config)

		  local redis = require 'bamboo.redis'

		  local bamboo_dir = config.bamboo_dir

		  local host = settings.db_host or config.DB_HOST or '127.0.0.1'
		  local port = settings.db_port or config.DB_PORT or 6379
		  local which = settings.which_db or config.WHICH_DB or 0					  

		  local db = redis.connect {host=host, port=port, which=which}
		  -- make model.lua work
		  BAMBOO_DB = db
		  setfenv(assert(loadfile('app/handler_entry.lua') or loadfile('../app/handler_entry.lua')), _G)()

		  if not bamboo.MAIN_USER then
			  print("Please use registerMainUser() function to register user module")
			  return
		  end
		  io.write("Username:")
		  local username = io.read("*line")
		  io.write("Password:")
		  --hide password
		  os.execute("stty -echo")
		  local password = io.read("*line")
		  io.write("\n")
		  io.write("Password again:")
		  local password2 = io.read("*line")
		  io.write("\n")
		  os.execute("stty echo")
		  if password ~= password2 then
			  print("Passwords are not equal!")
			  return
		  end
		  local data = {username=username, password=password}
		  local ret, err = bamboo.MAIN_USER:validate(data)
		  if not ret then
			  print("Error!")
			  for _, v in ipairs(err) do
				  print(v)
			  end
			  return
		  end
		  
		  local user = bamboo.MAIN_USER(data)
		  if user:save() then
			  local Perms = require 'bamboo.models.permission'
			  user:addForeign("perms", Perms:getByIndex("_sys_admin_"))
			  print("Add superuser successfully!")
		  else
			  print("Add superuser failly!")
		  end
	  end;

	


}
