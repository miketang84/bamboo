require 'bamboo'

local View = require 'bamboo.view'
local Form = require 'bamboo.form'

local MYUser = require 'models.myuser'
bamboo.registerModel(MYUser)

bamboo.registerPlugin('paginator', require "plugins.paginator")



local function index(web, req)
    web:page(View("form.html"){})
end

function paginator(list, npp)

	local length = #list
	local pages = math.ceil(length/npp)
	
	return npp, pages
	
end

--local function form_submit(web, req)
--    local params = req.PARAMS
--	DEBUG(params)
--	
--	local person = MYUser(params)
--	-- save person object to db
--	person:save()
--	
--	local thepage = tonumber(params.thepage) or 1
--	local npp = tonumber(params.npp) or 5
--	
--	local all_persons
--	if not MYUser:existCache('persons_list') then
--		-- retreive all person instance from db
--		all_persons = MYUser:all():sortBy('name')
--		MYUser:setCache('persons_list', all_persons)
--	else
--		DEBUG('entering cache block.')
--		all_persons = MYUser:getCache('persons_list', (thepage-1) * npp + 1, thepage * npp)
--		
--	end
--	fptable(all_persons)
--	local total = MYUser:numCache('persons_list')
--	local pages = math.ceil(total/npp)
--	
--	local prevpage = thepage - 1
--	if prevpage < 1 then prevpage = 1 end
--	local nextpage = thepage + 1
--	if nextpage > pages then nextpage = pages end
--	
--	
--	web:html("result.html", {all_persons = all_persons or {}, npp = npp, pages = pages, thepage = thepage, prevpage = prevpage, nextpage = nextpage })
--end

local function form_submit(web, req)
	
	web:html("result.html")
end

local function form_submit2(web, req, starti, endi)
    local params = req.PARAMS
	DEBUG(params)
	
	local person = MYUser(params)
	-- save person object to db
	person:save()

	
	local all_persons
	if not MYUser:existCache('aa_persons_list') then
		-- retreive all person instance from db
		all_persons = MYUser:all():sortBy('name')
		MYUser:setCache('aa_persons_list', all_persons)
		all_persons = all_persons:slice(starti, endi)
	else
		DEBUG('entering cache block.')
		all_persons = MYUser:getCache('aa_persons_list', starti, endi)
		
	end
	fptable(all_persons)
	local total = MYUser:numCache('aa_persons_list')	
	
	return View("item.html"){all_persons = all_persons}, total
end

bamboo.paginator_callbacks['page_callback'] = form_submit2

URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/form_submit/'] = form_submit,
	['/page/getInstance/'] = form_submit,
}

