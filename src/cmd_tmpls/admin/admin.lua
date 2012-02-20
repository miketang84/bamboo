module(..., package.seeall)

local Form = require 'bamboo.form'
local View = require 'bamboo.view'
local Session = require 'bamboo.session'
-- local pic = require 'lib.pic'
local Image = require 'bamboo.models.image'
local Upload = require 'bamboo.models.upload'
--local getpy = require 'app.py'

local function _admin_param_(a, e)
	print('admin checking params')
	local params = Form:parse(req)
	local query = Form:parseQuery(req)

	e = e or {}
	if not isFalse(extra) then
		for _, v in ipairs(extra) do
			if not params[v] or params[v] == '' then 
				if not query[v] or query[v] == '' then
					return web:page('请正确的输入参数')
				end
			end
		end
	end

	for k, v in pairs(params) do
		e[k] = v
	end

	for k, v in pairs(query) do
		e[k] = v
	end
	
	return true, e
end

local function _admin_logined_(a, e)
	if req.user then
		return true, e
	else
		web:html('../admin/views/login.html')
		return false
	end
end


bamboo.registerFilter('_admin_param_', _admin_param_)
bamboo.registerFilter('_admin_logined_', _admin_logined_)

bamboo.registerPermission(
						  '_sys_admin_', 
						  'The permission of admin', 
						  function()
							  web:html('../admin/views/login.html')
							  return false
						  end)

local admin_unlogined = require 'admin.admin_unlogined'
bamboo.registerModule(admin_unlogined)

function admin_entry(web, req, e)
	web:page(View('../admin/views/index.html'){models = bamboo.MODEL_LIST, user=req.user[req.user.__indexfd]})
end

local function getInstances(web, req, e)
	local m = bamboo.getModelByName(e.__tag)
	local instances = m:all()
	
	-- ptable(m)

	return web:page(View('../admin/views/instances.html'){instances = instances, fields = m.__fields, __tag = e.__tag})
end

local function def(web, req, e)
	return web:html('../admin/media/views/' .. req.path:sub(1, -2))
end

local function judge(condition, val_true, val_false)
	if condition then 
		return val_true
	end
	return val_false
end

local function slice(web, req, e)
	local m = bamboo.getModelByName(e.__tag)
	local instances = m:slice((e.pageNum-1) * e.numPerPage + 1 , e.pageNum * e.numPerPage)
	
	local totalPages = math.ceil(m:numbers()/e.numPerPage)

	return web:page(View('../admin/views/instances.html'){
						instances = instances, 
						fields = m.__fields,
						__tag = e.__tag, 
						totalCount = m:numbers(),
						currentPage = e.pageNum,
						numPerPage = e.numPerPage,
						pageNumShown = judge(totalPages>10, 10, totalPages)
					})
end

local function edit(web, req, e)
	local m = bamboo.getModelByName(e.__tag)
	local instance = m:getById(e.id)
	
	return web:page(View('../admin/views/edit.html'){
						instance = instance,
						fields = m.__fields,
						__tag = e.__tag,
						instance_id = e.id,
					})
end

local function add(web, req, e)
	local m = bamboo.getModelByName(e.__tag)
	
	local instance
	if m.__tag:startsWith('Bamboo.Model.Upload') then
		instance = m{path = Session:getKey('_upload_file_') or nil}
	else
		instance = m{}
	end
	-- ptable(instance)

	return web:page(View('../admin/views/add.html'){
						instance = instance,
						fields = m.__fields,
						__tag = e.__tag,
						id = e.id,
					})
end

local function deleteSelect(web, req, e)
	fptable(e)
	local m = bamboo.getModelByName(e.__tag)
	if e.instances then
		for _, v in ipairs(e.instances) do
			local instance = m:getById(v)
			if instance then
				instance:del()
			end
		end
	end
	return web:jsonSuccess{}
end

local function filter(web, req, e)
	local m = bamboo.getModelByName(e.__tag)
	fptable(e)
	-- loadstring(e.filterParams)()
	-- local field = e.filterField

	local operators = {
		['=contains'] = '⊃',
		['=uncontains'] = '⊅',
		['=eq'] = '=',
		['=uneq'] = '&ne;',
		['=gt'] = '&gt;',
		['=lt'] = '&lt;',
		['=le'] = '≤',
		['=ge'] = '≥',
		-- ['=bt'] = 'Belongs to',
		-- ['=be'] = 'Belongs to or equal',
		-- ['=outside'] = 'Outside',
		-- ['=startsWith'] = 'Starts with',
		-- ['=unstartsWith'] = 'Does not start with',
		-- ['=endsWith'] = 'Ends with',
		-- ['=unendsWith'] = 'Does not end with',
	}

	local filter_param = ('_ADMIN_FILTER_PARAMS_={%s%s("%s")}'):format(e.filterField or '', e.operator or '', e.value or '')
	print('filter_param:', filter_param)
	loadstring(filter_param)()

	local instances
	if isFalse(_ADMIN_FILTER_PARAMS_) then instances =  m:all() else instances = m:filter(_ADMIN_FILTER_PARAMS_) end
	local totalCount = #instances
	local totalPages = math.ceil((totalCount)/e.numPerPage)

	instances = instances:slice((e.pageNum-1) * e.numPerPage + 1 , e.pageNum * e.numPerPage)
	
	return web:page(View('../admin/views/instances.html'){
						instances = instances, 
						fields = m.__fields,
						__tag = e.__tag, 
						totalCount = totalCount,
						totalPage = totalPages,
						currentPage = e.pageNum,
						numPerPage = e.numPerPage,
						operators = operators,
						filterField = e.filterField or '',
						operator = e.operator or '',
						value = e.value or '',
						pageNumShown = judge(totalPages>10, 10, totalPages)
					})	
