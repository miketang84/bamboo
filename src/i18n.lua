
local _M = {}


_M['translate'] = function (sentence)
    local ret
    local lang_code = _G.languageEnv or 'zh-cn'
    local tranelem = bamboo.i18n[sentence]
    if tranelem then
        ret = bamboo.i18n[sentence][lang_code]
    end
    if ret then 
        return ret
    else
        return sentence
    end
	
end

_M['langcode'] = function (req)
    -- here, we like req is a local variable
    -- get the language specified
    local langenv = ''
    --
    local accept_language = req.headers['accept-language'] or req.headers['Accept-Language']
    if not accept_language then langenv = '' end

    if langenv == '' and accept_language then
    	-- such as  zh-cn, en-us, zh-tw, zh-hk
    	langenv = accept_language:match('(%a%a%-%a%a)'):lower();
    end

    -- currently, we define this language environment global variable
    _G.languageEnv = langenv
    
    return langenv
end


return _M
