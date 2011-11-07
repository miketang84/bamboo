require 'bamboo'

local View = require 'bamboo.view'
local Form = require 'bamboo.form'

local function index(web, req)
    web:page(View("form.html"){})
end

local function ajax_submit(web, req)
    local params = Form:parse(req)
	DEBUG(params)
	
	web:json {
		success = true,
		htmls = View('result.html'){results = params},
		-- for play only
		now = os.time()
	}
end



URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/ajax_submit/'] = ajax_submit,

	
}

