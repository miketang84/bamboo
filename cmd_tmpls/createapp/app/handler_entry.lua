require 'bamboo'

local View = require 'bamboo.view'

local function index(web, req)
    web:page(View("index.html"){})
end

-- 这里必须写成全局变量
URLS = { '/',
    ['/'] = index,
    ['index/'] = index,
}

