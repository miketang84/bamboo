# Filters
As said before, you can bind a function called handler to the url. But in many cases, those handlers may contain similar codes, such as judge if user is logined. To escape from 'WET', you can use filters. For example:

	local function checkLogined(extra, params)
		if req.user then
			return true, params
		else
			web:page('Please login!')
			return false
		end
	end
	
	bamboo.registerFilter('login', checkLogined)
	
	URLS = {
		['/'] = {
			handler = index,
			filters = {'login'}
		}
	}

In this way, a filter called login is added to the handler `index`, every time `/` is visited, bamboo will get execute the function checkLogined, only if it returns true, execute handler. So, if unlogined, user cannot get the content of `/`.  
If there are more than one filters, they will be executed by order. For example, `filters = {'filterA', 'filterB'}`, the order is `filterA` -> `filterB`. Parameters can be transferred from `filterA` to `filterB`, `filterA` returns `true`, `params`, and `filterB` get `params` as second parameter. Handler will recieve the third parameter from the last filter.   
The first parameter of a filter function is input from filters table. For example, `filters = {'filter: extraA extraB'}`, then `extra = {'extraA', 'extraB'}`.  
Also, there are post filters executed after handler. The format is just like filter. For example:

	URLS = {
		['/'] = {
			handler = index,
			filters = {'login'},
			post_filters = {'postfilterA', 'postfilterB'}
		}
	}

So the execute order is `login` -> `index` -> `postfilterA` -> `postfilterB`.
