local testing = require "bamboo.testing"
local socket = require "socket"

context("Bamboo Core Functions Testing", function ()

	context("Session - session.lua", function ()
			
	end)
	
	context("Web & Request - web.lua", function ()
			
	end)

	context("Form - form.lua", function ()
			
	end)
	

	context("Model - model.lua", function ()
		
		context("All Assertions", function ()
		
			local tester = testing.browser("tester")
			local t1 = socket.gettime()
			local ret 
			for i=1, 10000 do
				ret = tester:click("/test")
			end
			local t2 = socket.gettime()
			print(t2 - t1)
		end)
		
		context("Basic API", function ()
		
		end)
		
		context("Custom API", function ()
		
		end)
		
		context("Cache API", function ()
		
		end)
		
		context("Foreign API", function ()
		
		end)
		
		context("Dynamic Field API", function ()
		
		end)
		
	end)
	
	context("Views - view.lua", function ()
			
	end)
	
	context("Utils - util.lua", function ()
			
	end)
	
	context("Redis Wrapper - redis.lua and redis/*", function ()
			
	end)

	context("MySQL Driver - mysql.lua", function ()
			
	end)
	

end)
