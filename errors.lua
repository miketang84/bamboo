
module('bamboo.errors', package.seeall)

local View = require 'bamboo.view'

-- 错误信息模板
local ERROR_PAGE = View.compileView [[
<html><head><title>Tir Error</title></head> 
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
    local pretty_req = toString {"Request", request}
    local trace = debug.traceback(state.controller, err)
    local info
    local source = nil

    if state.stateful then
        info = debug.getinfo(state.controller, state.main)
    else
        info = debug.getinfo(state.main)
    end

    if info.source:match("@.+$") then
		-- 如果代码chunk来自文件，就显示这个文件的关于这个出错的函数代码部分
        source = io.loadLines(info.source:sub(2), info.linedefined, info.lastlinedefined)
    else
        -- 如果代码chunk不是来自文件
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

