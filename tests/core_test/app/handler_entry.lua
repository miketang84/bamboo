require 'bamboo'

local View = require 'bamboo.view'
local Form = require 'bamboo.form'

local MYUser = require 'models.myuser'
bamboo.registerModel(MYUser)
local plugin_paginator = require "plugins.ajaxpaginator"
bamboo.registerPlugin('paginator', plugin_paginator)



local function index(web, req)
    web:page(View("form.html"){})
end


local function form_submit(web, req)
    local params = req.PARAMS
	DEBUG(params)
	
	local person = MYUser(params)
	-- save person object to db
	person:save()

	
	web:redirect("/page/getInstance/")
end

local function show(web, req)
	
	return web:page(View("result.html"){})
end

local function form_submit2(web, req, starti, endi)

	local all_persons
	if not MYUser:existCache('persons_list') then
		-- retreive all person instance from db
		all_persons = MYUser:all():sortBy('name')
		MYUser:setCache('persons_list', all_persons)
		all_persons = all_persons:slice(starti, endi)
	else
--		DEBUG('entering cache block.')
		all_persons = MYUser:getCache('persons_list', starti, endi)
		
	end
--	fptable(all_persons)
	local total = MYUser:numCache('persons_list')	
	
	return View("item.html"){all_persons = all_persons}, total
end

bamboo.registerPluginCallback('page_callback', form_submit2)

function test (web, req)
	local x, y, z = 10, 100, 1000
	
	return web:page(View("test.html"){"locals"})
end

function i_am_query_set(web, req)
	local query_set = MYUser:all()

	return isQuerySet(query_set)
end


URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/form_submit/'] = form_submit,
	['/page/getInstance/'] = show,
	['/page/getInstances/'] = plugin_paginator.jsons,

	-- below for auto test
	['/test/'] = test,
	['/test/i_am_query_set/'] = i_am_query_set,
	
}

