module(..., package.seeall)

function simpleRender(tmpl_file, params)
	return function (web, req)
		web:html(tmpl_file, params)
	end
end

function simpleRedirect(rurl)
	local rulr = rurl or '/'
	return function (web, req)
		web:redirect(rurl)
	end
end


-- DEBUG level:
-- 0, none;
-- 1, verbose;
-- 2, detailed;
_G['DEBUG'] = function (...)
	
	local printout = function (level, ...)
		for i = 1, select('#', ...) do
			local arg = select (i, ...)
			if type(arg) == 'table' then
				if level >= 2 then
					fptable(arg)
				else
					ptable(arg)
				end
			else
				print(arg)
			end
		end
	end
	
	local debug_level = bamboo.config.debug_level
	if not isFalse(debug_level) then
		local its_type = type(debug_level)
		if its_type == 'boolean' then
			printout(2, ...)
		elseif its_type == 'number' then	
			printout(debug_level, ...)
		end
	end
		
end	
