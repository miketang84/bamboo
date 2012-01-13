local testing = require "bamboo.testing"
local json = require 'json'
local socket = require "socket"

context("View performance benchmark", function ()
	context("test1", function ()
		local tester = testing.browser("tester")
		local t1 = socket.gettime()
		local ret 
		for i=1, 10000 do
			ret = tester:click("/test")
		end
		local t2 = socket.gettime()
		print(t2 - t1)
	end)
end)
