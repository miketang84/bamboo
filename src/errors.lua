
module('bamboo.errors', package.seeall)

local View = require 'bamboo.view'

-- Error info template
local ERROR_PAGE = View.compileView [[
<html><head><title>Bamboo Error</title></head> 
<body>
<p>There was an error processing your request.</p>
<h1>Stack Trace</h1>
<pre>
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

-- Reports errors back to the browser so the user has something to work with.
function reportError(conn, request, err, state)
    local pretty_req = "Request\n " +  seri(request or {})
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
        -- if code doesn't come from file
		source = info.source
    end

    local page = ERROR_PAGE {err=trace, source=source, request=pretty_req}
    conn:reply_http(request, page, 500, "Internal Server Error")
    print("ERROR", err)

end


function basicError(conn, req, body, code, status, headers)
    headers = headers or {}
    headers['content-type'] = 'text/plain'
    headers['server'] = 'Bamboo on Mongrel2'

    conn:reply_http(req, body, code, status, headers)
end

