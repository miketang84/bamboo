require 'bamboo'

local View = require 'bamboo.view'
local Form = require 'bamboo.form'

local function index(web, req)
    web:page(View("form.html"){})
end

local function form_submit(web, req)
    local params = Form:parse(req)
	DEBUG(params)
	
	web:html("result.html", {results = params})
end


URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/form_submit/'] = form_submit,
	
}

