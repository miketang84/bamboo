require 'bamboo'

local View = require 'bamboo.view'

local function index(web, req)
    web:page(View("index.html"){})
end

local function pageb(web, req)
    web:html("index2.html")
end

local function pagec(web, req)
    web:html("index3.html", {})
end

URLS = { '/',
    ['/'] = index,
    ['/index/'] = index,
	['/pageb/'] = pageb,
	['/pagec/'] = pagec,
	
}

