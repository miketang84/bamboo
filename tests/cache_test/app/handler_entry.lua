require 'bamboo'

local View = require 'bamboo.view'
local Form = require 'bamboo.form'

local MYUser = require 'models.myuser'
bamboo.registerModel(MYUser)

local function index(web, req)
    web:page(View("form.html"){})
end

local function form_submit(web, req)
    local params = Form:parse(req)
	DEBUG(params)
	
	local person = MYUser(params)
	-- save person object to db
	person:save()
	
	local all_persons
	if not MYUser:existCache('aapersons_list') then
		-- retreive all person instance from db
		all_persons = MYUser:all():sortBy('name')
		MYUser:setCache('aapersons_list', all_persons)
		DEBUG('-----vvvv---------')
	else
		DEBUG('entering cache block.')
		all_persons = MYUser:getCache('aapersons_list')
		
	end
	
	web:html("result.html", {all_persons = all_persons or {} })
end


URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/form_submit/'] = form_submit,
	
}

