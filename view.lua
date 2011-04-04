module(..., package.seeall)

local PLUGIN_LIST = bamboo.PLUGIN_LIST
local tmpl_dir = './'

-- 模板渲染指令
local VIEW_ACTIONS = {
    -- 标记中嵌入lua语句
    ['{%'] = function(code)
        return code
    end,
    -- 标记中嵌入lua变量
    ['{{'] = function(code)
        -- 如果要找的变量不存在，则渲染为空字符串，这只一句目前只能处理{{}}
        -- 这样的情况，而并不能处理变量不存在的情况
        -- 可以通过执行pcall(loadstring())来检查一个变量是否存在
        if not code then code = '""' end
        return ('_result[#_result+1] = %s'):format(code)
    end,
    -- 标记中嵌入文件名字符串，用于包含其它文件
    ['{('] = function(code)
        return ([[       
            if not _children[%s] then
                local View = require 'bamboo.view'
                _children[%s] = View(%s)
            end
            -- getfenv()，用于传递当前函数所在环境，默认即全局变量
            local env = getfenv()
            -- 6和7只是经验值，目前还无法找出一个更好的办法来将局部变量（不同情况下名字不同）扩充到
            -- 全局环境中去。这里这几个语句主要是抽取泛型for中的暴露出来的局部变量
            local kstr, kstr_val = debug.getlocal(1, 6)
            local vstr, vstr_val = debug.getlocal(1, 7)
            --print(kstr, kstr_val)
            --print(vstr, vstr_val)
            if kstr and vstr then 
                if type(kstr_val) == 'number' or type(kstr_val) == 'string' then
                    if type(vstr_val) == 'string' or type(vstr_val) == 'table' then
                        env[kstr] = kstr_val
                        env[vstr] = vstr_val
                    end
                end
            end
            
            _result[#_result+1] = _children[%s](env)
        ]]):format(code, code, code, code)
    end,
    -- 标记中嵌入转义后的html代码，安全措施
    ['{<'] = function(code)
        return ('_result[#_result+1] = http.escapeHTML(%s)'):format(code)
    end,
    
    ['{['] = function(code)
        -- nothing now
        return true
    end,
    -- 在这个函数中，传进来的code就是被继承的基页名称
    ['{:'] = function(code, this_page)
        local base_page = io.loadFile(tmpl_dir, unseri(code))
        local new_page = base_page
        for block in new_page:gmatch("({%[[%s_%w%.%-\'\"]+%]})") do
            -- 获取到里面的内容
            local block_content = block:sub(3, -3):trim()
            -- 再检查自己这个页面中有无与这个block_content配对的实现，一个名字只限定标识一个块
            -- 有的话，就把实现内容取出来
            local this_part = this_page:match('{%[%s*======*%s*' + block_content + '%s*======*%s+(.+)%s*%]}')
            -- 如果this_part有值
            if this_part then
                -- gsub的第二个参数，将会识别模式匹配，所以要将%变成%%才行。
                -- gsub应该提供一个附加参数，以判断是否识别模式匹配，不然一点都不方便
                this_part = this_part:gsub('%%', '%%%%')
                new_page = new_page:gsub('{%[ *' + block_content + ' *%]}', this_part)
            else
                new_page = new_page:gsub('{%[ *' + block_content + ' *%]}', "")
            end
        end
        
        return new_page
    end,
    
    -- {^ 插件名称  参数1=值1, 参数2=值2, ....^}
    ['{^'] = function (code)
        local code = code:trim()
        assert( code ~= '', 'Plugin name must not be blank.')
        local divider_loc = code:find(' ')
        local plugin_name = nil
        local param_str = nil
        local params = {}
        
        if divider_loc then
            -- 如果找到了
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
            
            return ('_result[#_result+1] = [[%s]]'):format(PLUGIN_LIST[plugin_name](params))
        else
            -- 如果divider_loc是nil, 表明插件不带参数
            plugin_name = code
            -- 注：下面那个%s两边的引号必不可少，因为要被认成字符串
            return ('_result[#_result+1] = [[%s]]'):format(PLUGIN_LIST[plugin_name]({}))
        end
    end,
    
}


-- 注：此类的实例是一个View函数，用于接收表参数产生具体的页面内容。
local View = Object:extend {
    __tag = "Bamboo.View";
    __name = 'View';
    ------------------------------------------------------------------------
    -- 从默认的TEMPLATES路径中找到文件name，进行模板渲染
    -- 如果ENV[PROD]有值，表示在产品模式中，那么它只会编译一次
    -- 否则，就是在开发模式中，于是会在每次调用那个函数的时候，都会被编译。
    -- @param name 模板文件名
    -- @return 一个函数 这个函数在后面的使用中接收一个table作为参数，以完成最终的模板渲染
    ------------------------------------------------------------------------
    init = function (self, name) 
        -- 首先，找用户指定路径
        if USERDEFINED_VIEWS and posix.access(USERDEFINED_VIEWS + name) then
            tmpl_dir = USERDEFINED_VIEWS
        -- 第二，找工程下的views目录
        elseif posix.access( APP_DIR + "views/" + name) then
            tmpl_dir = APP_DIR + "views/"
        -- 第三，找工程下的plugins目录
        elseif posix.access( APP_DIR + "plugins/" + name) then
            tmpl_dir = APP_DIR + "plugins/"
        else
            error("Template " + tmpl_dir + name + " does not exist or wrong permissions.")
        end
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
    
    preprocess = function(tmpl)
        -- 如果页面中有继承符号（继承符号必须写在最前面）
        if tmpl:match('{:') then
            local block = tmpl:match("(%b{})")
            local headtwo = block:sub(1,2)
            local block_content = block:sub(3, -3)
            assert(headtwo == '{:', 'The inheriate tag must be put in front of the page.') 

            local act = VIEW_ACTIONS[headtwo]
            return act(block_content, tmpl)
        -- 如果页面没有继承，则直接返回
        else
            return tmpl
        end
    end;
    
    ------------------------------------------------------------------------
    -- 将一个模板字串解析编译，生成一个函数，这个函数代码中包含了这个模板的所有中间信息，
    -- 进而最终转换成浏览器识别的html字串。
    -- 返回一个函数，这个函数必须以一个table作为参数传入，以对其中的参数进行填充，
    -- 这段代码设计得相当巧妙，值得仔细品味。
    -- @param tmpl 模板字符串，是从存储空间加载到内存中的模板数据
    -- @param name 模板文件名
    -- @return 一个函数 这个函数在后面的使用中接收一个table作为参数，以完成最终的模板渲染
    ------------------------------------------------------------------------
    compileView = function (tmpl, name)
        local tmpl = ('%s{}'):format(tmpl)
        local code = {'local _result, _children = {}, {}\n'}

        for text, block in tmpl:gmatch("([^{]-)(%b{})") do
            local act = VIEW_ACTIONS[block:sub(1,2)]

            if act then
                code[#code+1] =  '_result[#_result+1] = [[' + text + ']]'
                code[#code+1] = act(block:sub(3,-3))
            elseif #block > 2 then
                code[#code+1] = '_result[#_result+1] = [[' + text + block + ']]'
            else
                code[#code+1] =  '_result[#_result+1] = [[' + text + ']]'
            end
        end

        code[#code+1] = 'return table.concat(_result)'

        code = table.concat(code, '\n')
        --print(code:sub(1, 3000))
        local func, err = loadstring(code, name)

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
