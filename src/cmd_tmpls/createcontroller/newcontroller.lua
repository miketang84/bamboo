module(..., package.seeall)

local $MODEL = require "models.$CONTROLLER"

local urlprefix = "$CONTROLLER"

-- default methods
newview = function (web, req)

end

editview = function (web, req)

end

delview = function (web, req)

end

item = function (web, req)

end

list = function (web, req)

end

create = function (web, req)

end

update = function (web, req)

end

delete = function (web, req)

end

URLS = {
	["/" + urlprefix + "/newview/"] = newview,
	["/" + urlprefix + "/editview/"] = editview,
	["/" + urlprefix + "/delview/"] = delview,
	["/" + urlprefix + "/item/"] = item,
	["/" + urlprefix + "/list/"] = list,
	["/" + urlprefix + "/create/"] = create,
	["/" + urlprefix + "/update/"] = update,
	["/" + urlprefix + "/delete/"] = delete,

}
