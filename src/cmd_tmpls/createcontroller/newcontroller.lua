module(..., package.seeall)

local $MODEL = require "models.$CONTROLLER"

local urlprefix = "$CONTROLLER"

-- default methods
newView = function (web, req)

end

editView = function (web, req)

end

delView = function (web, req)

end

getInstance = function (web, req)

end

getInstances = function (web, req)

end

createInstance = function (web, req)

end

updateInstance = function (web, req)

end

delInstance = function (web, req)

end

URLS = {
	["/" + urlprefix + "/newView/"] = newView,
	["/" + urlprefix + "/editView/"] = editView,
	["/" + urlprefix + "/delView/"] = delView,
	["/" + urlprefix + "/getInstance/"] = getInstance,
	["/" + urlprefix + "/getInstances/"] = getInstances,
	["/" + urlprefix + "/createInstance/"] = createInstance,
	["/" + urlprefix + "/updateInstance/"] = updateInstance,
	["/" + urlprefix + "/delInstance/"] = delInstance,

}