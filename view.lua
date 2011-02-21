module(..., package.seeall)

local TEMPLATES = APP_DIR + "views/"

-- 模板渲染指令
local VIEW_ACTIONS = {
    -- 标记中嵌入lua语句
    ['{%'] = function(code)
        return code
    end,
    -- 标记中嵌入lua变量
    ['{{'] = function(code)
        -- 如果要找的变量不存在，则渲染为空字符串
        if not code then code = "" end
        return ('_result[#_result+1] = %s'):format(code)
    end,
    -- 标记中嵌入文件名字符串，用于包含其它文件
    ['{('] = function(code)
        return ([[             
            if not _children[%s] then
                local View = require 'bamboo.view'
                _children[%s] = View(%s)
            end

            _result[#_result+1] = _children[%s](getfenv())
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
        local base_page = io.loadFile(TEMPLATES, unseri(code))
        local new_page = base_page
        for block in new_page:gmatch("({%[[%s_%w%.%-\'\"]+%]})") do
            -- 获取到里面的内容
            local block_content = block:sub(3, -3):trim()
            -- 再检查自己这个页面中有无与这个block_content配对的实现，一个名字只限定标识一个块
            -- 有的话，就把实现内容取出来
            local this_part = this_page:match('{%[%s*======*%s*' + block_content + '%s*======*%s+(.+)%s*%]}')
            -- 如果this_part有值
            if this_part then
                new_page = new_page:gsub('{%[ *' + block_content + ' *%]}', this_part)
            else
                new_page = new_page:gsub('{%[ *' + block_content + ' *%]}', "")
            end
            
        end
        return new_page
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
        assert(posix.access(TEMPLATES + name), "Template " + TEMPLATES + name + " does not exist or wrong permissions.")

        if os.getenv('PROD') then
            local tmpf = io.loadFile(TEMPLATES, name)
            tmpf = self.preprocess(tmpf)
            return self.compileView(tmpf, name)
        else
            return function (params)
                local tmpf = io.loadFile(TEMPLATES, name)
                assert(tmpf, "Template " + TEMPLATES + name + " does not exist.")
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
