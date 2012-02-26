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

		local MYUser = require 'models.myuser'
		
		context("Global Functions Defined in model.lua", function ()
			test("isClass()", function ()
				assert_equal(isClass(MYUser), true)
			end)
			test("isInstance()", function ()
				local instance = MYUser:get{ id = 1}
				assert_equal(isInstance(instance), true)			
			end)
			test("isQuerySet()", function ()
				local query_set = MYUser:all()
				assert_equal(isQuerySet(query_set), true)
			end)
			
			
			--[[
			local tester = testing.browser("tester")
			local t1 = socket.gettime()
			local ret 
			for i=1, 10000 do
				ret = tester:click("/test")
			end
			local t2 = socket.gettime()
			print(t2 - t1)
			--]]
		end)
		
		context("Assertions", function ()
			test("I_AM_CLASS()", function ()
				local ret, err = pcall(I_AM_CLASS, MYUser)
				assert_equal(ret, true)
			end)
			test("I_AM_INSTANCE()", function ()
				local instance = MYUser:get{ id = 1 }
				local ret, err = pcall(I_AM_INSTANCE, instance)
				assert_equal(ret, true)
			end)
			test("I_AM_QUERY_SET()", function ()
				local query_set = MYUser:all()
				local ret, err = pcall(I_AM_QUERY_SET, query_set)
				assert_equal(ret, true)
			end)
			
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
