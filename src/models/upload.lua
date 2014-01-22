--- A basic lower upload API
--
module(..., package.seeall)

require 'posix'
local http = require 'lglib.http'
local normalizePath = require('lglib.path').normalize

local Model = require 'bamboo.model'
local Form = require 'bamboo.form'

local function rename_func(oldname)
  return os.time() .. math.random(1000000, 9999999) .. oldname:match('^.+(%.%w+)$')
end


local function calcNewFilename(dir, oldname)
  -- separate the base name and extense name of a filename
  local main, ext = oldname:match('^(.+)(%.%w+)$')
  if not ext then 
    main = oldname
    ext = ''
  end
  -- check if exists the same name file
  local tstr = ''
  local i = 0
  while posix.stat( dir + main + tstr + ext ) do
    i = i + 1
    tstr = '_' + tostring(i)
  end
  -- concat to new filename
  local newbasename = main + tstr

  return newbasename, ext
end

--- here, we temprorily only consider the file data is passed wholly by zeromq
-- and save by bamboo
-- @field t.req 
-- @field t.file_obj
-- @field t.dest_dir
-- @field t.prefix
-- @field t.postfix
-- 
local function savefile(file_obj, ajax, dest_dir, prefix, postfix, rename_func)
  
  local export_dir = dest_dir and ('/uploads/' + dest_dir + '/') or '/uploads/'
  export_dir = normalizePath(export_dir)
  local dest_dir = 'media'.. export_dir

  local prefix = prefix or ''
  local postfix = postfix or ''
  local filename = ''
  
  -- if upload in html5 way
  if ajax then
    filename = file_obj.headers['x-file-name'] or file_obj.PARAMS.filename or ''
    body = file_obj.body or ''
  else
    -- Notice: the filename in the form string are quoted by ""
    -- this pattern rule can deal with the windows style directory delimiter
    -- file_obj['content-disposition'] contains many file associated info
    filename = file_obj['content-disposition'].filename:sub(2, -2):match('\\?([^\\]-%.%w+)$')
    body = file_obj.body or ''
  end
  --fptable(file_obj) 
  --print('filename body', filename, #body) 
  if isFalse(filename) or isFalse(body) then return nil, nil end
  if not ajax then
    filename = http.encodeURL(filename)
  end
  
  if not posix.stat(dest_dir) then
    -- XXX: why posix have no command like " mkdir -p "
    os.execute('mkdir -p ' + dest_dir)
  end

  local _name = filename
  -- if passed in a rename function, use it to replace the orignial filename
  if rename_func and type(rename_func) == 'function' then
    _name = rename_func(_name)
  end

  local newbasename, ext = calcNewFilename(dest_dir, _name)
  local newname = prefix .. newbasename .. postfix .. ext
  
  local export_path = export_dir .. newname
  local path = dest_dir .. newname

  -- write file to disk
  local fd = io.open(path, "wb")
  fd:write(body)
  fd:close()
  
  return newname, path, export_path, filename
end

local	batch = function (params, dest_dir, prefix, postfix, rename_func)
  local file_objs = List()
  -- file data are stored as arraies in params
  for i, v in ipairs(params) do
    local name, path, export_path, oldname = savefile (v, false, dest_dir, prefix, postfix, rename_func)
    if path then
      file_objs:append({
        name = name,
        path = path,
        export_path = export_path,
        oldname = oldname
      })
    end
  end
  
  return file_objs	
end;



local processFile = function (req, ajax, dest_dir, prefix, postfix, rename_func)

  -- if upload in html5 way
  if ajax then
    -- when use ajax upload file, params is req object
    -- stored to disk
    local name, path, export_path, oldname = savefile (req, true, dest_dir, prefix, postfix, rename_func )    
    --print('--->2', name, path, export_path, oldname)
    if not path then return nil end
    
    return {
      name = name,
      path = path,
      export_path = export_path,
      oldname = oldname
    }
    
  else
    -- for uploading in html4 way
    -- here, in formal html4 form, req.POST always has value in, 
    assert(#params > 0, '[Error] No valid file data contained.')
    local files = batch ( req.PARAMS, dest_dir, prefix, postfix, rename_func )
    if files:isEmpty() then return nil end
    
    if #files == 1 then
      -- even only one file upload, batch function will return this fileobj
      return files[1]
    else
      return files
    end
  end

end


local Upload = Model:extend {
  __name = 'Upload';
  __fields = {
    ['name'] = {},
    ['path'] = {unique=true},
    ['innerpath'] = {},
    ['size'] = {},
    ['title'] = {},
    ['desc'] = {},
    ['cate'] = {},
    ['oldname'] = {},
    
  };
  __decorators = {
    del = function (odel)
      return function (self, ...)
        I_AM_INSTANCE_OR_QUERY_SET(self)
        -- if self is query set
        if isQuerySet(self) then
          for _, v in ipairs(self) do
            -- remove file from disk
            os.execute('rm ' + v.path)
          end
        else
          -- remove file from disk
          os.execute('rm ' + self.path)
        end
        
        return odel(self, ...)
      end
    end
  
  };
  
  
  -- t 就是外面传进来的params，就是 req.GET or req.POST or req.PARAMS
  -- 对于ajax上传的情况，外部应该把文件名传进来，要么放在t.filename中，要么放在 options.filename中传进来
  -- body也要放在 t.body 中传入
  -- 对于html4传统表单上传的情况，文件名已经包含在在params参数中，所以不用担心
  init = function (self, t, options)
    if not t then return self end
    
    local dest_dir = options.dest_dir
    local prefix = options.prefix
    local postfix = options.postfix
    local rename_func = options.rename_func == 'default' and rename_func or options.rename_func
    local ajax = options.ajax
    
    -- save file to disk
    --print('-->', t, ajax, dest_dir, prefix, postfix, rename_func)
    local file = processFile(t, ajax, dest_dir, prefix, postfix, rename_func)
    --print('file', file)
    if not file then return self end
    
    if #file == 0 then
      self.name = file.name
      self.path = file.export_path
      self.innerpath = file.path
      self.size = posix.stat(file.path).size
      self.desc = t.desc or ''
      self.title = t.title or ''
      self.cate = t.cate or ''
      self.oldname = file.oldname
      
    else
      local files = List()
      for i, v in ipairs(file) do
        files:append({
          name = v.name,
          path = v.export_path,
          innerpath = v.path,
          size = posix.stat(v.path).size,
          desc = t.desc or '',
          title = t.title or '',
          cate = t.cate or '',
          oldname = v.oldname
        })
      end
      self.files = files
    end
    --fptable(self) 
    return self
  end;
  
  -- deprecated, compatible with old version.
  process = function (self, web, req, dest_dir, prefix, postfix, rename_func)
		I_AM_CLASS(self)
		assert(web, '[Error] Upload input parameter: "web" must be not nil.')
		assert(req, '[Error] Upload input parameter: "req" must be not nil.')

    return self(req, {
      ajax = req.ajax,
      dest_dir = dest_dir, 
      prefix = prefix, 
      postfix = postfix, 
      rename_func = rename_func
    });
	
	end;
  
  calcNewFilename = function (self, dest_dir, oldname)
    return calcNewFilename(dest_dir, oldname)
  end;
  
}

return Upload