end

local function create(web, req, e)
	local tag = e.__tag
	e.__tag = nil
	local model = bamboo.getModelByName(tag)
	e.id = nil
	e['_'] = nil

	ptable(e)
	
	local ret, err_msg = model:validate(e)
	if not ret then
		-- for _, v in ipairs(err_msg) do
		-- 	print(v)
		-- end
		local data = {
			["statusCode"] = "300",
			["message"] = "修改信息出错!<br/>" .. table.concat(err_msg, '<br/>'),
			["navTabId"] = tag,
			["rel"] = "",
			["callbackType"] = "",--closeCurrent",
			["forwardUrl"] = ""
		}
		return web:json(data)
	end
	
	local instance = model(e)
	if instance then
		for k, v in pairs(e) do
			print('_____', k)
			if model.__fields[k].foreign then
				if model.__fields[k].widget_type == 'foreign' then
					local foreign_model = bamboo.getModelByName(model.__fields[k].foreign)
					-- print('foreign', k)
					if model.__fields[k].st == 'ONE' then
						-- print('<<<<<')
						if tonumber(v) <= 0 then
							local foreign_instance = instance:getForeign(k)
							if foreign_instance then
								instance:delForeign(k, foreign_instance)
							end
						else
							instance:addForeign(k, foreign_model:getById(v))
						end
					elseif model.__fields[k].st == 'MANY' then
						assert(type(v)=='table', '[Error] It is not a table')
						local foreign_instances = foreign_model:all()
						-- print('>>>>>>>>')
						-- fptable(foreign_instances)
						for _, foreign_instance in ipairs(foreign_instances) do
							local eq = false
							for _, foreign_id in ipairs(v) do
								if foreign_instance.id == foreign_id then
									eq = true
								end
							end
							if eq then
								instance:addForeign(k, foreign_instance)
							else
								instance:delForeign(k, foreign_instance)
							end
						end
					end
				end
			end
		end
	end
	instance:save()

	local data = {
		["statusCode"] = "200",
		["message"] = "添加成功",
		["navTabId"] = tag,
		["rel"] = "",
		["callbackType"] = "closeCurrent",
		["forwardUrl"] = ""
	}
	return web:json(data)	
end

local function update(web, req, e)
	-- fptable(e)
	
	local tag = e.__tag
	e.__tag = nil
	local id = e.id
	e.id = nil
	e['_'] = nil

	local model = bamboo.getModelByName(tag)
	local instance = model:getById(id)

	-- print('instance')
	-- fptable(instance)
	local ret, err_msg = model:validate(e)
	if not ret then
		-- for _, v in ipairs(err_msg) do
		-- 	print(v)
		-- end
		local data = {
			["statusCode"] = "300",
			["message"] = "修改信息出错!<br/>" .. table.concat(err_msg, '<br/>'),
			["navTabId"] = tag,
			["rel"] = "",
			["callbackType"] = "",--closeCurrent",
			["forwardUrl"] = ""
		}
		return web:json(data)
	end
	
	if instance then
		for k, v in pairs(e) do
			-- print(k)
			if model.__fields[k].foreign then
				local foreign_model = bamboo.getModelByName(model.__fields[k].foreign)
				-- print('foreign', k)
				if model.__fields[k].st == 'ONE' then
					-- print('<<<<<')
					if tonumber(v) <= 0 then
						local foreign_instance = instance:getForeign(k)
						if foreign_instance then
							instance:delForeign(k, foreign_instance)
						end
					else
						instance:addForeign(k, foreign_model:getById(v))
					end
				elseif model.__fields[k].st == 'MANY' then
					-- assert(type(v)=='table', '[Error] It is not a table')
					if type(v)=='table' then
						local foreign_instances = foreign_model:all()
						-- print('>>>>>>>>')
						-- fptable(foreign_instances)
						for _, foreign_instance in ipairs(foreign_instances) do
							local eq = false
							for _, foreign_id in ipairs(v) do
								if foreign_instance.id == foreign_id then
									eq = true
								end
							end
							if eq then
								instance:addForeign(k, foreign_instance)
							else
								instance:delForeign(k, foreign_instance)
							end
						end
					end
				end
			else
				-- print('______', k ,v)
				instance:update(k, v)
			end
		end
	end
	
	local data = {
		["statusCode"] = "200",
		["message"] = "修改信息成功",
		["navTabId"] = tag,
		["rel"] = "",
		["callbackType"] = "closeCurrent",
		["forwardUrl"] = ""
	}
	return web:json(data)	
