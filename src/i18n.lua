
local _M = {}


_M['translate'] = function (sentence, lang_code)
	local ret
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

_M['langCode'] = function (req)
    -- here, we like req is a local variable
    -- get the language specified
    local accept_language = req.headers['accept-language'] or req.headers['Accept-Language']
    if not accept_language then return nil end

    -- first_lang, such as  zh-cn, en-us, zh-tw, zh-hk
    local first_lang = accept_language:match('(%a%a%-%a%a)'):lower();
    
    return first_lang
end


return _M
