module(..., package.seeall)






local CHECKBOX_TMPL = [[<input type="checkbox" name="${name}" value="${value}" class="%${class}">${caption} ]]
checkbox = function (args)
	local htmls = ''
	local name = args.name or 'checkbox'
	local class = args.class or 'checkbox'
	local values = args.values or {}
	
	for _, item in ipairs(values) do
		htmls = htmls .. (CHECKBOX_TMPL % { 
			name = name, 
			value = item[1], 
			class = class, 
			caption = item[2] 
		})
	end

	return htmls
end




bamboo.WIDGETS['checkbox'] = checkbox
