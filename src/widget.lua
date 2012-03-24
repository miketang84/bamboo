module(..., package.seeall)



local TEXT_TMPL = [[<input type="text" name="${name}" value="${value}" class="${class}" /> ]]
text = function (args)
	local name = args.name or 'text'
	local class = args.class or 'text'
	local value = args.value or ''
	
	local htmls = (TEXT_TMPL % { 
		name = name, 
		value = value, 
		class = class, 
	})

	return htmls
end




local CHECKBOX_TMPL = [[<input type="checkbox" name="${name}" value="${value}" ${checked} class="${class}">${caption} ]]
checkbox = function (args)
	local htmls = {}
	local name = args.name or 'checkbox'
	local class = args.class or 'checkbox'
	local value = args.value or {}
	local checked_list = args.checked or {}
	
	local checked_set = Set(checked_list)
	
	for _, item in ipairs(value) do
		table.insert(htmls, (CHECKBOX_TMPL % { 
			name = name, 
			value = item[1], 
			class = class, 
			caption = item[2] or '',
			checked = checked_set:has(item[1]) and 'checked="checked"' or ''
		}))
	end

	return table.concat(htmls)
end



bamboo.WIDGETS['text'] = text
bamboo.WIDGETS['checkbox'] = checkbox
