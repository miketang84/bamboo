module(..., package.seeall)

local function login(web, req, e)
	ptable(e)
	ptable(MAIN_USER)
	MAIN_USER:login(e)
	return web:redirect('/admin')--html('../admin/views/login.html')
end

URLS={
	['/admin/login'] = {
		handler = login,
		filters = {'_admin_param_: username passord'},
		-- perms = {'_sys_admin_'}
	},
}