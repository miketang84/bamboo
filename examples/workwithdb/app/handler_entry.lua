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
	
	-- retreive all person instance from db
	local all_persons = MYUser:all()
	
	web:html("result.html", {all_persons = all_persons})
end


URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/form_submit/'] = form_submit,
	
}

