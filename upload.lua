module(..., package.seeall)

require 'posix'
local http = require 'lglib.http'

local Model = require 'bamboo.model'
local Form = require 'bamboo.form'

------------------------------------------------------------------------
-- 作为上传机制，我们只提供这样一个比较底层的接口
-- 是因为，可能不同的应用，需要有不同的文件管理模型（上传文件模型）
-- 如果是内部定义了一套Upload模型的话，后面就需要从这个Upload模型中继承
-- 同样，在后面的扩展模型中，数据库的名字都还是用Upload
------------------------------------------------------------------------

------------------------------------------------------------------------
-- 暂只考虑上传文件全部小于4M（在monglre2.conf中设定）的情况
-- 这种情况下，全部文件数据会通过0mq传输到handler中来，并经过form的解析
-- 生成直接可用的lua对象。这种情况下的文件的数据是整个加载到内存中的。
-- 另外一种临时文件的形式，会另外作处理。
------------------------------------------------------------------------
local function savefile(t)
	local req, file_obj = t.req, t.file_obj
	local dest_dir = t.dest_dir or 'media/uploads/'
	local prefix = t.prefix or ''
	local postfix = t.postfix or ''
	local filename = ''
	local body = ''
	
	-- 如果是xhr上传
	if req.headers['x-requested-with'] then
		filename = req.headers['x-file-name']
		body = req.body
	else
		checkType(file_obj, 'table')
		-- 注，从这里取出的文件名，两边是由""括起来的
		-- 这种情况，一般就是处理Windows下IE的情况了，为什么传上来的文件名是：
		-- filename="C:\Documents and Settings\Administrator\桌面\little_bg.gif" 这种形式
		filename = file_obj['content-disposition'].filename:sub(2, -2):match('\\?([^\\]-%.%w+)$')
		--print(filename)
		body = file_obj.body
	end
	
	-- 检查系统中是否有指定目录，如果没有，就创建它
	if not posix.stat(dest_dir) then
		-- 由于posix库中找不到一次性递归创建目录的函数，所以暂时用这个系统调用了
		os.execute('mkdir -p ' + dest_dir)
	end
	
	-- 分离文件的文件名和扩展名
	local main, ext = filename:match('^(.+)(%.%w+)$')
	-- 计算是否存在同名文件
	local tstr = ''
	local i = 0
	while posix.stat( dest_dir + main + tstr + ext ) do
		i = i + 1
		tstr = '_' + tostring(i)
	end
	-- 得出新的文件名
	local newname = prefix + main + tstr + postfix + ext
	local fullname = dest_dir + newname
	-- 写文件到磁盘上
	local fd = io.open(fullname, "wb")
	fd:write(body)
	fd:close()
	
	return fullname, newname
end


local Upload = Model:extend {
	__tag = 'Bamboo.Model.Upload';
	__name = 'Upload';
	__desc = 'User\'s upload files.';
	__fields = {
		{ 'name', 'text', false },				-- 此文件的名字
		{ 'fullname', 'text', false },			-- 此文件的可访问URI
		{ 'size', 'text', false },				-- 此文件大小，以字节计算
		{ 'timestamp', 'date', false }, 			-- 上传成功的时间戳
		{ 'desc', 'textarea', true },			-- 此文件的描述
		
		{ 'page', 'text', true },				-- 此文件依附于哪一个页面，可省略
		{ 'user', 'text', false },				-- 此文件由哪个用户上传
	};
	
	init = function (self, t)
		if not t then return self end
		-- if isFalse(t) then error('Upload input parameters must be not blank.'); return false end
		if not t.web then error('Upload input parameter: "web" must be not nil.'); return false end
		if not t.req then error('Upload input parameter: "req" must be not nil.'); return false end
		
		local req = t.req
		-- 目前的方案，对大于预定义值的文件上传，立即给予中止
		if req.headers['x-mongrel2-upload-start'] then
			print('return blank to abort upload.')
			-- 发送中止信息，这里web如何引入？
			t.web.conn:reply(req, '')
			-- 返回错误信息
			return nil, 'Uploading file is too large.'
		end
		
		-- 存储文件到磁盘上
		local fullname, name = savefile(t)
		
		-- 默认的几个文件属性，其它属性也可以在这里添加
		self.name = name
		self.fullname = fullname
		self.size = posix.stat(fullname).size
		self.timestamp = os.time()
		-- 按照目前的做法，上传的时候，是没有备注信息的，这里写这一句只是为了表示可能会扩展
		self.desc = t.desc or ''
		
		
		return self
	end;
	
	-- 类方法，params中为文件数据，由Form.parse解析后的内容
	-- batch只适合存储传统表单文件数据，使用xhr时不能用这个函数处理
	-- 因为xhr上传总是一个一个上传，不会出现多个合在一起的情况
	batch = function (self, t)
		local params = t.params
		local file_objs = {}
		--local files = savefiles(params, dest_dir, prefix, postfix)
		for i, v in ipairs(params) do
			-- 创建各个文件对象实例
			local file_instance = self {
				web = t.web,
				req = t.req,
				file_obj = v,
				dest_dir = t.dest_dir,
				prefix = t.prefix,
				postfix = t.postfix,
			}
			if file_instance then
				-- 保存到数据库
				file_instance:save()
				table.append(file_objs, file_instance)
			else
				-- 一旦发现file_instance为nil，则说明没有上传成功（可能被中断了），直接返回nil
				return nil
			end
		end
		
		-- 返回这一批文件对象
		return file_objs	
	end;
	
	process = function (self, web, req, dest_dir, prefix, postfix)
	    if req.headers['x-requested-with'] then
			local file_instance = self { web = web, req = req, dest_dir = dest_dir, prefix = prefix, postfix = postfix}
			if file_instance then
				file_instance:save()
				return file_instance, 'single'
			else
				-- 发现file_instance为nil，则说明没有上传成功（可能被中断了），直接返回nil
				return nil
			end
		else
			-- ptable(req)
			-- ptable(req.headers)
			local params = Form:parse(req)
			local files = self:batch { web = web, req = req, params = params,  dest_dir = dest_dir, prefix = prefix, postfix = postfix }
			-- 或只保存一个文件
			-- local file_obj = Form.parse(req)[1]
			-- local file_instance = Upload { req = req, file_obj = file_obj }
			-- file_instance:save()
			return files, 'list'
		end
	
	end;
	

}

return Upload


