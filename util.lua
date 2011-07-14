module(..., package.seeall)

local http = require 'lglib.http'


function parseQuery(req)
	if req and req.headers and req.headers.QUERY then
		return http.parseURL(req.headers.QUERY)
	else
		return {}
	end
end

    
