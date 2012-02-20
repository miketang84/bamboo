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

local function form_submit(web, req)
    local params = req.PARAMS
	DEBUG(params)
	
	local person = MYUser(params)
	-- save person object to db
	person:save()

	web:redirect('/result/')
end

local function show(web, req)
	web:page(View('result.html'){})
end

local function paginator_callback(web, req, starti, endi)
	
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

bamboo.registerPluginCallback('page_callback', paginator_callback)

URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/result/'] = show,
	['/form_submit/'] = form_submit,
}

