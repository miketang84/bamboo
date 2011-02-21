module(..., package.seeall)


require 'posix'
local Model = require 'bamboo.model'

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
local function savefile(file_obj, dest_dir, prefix, postfix)
	checkType(file_obj, 'table')
	local filename = file_obj['content-disposition'].filename
	local filebody = file_obj.body
	-- 分离文件的文件名和扩展名
	--print(filename)
	local main, ext = filename:match('^\"(.+)(%.%w+)\"$')
	--print (main,  ext)
	local dest_dir = dest_dir or 'media/uploads/'
	local prefix = prefix or ''
	local postfix = postfix or ''
	local newname = prefix + main + postfix + ext
	
	--print(dest_dir)
	local fullname = dest_dir + newname
	
	
	local fd = io.open(fullname, "wb")
	fd:write(filebody)
	fd:close()
	
	return fullname, newname
end


local Upload = Model:extend {
	__tag = 'Bamboo.Model.Upload';
	__name = 'Upload';
	
	init = function (self, file_obj, dest_dir, prefix, postfix)
		-- 存储文件到磁盘上
		local fullname, name = savefile(file_obj, dest_dir, prefix, postfix)
		-- 默认的几个文件属性
		self.name = name
		self.fullname = fullname
		self.size = posix.stat(fullname).size
		
		return self
	end;
	
	-- 类方法
	batch = function (self, params, dest_dir, prefix, postfix)
		local file_objs = {}
		--local files = savefiles(params, dest_dir, prefix, postfix)
		for i, v in ipairs(params) do
			-- 创建各个文件对象实例
			local file_instance = self(v, dest_dir, prefix, postfix)
			-- 保存到数据库
			file_instance:save()
			table.append(file_objs, file_instance)
		end
		
		-- 返回这一批文件对象
		return file_objs	
	end;
	

}

return Upload


