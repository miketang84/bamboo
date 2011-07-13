module(..., package.seeall)

local http = require 'lglib.http'


function parseQuery(self, req)
	I_AM_CLASS(self)
	if req.headers.QUERY then
		return http.parseURL(req.headers.QUERY)
	else
		return {}
	end
end

    
