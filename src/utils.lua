module(..., package.seeall)

function simpleRender(tmpl_file, params)
	return function (web, req)
		web:html(tmpl_file, params)
	end
end

function simpleRedirect(rurl)
	local rulr = rurl or '/'
	return function (web, req)
		web:redirect(rurl)
	end
end


-- DEBUG level:
-- 0, none;
-- 1, verbose;
-- 2, detailed;
_G['DEBUG'] = function (...)
	
	local printout = function (level, ...)
		for i = 1, select('#', ...) do
			local arg = select (i, ...)
			if type(arg) == 'table' then
				if level >= 2 then
				    print(table.tree(arg))
				else
					for k, v in pairs(arg) do
						print(k, v)
					end
				end
			else
				print(arg)
			end
			print('')
		end
	end
	
	local info = debug.getinfo(2, "nS")
	local debug_level = bamboo.config.debug_level
	if not isFalse(debug_level) then
		print('')
		print('-----------------------------------------------')	
		print(('DEBUG @%s,  @%s,  @%s'):format(tostring(info.short_src), tostring(info.linedefined), tostring(info.name)))
		print('...............................................')
	
		local its_type = type(debug_level)
		if its_type == 'boolean' then
			printout(2, ...)
		elseif its_type == 'number' then	
			printout(debug_level, ...)
		end
		print('^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^')
	end
end	


function readSettings(config)
	local config = config or {}
  
	-- try to load settings.lua 
	local setting_file = loadfile('settings.lua') or loadfile('../settings.lua')
	if setting_file then
		setfenv(assert(setting_file), config)()
	end
	config.bamboo_dir = config.bamboo_dir or '/usr/local/share/lua/5.1/bamboo/'

	-- check whether have a global production setting
	local production = loadfile('/etc/bamboo_production')
	if production then
		config.PRODUCTION = true
	end

	return config
end
