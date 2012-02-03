require 'bamboo'

local View = require 'bamboo.view'

local function index(web, req)
    web:page(View("index.html"){})
end

URLS = {
    ['/'] = index,
    ['/index/'] = index,
}

