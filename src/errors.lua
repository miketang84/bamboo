
module('bamboo.errors', package.seeall)

local View = require 'bamboo.view'

-- Reports errors back to the browser so the user has something to work with.
function reportError(conn, request, err, state)
    local pretty_req = "Request\n " +  serialize(request or {})
    local trace = debug.traceback(state.controller, err)
    local info
    local source = nil

    if state.stateful then
        info = debug.getinfo(state.controller, state.main)
    else
        info = debug.getinfo(state.main)
    end

    if info.source:match("@.+$") then
		-- if code comes from file, display the code lines errored in that file
        source = io.loadLines(info.source:sub(2), info.linedefined, info.lastlinedefined)
    else
        -- if code doesn't come from file, it is a string
		source = info.source
    end
    
    local erroutput = ""
    local target = err:match("%[%w* *\"(%S+)\"%]:")
    local errorlinenum = tonumber(string.match(err, ":(%d+):"))
    if target and errorlinenum then
    	local elines = string.split(request.viewcode[target], '\n')
    	local errorline = elines[errorlinenum]
    	if errorline then
    		erroutput = "[Error] error occured at: " .. (errorline:match("_result%[%#_result%+1%] = (.+)$") or errorline)
		end
    end
    print(erroutput)
    print("[Error]", err)

-- Error info template
local ERROR_PAGE = View.compileView [[
<html><head><title>Bamboo Error</title></head> 
<body>
<p>There was an error processing your request.</p>
<h1>Stack Trace</h1>
<pre>
{{ erroutput }} <br/>
{{ err }}
</pre>
<h1>Source Code</h1>
<pre>
{{ source }}
</pre>
<h1>Request</h1>
<pre>
{{ request }}
</pre>
</body>
</html>
]]

	-- remove the viewcode part to show on page.
	request.viewcode = nil
    local page = ERROR_PAGE {err=trace, source=source, request=pretty_req, erroutput = erroutput}
    conn:reply_http(request, page, 500, "Internal Server Error")
end


function basicError(conn, req, body, code, status, headers)
    headers = headers or {}
    headers['content-type'] = 'text/plain'
    headers['server'] = 'Bamboo on Monserver'

    conn:reply_http(req, body, code, status, headers)
end

