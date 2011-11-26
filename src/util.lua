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

-- to return a html fragment, which was constructed with ul and li
-- with specified id name and class name, for page rendering
-- This algorithm only supports closest arrange method.
function makeNavigator(site_map)
	local navi_htmls = '<ul class="bamboo_navigator">'
	
	if #site_map > 0 then
		navi_htmls = navi_htmls + ([[<li><a href="%s">%s</a>]]):format(site_map[1].pathkey, site_map[1].title)
	end
	i = 2
	while i <= #site_map do
		local cur_item = site_map[i]
		local prev_item = site_map[i-1]
		if cur_item.rank == prev_item.rank then
			navi_htmls = navi_htmls + ([[</li><li><a href="%s">%s</a>]]):format(cur_item.pathkey, cur_item.title)
		elseif cur_item.rank > prev_item.rank then
			navi_htmls = navi_htmls + ([[<ul><li><a href="%s">%s</a>]]):format(cur_item.pathkey, cur_item.title)
		elseif cur_item.rank < prev_item.rank then
			navi_htmls = navi_htmls + '</li>'
			delta = prev_item.rank - cur_item.rank
			for n = 1, delta do
				navi_htmls = navi_htmls + '</ul></li>'
			end
			navi_htmls = navi_htmls + ([[<li><a href="%s">%s</a>]]):format(cur_item.pathkey, cur_item.title)
		end
		
		i = i + 1
	end
	
	if site_map[#site_map].rank > 1 then
		local delta = site_map[#site_map].rank - 1
		navi_htmls = navi_htmls + string.rep('</li></ul>',  delta)
	end
	
	if navi_htmls then navi_htmls = navi_htmls + '</li>' end
	navi_htmls = navi_htmls + '</ul>'
	
	-- print(navi_htmls)
	return navi_htmls
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
