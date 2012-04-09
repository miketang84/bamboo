module (..., package.seeall)

local _args = {}

function helper()
	local params = req.PARAMS
	
	local thepage = tonumber(params.thepage) or 1
	if thepage < 1 then thepage = 1 end
	local totalpages = tonumber(params.totalpages) or 1
	if totalpages and thepage > totalpages then thepage = totalpages end
	local npp = tonumber(params.npp) or tonumber(_args.npp) or 5
	local starti = (thepage-1) * npp + 1
	local endi = thepage * npp
	local pageurl = params.pageurl or _args.pageurl
	local callback = _args.callback
	
	-- the callback should return 2 values: html fragment and totalnum
	local htmlcontent, totalnum = bamboo.getPluginCallbackByName(callback)(web, req, starti, endi)
	
	if totalnum then
		totalpages = math.ceil(totalnum/npp)
		if thepage > totalpages	then thepage = totalpages end
	end
	
	local prevpage = thepage - 1
	if prevpage < 1 then prevpage = 1 end
	local nextpage = thepage + 1
print(nextpage, totalpages)
	if nextpage > totalpages then nextpage = totalpages end

	return {
		['htmlcontent'] = htmlcontent, 
		['totalpages'] = totalpages, 
		['npp'] = npp, 
		['pageurl'] = pageurl, 
		['thepage'] = thepage, 
		['prevpage'] = prevpage, 
		['nextpage'] = nextpage
	}
end


function main(args)

	assert(type(args.pageurl) == 'string', '[Error] pageurl missing in plugin paginator.')
	assert(type(args.callback) == 'string' and type(bamboo.getPluginCallbackByName(args.callback)) == 'function', '[Error] callback missing in plugin paginator.')
	_args = args
	
	return View('../plugins/ajaxpaginator/ajaxpaginator.html') (helper())

end

function jsons(web, req)
	-- fptable(req.PARAMS)
	return web:jsonSuccess(helper())
end
