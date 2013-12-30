
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

return _M
