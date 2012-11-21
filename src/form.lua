
module(..., package.seeall)

local http = require 'lglib.http'


local ENCODING_MATCH = '^%s-([%w/%-]+);*(.*)$'
local URL_ENCODED_FORM = 'application/x-www-form-urlencoded'
local MULTIPART_ENCODED_FORM = 'multipart/form-data'




--- parse http headers, transform it to lua table
-- @param head:	original HTTP header string
-- @return result: lua table
local parseHeaders = function (head)
    local result = {}
    head = ('%s\r\n'):format(head)

    for key, val in head:gmatch('%s*(.-):%s*(.-)\r\n') do
        result[key:lower()] = http.parseURL(val, ';')
    end

    return result
end;


--- parse multipart form string format
-- now it's very simple, load whole file into memory
-- @param body:		original HTTP body string
-- @param sepstr:	
-- @return result:	
local extractMultiparts = function (body, sepstr)
    sepstr = ('%s;'):format(sepstr)
    local boundary = ('%%-%%-%s'):format(sepstr:match('^.*boundary=(.-);.*$'):gsub('%-', '%%-'))
    local results = {}

    -- body use boundary to seperate each part，iterate them
    for part in body:gmatch(('(.-)%s'):format(boundary)) do
        -- in every part, head and piece are divided by two '\r\n'，piece has one '\r\n' followed it
        local head, piece = part:match('^(.-)\r\n\r\n(.*)\r\n$')

        if head then
            head = parseHeaders(head)

            local cdisp = head['content-disposition']
            if cdisp and cdisp.name and cdisp[1] == 'form-data' and not head['content-type'] then
                -- store named variable in form，as a dict
                results[cdisp.name:match('"(.-)"')] = piece
            else
                head.body = piece
                -- store none named variable in form, as a list
                results[#results + 1] = head
            end
        end
    end

    return results
end;


local Form = Object:extend {
    parse = function (self, req)
        I_AM_CLASS(self)
        local headers = req.headers
        local method = req.method
        local query_string = req.query_string
        local body = req.body
        local params = {}

        if method == 'GET' then
            if query_string then
                -- params is the dictory of query
                params = http.parseURL(query_string)
            end
        elseif method == 'POST' then
            local ctype = headers['content-type'] or ""
            local encoding, encparams = ctype:match(ENCODING_MATCH)
            if encoding then encoding = encoding:lower() end

            if encoding == URL_ENCODED_FORM then
                if body then
                    -- POST data is placed in body
                    params = http.parseURL(body)
                end
            elseif encoding == MULTIPART_ENCODED_FORM then
                params = extractMultiparts(body, encparams)
                params.multipart = true
            else
                -- for other format case
				--print(("POST RECEIVED BUT NO CONTENT TYPE WE UNDERSTAND: %s."):format(ctype))
            end
        end
        
        return params
    end;

	parseQuery = function (self, req)
		I_AM_CLASS(self)
		if req.query_string then
            return http.parseURL(req.query_string)
        else
            return {}
        end
	end;

    
    encode = function (self, data, sep)
        I_AM_CLASS(self)
        local result = {}

        for k,v in pairs(data) do
            result[#result + 1] = ('%s=%s'):format(http.encodeURL(tostring(k)), http.encodeURL(tostring(v)))
        end

        return table.concat(result, sep or '&')
    end;

}

return Form
