
module(..., package.seeall)

local http = require 'lglib.http'
local json = require 'json'


local ENCODING_MATCH = '^%s-([%w/%-]+);*(.*)$'
local URL_ENCODED_FORM = 'application/x-www-form-urlencoded'
local MULTIPART_ENCODED_FORM = 'multipart/form-data'



------------------------------------------------------------------------
-- 解析HTTP头的字符串，返回解析后的table字典表
-- @param head		原始的HTTP header字符串
-- @return result	table字典，head头信息
------------------------------------------------------------------------
local parseHeaders = function (head)
    local result = {}
    head = ('%s\r\n'):format(head)

    for key, val in head:gmatch('%s*(.-):%s*(.-)\r\n') do
        result[key:lower()] = http.parseURL(val, ';')
    end

    return result
end;

------------------------------------------------------------------------
-- 解析HTTP头的字符串，返回解析后的table字典表
-- @param body		原始的HTTP body字符串（注，这个body中包含头信息，详见http协议）
-- @param params	不同部分之间分隔字符串
-- @return result	table字典，head头信息
------------------------------------------------------------------------
local extractMultiparts = function (body, params)
    -- 目前非常简单，需要整个文件都加载到内存中去
    params = ('%s;'):format(params)
    local boundary = ('%%-%%-%s'):format(params:match('^.*boundary=(.-);.*$'):gsub('%-', '%%-'))
    local results = {}

    -- body的不同的part之间以boundary分隔，遍历所有parts
    for part in body:gmatch(('(.-)%s'):format(boundary)) do
        -- 每一个part中，head和piece之间用两个\r\n分隔，piece之后有一个\r\n
        local head, piece = part:match('^(.-)\r\n\r\n(.*)\r\n$')

        if head then
            -- 执行下面的函数之前，head是字符串，执行后，head是table
            head = parseHeaders(head)

            local cdisp = head['content-disposition']
            if cdisp and cdisp.name and cdisp[1] == 'form-data' and not head['content-type'] then
                -- 存储form中有名字的变量值，为一个dict
                results[cdisp.name:match('"(.-)"')] = piece
            else
                head.body = piece
                -- 存储form中无名字的变量值，为一个list
                results[#results + 1] = head
            end
        end
    end

    return results
end;


-- Form类定义
local Form = Object:extend {
    __tag = 'Bamboo.Form';
    
    ------------------------------------------------------------------------
    -- 处理请求中的表单内容，不是很完备
    -- @param req		请求对象
    -- @return result	table字典，head头信息
    ------------------------------------------------------------------------
    parse = function (self, req)
        I_AM_CLASS(self)
        local headers = req.headers
        local params = {}

        if headers.METHOD == 'GET' then
            -- headers.QUERY是请求参数字符串，跟在url后面的
            if headers.QUERY then
                -- params中存储的就是解析后的参数字典
                params = http.parseURL(headers.QUERY)
            end
        elseif headers.METHOD == 'POST' then
            local ctype = headers['content-type'] or ""
            local encoding, encparams = ctype:match(ENCODING_MATCH)
            encoding = encoding:lower()

            if encoding == URL_ENCODED_FORM then
                if req.body then
                    -- POST上传的参数是写在body中的
                    params = http.parseURL(req.body)
                end
            elseif encoding == MULTIPART_ENCODED_FORM then
                params = extractMultiparts(req.body, encparams)
                params.multipart = true
            else
                error(("POST RECEIVED BUT NO CONTENT TYPE WE UNDERSTAND: %s."):format(ctype))
            end
        end
        
        -- params此时已经包含从提交的form中的数据
        params.__session = req.session_id

        return params
    end;

    
    -- 当使用Html5 POST上传时，Upload:process过程不会顾虑到放在URL中的query参数，
	-- 这个时候，就调用这个函数来获取这些额外参数
	-- 上传的时候，不应该调用 Form:parse() 函数来处理文件，而应该使用
	-- process和getURLParams两个函数来获取
	-- deprecated
	parseQuery = function (self, req)
		I_AM_CLASS(self)
		if req.headers.QUERY then
            return http.parseURL(req.headers.QUERY)
        else
            return {}
        end
	end;

    
    -- 对form中的数据进行编码，一般用在testing中
    encode = function (self, data, sep)
        I_AM_CLASS(self)
        local result = {}

        for k,v in pairs(data) do
            result[#result + 1] = ('%s=%s'):format(http.encodeURL(k), http.encodeURL(v))
        end

        return table.concat(result, sep or '&')
    end;

}

return Form