end

local function delete(web, req, e)
	local model = bamboo.getModelByName(e.__tag)
	local instance = model:getById(e.id)
	
	instance:del()

	local data = {
		["statusCode"] = "200",
		["message"] = "删除成功",
		["navTabId"] = tag,
		["rel"] = "",
		["callbackType"] = "forword",
		["forwardUrl"] = ""
	}
	return web:json(data)	
end

local function validate(web, req, e)
	local data = {
		["statusCode"] = "200",
		["message"] = "\u64cd\u4f5c\u6210\u529f",
		["navTabId"] = "",
		["rel"] = "",
		["callbackType"] = "closeCurrent",
		["forwardUrl"] = ""
	}
	return web:json(data)
end

local function upload(web, req, e)
	-- local newfile, result_type = Image:process(web, req, nil, nil, nil, function() return req.session.session_id .. os.time() end)

	-- if result_type == 'single' then
	-- elseif result_type == 'multiple' then
	-- end
	
	-- if not newfile then 
	-- 	return web:jsonError(200, '上传文件失败')
	-- end

	-- local im_src = pic.guessPhotoFormat(newfile.path)
	-- local x, y = im_src:sizeXY()
	-- newfile.width = x
	-- newfile.height = y
	-- -- newfile:save()
	-- local ny = x
	-- local nx = y
	-- local im_des = gd.createTrueColor(nx, ny)

	-- im_des:copyResampled(im_src, 0, 0, 0, 0, nx, ny, x, y)
	-- -- 分离文件的文件名和扩展名
	-- local newpath = newfile.path
	-- -- local main, ext = newpath:match('^(.+)(%.%w+)$')
	-- local main = newpath
	-- -- main = main + '_middle'
	-- newpath = main + '.png'
	-- print(main)
	-- local mainname = main:match('/([^:%(%)/]+)$')
	-- -- 存储文件到磁盘上
	-- im_des:png(newpath)
	-- -- 删除原文件
	-- os.execute('rm ' .. newfile.path)

	local newfile, result_type = Upload:process(web, req)
	Session:setKey('_upload_file_', newfile.path)
	
	
	-- -- 记录到数据库中
	-- newfile = Image {
	-- 	-- name = tostring(os.time()) .. '.png',
	-- 	name = mainname .. '.png',
	-- 	path = newpath,
	-- 	width = nx,
	-- 	height = ny
	-- }
	-- ptable(newfile)
	-- newfile:save()

	return web:jsonSuccess{}
end

local function logout(web, req, e)
	bamboo.MAIN_USER:logout()
	return web:redirect('/admin')
end

function init()
	local flag = bamboo.executeFilters{'_admin_logined_'} and bamboo.executePermissionCheck{'_sys_admin_'}
	-- local flag = true
	return flag
end

function finish()
	return true
end

function test()
	-- print(getpy('测试'))
	return web:html('test.html', {instance=req.user})
end

URLS = {
	['/'] = {
		handler = admin_entry,
	},
	['getinstances'] = {
		handler = getInstances,
		filters = {'_admin_param_: __tag'},
	},
	['slice'] = {
		handler = slice,
		filters = {'_admin_param_: __tag status pageNum numPerPage'}
	},
	['filter'] = {
		handler = filter,
		filters = {'_admin_param_: __tag pageNum numPerPage params'},
	},
	['validate'] = {
		handler = validate,
		filters = {},
	},
	['edit'] = {
		handler = edit,
		filters = {'_admin_param_: __tag id'},
	},
	['update'] = {
		handler = update,
		filters = {'_admin_param_: __tag id'},
	},
	['add'] = {
		handler = add,
		filters = {'_admin_param_: __tag'},
	},
	['create'] = {
		handler = create,
		filters = {'_admin_param_: __tag id'},
	},
	['delete'] = {
		handler = delete,
		filters = {'_admin_param_: __tag id'},
	},
	['deleteselect'] = {
		handler = deleteSelect,
		filters = {'_admin_param_: __tag instances'}
	},
	['upload'] = {
		handler = upload,
	},
	['logout'] = {
		handler = logout,
	},
	['test'] = test,
	-- ['[%w_%-/]+/'] = {
	-- 	handler = def,
	-- }
}

