module(..., package.seeall)

function simpleRender(tmpl_file, params)
	return function (web, req)
		web:html(tmpl_file, params)
	end
end

function simpleRedirect(rurl)
	local rulr = rurl or '/'
	return function (web, req)
		web:redirect(rurl)
	end
end

