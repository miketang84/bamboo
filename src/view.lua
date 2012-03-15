module(..., package.seeall)
local lgstring = require "lgstring"


local function getlocals(context)
	local i = 1
	while true do
		local name, value = debug.getlocal(4, i)
		if not name then break end
		context[name] = value
		i = i + 1
	end
	return context
end


local function findTemplDir( name )
    -- second, find 'project_dir/views/'
    if posix.access( "views/" + name) then
        return "views/"
    else
        error("Template " + name + " does not exist or wrong permissions.")
    end
end

-- template rendering directives
local VIEW_ACTIONS = {
    -- embeding lua sentances
    ['{%'] = function(code)
        return code
    end,
    -- embeding lua variables
    ['{{'] = function(code)
        return ('_result[#_result+1] = %s'):format(code)
    end,
    -- containing child template
    ['{('] = function(code)
        return ([[
            if not _children[%s] then
                _children[%s] = View(%s)
            end
            _result[#_result+1] = _children[%s](getfenv())
        ]]):format(code, code, code, code)
    end,
    -- escape tag, to make security
    ['{<'] = function(code)
        return ('local http = require("lglib.http"); _result[#_result+1] = http.escapeHTML(%s)'):format(code)
    end,

    ['{['] = function(code)
        -- nothing now
        return true
    end,
    -- template inheritation syntax
	-- @param code: the base file's name
	-- @param this_page: the master file rendered
    ['{:'] = function(code, this_page)
        local name = deserialize(code)
        local tmpl_dir = findTemplDir(name)
        local base_page = io.loadFile(tmpl_dir, name)
        local starti = 1
        local oi, oj = 1, 0
        local i, j = 1, 0
        local block, matched, block_content
       	local part
       	local parts = {}
        while true do
        	oi, oj, block = base_page:find("({%[[%s_%w%.%-\'\"]+%]})", oj + 1)
        	if oi == nil then break end
            block_content = block:sub(3, -3):trim()
            while true do
            	i, j, matched = this_page:find("(%b{})", j + 1)
--            	DEBUG('-----', i, j, matched)
            	
            	if i == nil then break end
            	part = matched:match('^{%[%s*======*%s*' + block_content +
            '%s*======*%s+(.+)%s*%]}$')
				if part then
					table.insert(parts, base_page:sub(starti, oi-1))
					table.insert(parts, part)
					starti = oj + 1
					break
				end
            end
        end
        table.insert(parts, base_page:sub(starti, -1))

        return table.concat(parts)
    end,

    -- insert plugin
    ['{^'] = function (code)
        local code = code:trim()
        assert( code ~= '', 'Plugin name must not be blank.')
        local divider_loc = code:find(' ')
        local plugin_name = nil
        local param_str = nil
        local params = {}

        if divider_loc then
            plugin_name = code:sub(1, divider_loc - 1)
            param_str = '{' .. code:sub(divider_loc + 1) .. '}'
        else
            -- if divider_loc is nil, means this plugin has no arguments
            plugin_name = code
            param_str = "{}"
        end
        assert(bamboo.PLUGIN_LIST[plugin_name], ('[Error] plugin %s was not registered.'):format(plugin_name))
        return ("_result[#_result+1] = bamboo.PLUGIN_LIST['%s'](%s, getfenv())"):format(plugin_name, param_str)

    end,
    
    ['{-'] = function (code)
		return ""
    end,
}


-- NOTE: the instance of this class is a function
local View = Object:extend {
    __tag = "Bamboo.View";
    __name = 'View';
    ------------------------------------------------------------------------
    --
    -- if ENV[PROD] is true, means it is in production mode, it will only be compiled once
    -- else, it is in develop mode, it will be compiled every request coming in.
    -- @param name:  the name of the template file
    -- @return:  a function, this function can receive a table to finish the rendering procedure
    ------------------------------------------------------------------------
    init = function (self, name)
        local tmpl_dir = findTemplDir(name)
        -- print('Template file dir:', tmpl_dir, name)

		if bamboo.config.PRODUCTION then
            local tmpf = io.loadFile(tmpl_dir, name)
            tmpf = self.preprocess(tmpf)
            return self.compileView(tmpf, name)
        else
            return function (params)
                local tmpf = io.loadFile(tmpl_dir, name)
                assert(tmpf, "Template " + tmpl_dir + name + " does not exist.")
                tmpf = self.preprocess(tmpf)
                return self.compileView(tmpf, name)(params)
            end
        end

    end;

	-- preprocess course
	preprocess = function(tmpl)

		if tmpl:match('{:') then
            -- if there is inherited tag in page, that tag must be put in the front of this file
            local block = tmpl:match("(%b{})")
            local headtwo = block:sub(1,2)
            local block_content = block:sub(3, -3)
            assert(headtwo == '{:', 'The inheriate tag must be put in front of the page.')

            local act = VIEW_ACTIONS[headtwo]
            return act(block_content, tmpl)
        else

            return tmpl
        end
    end;

    ------------------------------------------------------------------------
    -- compile template string to a middle function
    -- use this function to receive a table to finish rendering to html
    --
	-- this snippet is very concise and powerful!
    -- @param tmpl:  template string read from file
    -- @param name:  template file name
    -- @return: middle rendering function
    ------------------------------------------------------------------------
    compileView = function (tmpl, name)
        local tmpl = ('%s{{""}}'):format(tmpl)
        local code = {'local _result, _children = {}, {}\n'}

		-- render the rest
		local text, block, _ret
		for text, block in lgstring.matchtagset(tmpl) do
			local act = VIEW_ACTIONS[block:sub(1,2)]

			if act then
				code[#code+1] =  '_result[#_result+1] = [==[' + text + ']==]'
				_ret = act(block:sub(3,-3))
				assert(type(_ret) == 'string', ("[Error] the returned value type by view rendering tag '%s' is not string."):format(block:sub(1,2)))
				code[#code+1] = _ret
			elseif #block > 2 then
				code[#code+1] = '_result[#_result+1] = [==[' + text + block + ']==]'
			else
				code[#code+1] =  '_result[#_result+1] = [==[' + text + ']==]'
			end
		end

        code[#code+1] = 'return table.concat(_result)'
        code = table.concat(code, '\n')
        -- print('-----', code)
        -- recode each middle view code to request
        if type(name) == 'string' then
        	req.viewcode[name] = code
		end

        -- compile the whole string code
        local func, err = loadstring(code, name)

        if err then
            assert(func, err)
        end

        return function(context)
            assert(type(context) == 'table', "You must always pass in a table for context.")
			if context[1] == 'locals' then  context[1] = nil; context = getlocals(context) end
			-- for global context rendering
			for k, v in pairs(bamboo.context) do
				if not context[k] then
					context[k] = v
				end
			end
			setmetatable(context, {__index=_G})
			setfenv(func, context)
			return func()
        end
    end;
}

return View
