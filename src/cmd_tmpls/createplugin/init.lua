module(..., package.seeall)

local View = require 'bamboo.view'

function main()
	local i = 0
	local str = ''
	for i=1, 100, 10 do
		str = ('%s %s'):format(str, tostring(i))
	end

	return View('testplugin/testplugin.html'){ onetwo = str }
end

URLS = {
	['xxxxx/xxxxx/'] = main
}
