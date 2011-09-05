module(..., package.seeall)

local PLUGIN_LIST = bamboo.PLUGIN_LIST



local function findTemplDir( name )
    -- first, find user custom directory
    if USERDEFINED_VIEWS and posix.access(USERDEFINED_VIEWS + name) then
        return USERDEFINED_VIEWS
    -- second, find 'project_dir/views/'
    elseif posix.access( "views/" + name) then
        return "views/"
    -- third, find 'project_dir/plugins/'
    elseif posix.access( "plugins/" + name) then
        return "plugins/"
    else
        error("Template " + name + " does not exist or wrong permissions.")
    end

end

local function removeSnippets(tmpl)
	-- for html
	-- remove all comments except something like <!--[if lg IE 6]> <![endif]-->
	return tmpl:gsub('%<%!%-%-[^%[]?.-[^%]]?%-%-%>', '')
end


local localvars_pattern_list = {
    -- judge whether contains repeatation
    'for%s+([%w_%s,]-)%s+in',
    -- judge whether contains new local variable definations
    'local([%w_%s,]+)=',
}

-- template rendering directives
local VIEW_ACTIONS = {
    -- embeding lua sentances
    ['{%'] = function(code)
        -- add new generated local variable to _G enviroment
        local varstr
        local morestr = " local _env = getfenv();"
        for _, pattern in ipairs(localvars_pattern_list) do
            varstr = code:match(pattern)
            if varstr then
                local varlist = varstr:split(',')
                for _, v in ipairs(varlist) do
                    local t = v:trim()
                    if not isFalse(t) and t ~= '_' then
                        morestr = morestr + (" _env['%s'] = %s; "):format(t, t)
                    end
                end
            end
        end
        
        code = code + morestr
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
                local View = require 'bamboo.view'
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
        local name = unseri(code)
        local tmpl_dir = findTemplDir(name)
        local base_page = io.loadFile(tmpl_dir, name)
        local new_page = removeSnippets(base_page)
        for block in new_page:gmatch("({%[[%s_%w%.%-\'\"]+%]})") do
            -- remove the outer tags
            local block_content = block:sub(3, -3):trim()
            local this_part = this_page:match('{%[%s*======*%s*' + block_content +
            '%s*======*%s+(.-)%s*%]}')

            if this_part then

                this_part = this_part:gsub('%%', '%%%%')
                new_page = new_page:gsub('{%[ *' + block_content + ' *%]}', this_part)
            else
                new_page = new_page:gsub('{%[ *' + block_content + ' *%]}', "")
            end
        end
        
        return new_page
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
            param_str = code:sub(divider_loc + 1)
            
            local tlist = param_str:trim():split(',')
            for i, v in ipairs(tlist) do
                local v = v:trim()
                local var, val = v:splitOut('=')
                var = var:trim()
                val = val:trim()
                assert( var ~= '' )
                assert( val ~= '' )
                
                params[var] = val
            end
            
            return ('_result[#_result+1] = [==[%s]==]'):format(PLUGIN_LIST[plugin_name](params))
        else
            -- if divider_loc is nil, means this plugin has no arguents
            plugin_name = code

            return ('_result[#_result+1] = [==[%s]==]'):format(PLUGIN_LIST[plugin_name]({}))
        end
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
        
        if os.getenv('PROD') then
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

		local tmpl = removeSnippets(tmpl)
		
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
        local tmpl = ('%s{}'):format(tmpl)
        local code = {'local _result, _children = {}, {}\n'}
		local loc_b, loc_e = 1, 0
		local has_script, has_css = false, false
		
		local text, block
		-- :gsub("", ''):gsub("%<style%>.-%</style%>", '')
		
		local script_array = {}
		local script_snippet = ''
		while true do
			loc_b, loc_e, script_snippet  = tmpl:find("(%<script *[%w=\'\"]*%>.-%</script%>)", loc_e + 1)
			if not loc_b then break end
			
			script_array[#script_array + 1] = script_snippet
			tmpl = table.concat({tmpl:sub(1, loc_b - 1), '####SCRIPT_TOBEFILLED####', tmpl:sub(loc_e + 1, -1)})
			loc_e = loc_b - 1
		end
		if #script_array > 0 then has_script = true end

		-- now, script_array contains all script part of a html file

		local css_array = {}
		local css_snippet = ''
		loc_b = 1
		loc_e = 0
		while true do
			loc_b, loc_e, css_snippet  = tmpl:find("(%<style%>.-%</style%>)", loc_e + 1)
			if not loc_b then break end
			
			css_array[#css_array + 1] = css_snippet
			tmpl = table.concat({tmpl:sub(1, loc_b - 1), '####CSS_TOBEFILLED####', tmpl:sub(loc_e + 1, -1)})
			
			loc_e = loc_b - 1
		end
		if #css_array > 0 then has_css = true end
		-- now, script_array contains all script part of a html file
		
		-- render the rest
		for text, block in tmpl:gmatch("([^{]-)(%b{})") do		
			local act = VIEW_ACTIONS[block:sub(1,2)]

			if act then
				code[#code+1] =  '_result[#_result+1] = [==[' + text + ']==]'
				code[#code+1] = act(block:sub(3,-3))
			elseif #block > 2 then
				code[#code+1] = '_result[#_result+1] = [==[' + text + block + ']==]'
			else
				code[#code+1] =  '_result[#_result+1] = [==[' + text + ']==]'
			end
		end
		
        code[#code+1] = 'return table.concat(_result)'
        code = table.concat(code, '\n')
        -- print(code)

        -- restore the script and css part to each fragment
        if has_script then
			local loc_e = 1
			local scripts_tofill = {}
			while true do
				loc_b, loc_e = code:find("####SCRIPT_TOBEFILLED####", loc_e + 1)
				if not loc_b then break end
				
				scripts_tofill[#scripts_tofill + 1] = {loc_b, loc_e}
			end
			
			local frags = {}
			local head = 1
			for i, v in ipairs(scripts_tofill) do
				frags[#frags + 1] = code:sub(head, v[1] - 1)
				frags[#frags + 1] = script_array[i] or ''
				head = v[2] + 1
			end
			if head < #code then
				frags[#frags + 1] = code:sub(head, -1)
			end
			code = table.concat(frags)
		    -- print(code)
		end
		

        -- restroe css part
        if has_css then
			local loc_e = 1
			local css_tofill = {}
			while true do
				loc_b, loc_e = code:find("####CSS_TOBEFILLED####", loc_e + 1)
				if not loc_b then break end
				
				css_tofill[#css_tofill + 1] = {loc_b, loc_e}
			end
			
			local frags = {}
			local head = 1
			for i, v in ipairs(css_tofill) do
				frags[#frags + 1] = code:sub(head, v[1] - 1)
				frags[#frags + 1] = css_array[i] or ''
				head = v[2] + 1
			end
			if head < #code then
				frags[#frags + 1] = code:sub(head, -1)
			end
			code = table.concat(frags)
			-- print(code)
        end
        
        -- compile the whole string code
        local func, err = loadstring(code)

        if err then
            assert(func, err)
        end

        return function(context)
            assert(context, "You must always pass in a table for context.")
            setmetatable(context, {__index=_G})
            setfenv(func, context)
            return func()
        end
    end;
}

return View
