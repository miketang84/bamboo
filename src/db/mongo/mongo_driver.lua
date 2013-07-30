
local tinsert = table.insert
local tremove = table.remove
local tupdate = table.update

--local db = BAMBOO_MDB
--assert(db, '[ERROR] no mongodb connection!')

-------------------------------------------------------
-- helpers
-------------------------------------------------------
local function attachId(obj)
  if obj then
    obj.id = obj._id
    return obj
  else
    return obj
  end
end

local function attachIds(objs)
  for i, obj in ipairs(objs) do
    obj.id = obj._id
  end
  
  return objs
end


-- fields form:  {
--   field_a = true,
--   field_b = true
-- }
local getById = function (self, id, fields)
  local obj = self.__mdb:findOne(self.__collection, {_id = id}, fields)
  
  if obj then
    -- keep compitable
    obj.id = obj._id
  end

  return obj
end

local getByIds = function (self, ids, fields)
  local objs = self.__mdb:find(self.__collection, {_id = {
    ['$in'] = ids
  }}, fields)
  
  -- rearrange objs by ids' element order
  local robjs = {}
  for i, obj in ipairs(objs) do
    robjs[tostring(obj._id)] = obj
  end
  
  local orderedObjs = List()
  for i, id in ipairs(ids) do
    tinsert(orderedObjs, robjs[tostring(id)])
  end
  
  return orderedObjs
end

local allIds = function (self, is_rev)
  local idobjs = self.__mdb:find(self.__collection, {}, {_id=true})
  
  local ids = List()
  if is_rev == 'rev' then
    local idobj
    for i=#idobjs, 1, -1 do
      idobj = idobjs[i]
      tinsert(ids, idobj._id)
    end
  else
    for i, idobj in ipairs(idobjs) do
      tinsert(ids, idobj._id)
    end
  end
  return ids
end

local sliceIds = function (self, start, stop, is_rev)
  if start < 0 and stop < 0 then
    local total = self.__mdb:count(self.__collection)
    start = total + start + 1
    stop = total + stop + 1
  end
  
  local idobjs = self.__mdb:find(self.__collection, {
    ['$query'] = {},
    ['$maxScan'] = stop - start + 1,
    
  }, {_id=true}, start-1)
  
  local ids = List()
  if is_rev == 'rev' then
    local idobj
    for i=#idobjs, 1, -1 do
      idobj = idobjs[i]
      tinsert(ids, idobj._id)
    end
  else
    for i, idobj in ipairs(idobjs) do
      tinsert(ids, idobj._id)
    end
  end

  return ids
end

local all = function (self, fields, is_rev)
  local objs = self.__mdb:find(self.__collection, {}, fields)
 
  if is_rev == 'rev' then
    return List(objs):reverse()
  else
    return List(objs)
  end
end

local slice = function (self, fields, start, stop, is_rev)
  if start < 0 and stop < 0 then
    local total = self.__mdb:count(self.__collection)
    start = total + start + 1
    stop = total + stop + 1
  end

  local objs = self.__mdb:find(self.__collection, {
    ['$query'] = {},
    ['$maxScan'] = stop - start + 1,
  }, fields, start-1)
  
  if is_rev == 'rev' then
    return List(objs):reverse()
  else
    return List(objs)
  end

end

local numbers = function (self)
  return self.__mdb:count(self.__collection)

end

local get = function (self, query_args, fields, skip)
  local obj = self.__mdb:findOne(self.__collection, query_args, fields, skip)
  
  return obj
end

local filter = function (self, query_args, fields, skip)
  --local objs = self.__mdb:findMany(self.__collection, query_args, fields, skip)
  local objs = self.__mdb:find(self.__collection, query_args, fields, skip):all()
  
  return objs
end

local count = function (self, query_args)
  return self.__mdb:count(self.__collection, query_args)
end

local delById = function (self, id)
  local idtype = type(id)
  
  if idtype == 'string' then
    self.__mdb:remove(self.__collection, {_id=id})
  elseif idtype == 'table' then
    self.__mdb:remove(self.__collection, {
      _id = {
        ['$in'] = id
      }
    })
  end

  return self
end

local trueDelById = delById

-------------------------------------------------------
-- instance api
-------------------------------------------------------

local save = function (self, params)
  if self.id and self._id then
  
    -- here, may save extra fields, because we don' check the validance of each field
    self.__mdb:update(self.__collection, {_id = self._id}, {
      ['$set'] = params
    })
  else
    tupdate(self, params)
    -- here, mongo will generate _id for us, but self will not contain _id now
    self.__mdb:insert(self.__collection, {self})
  end
  
  return self
end

local update = function (self, field, value)
  self.__mdb:update(self.__collection, {_id = self._id}, {
      ['$set'] = { field = value}
    })
    
  return self
end

local del = function (self)
  self.__mdb:remove(self.__collection, {_id=self._id})

  return self
end

local trueDel = del


-------------------------------------------------------
-- foreign api
-------------------------------------------------------

-- addForeign, we didn't care which Model the id belongs to, 
-- we must check this before call this function
-- foreign ids should belong the same Model, but next case, 
-- it will contains another Model type ids
local addForeign = function (self, ffield, foreignid)
  local fld = self.__fields[ffield]
  local storetype = fld.st
  if storetype == 'ONE' then
    self.__mdb:update(self.__collection, {_id=self._id}, {
      ['$set'] = {
        ffield = foreignid
      }
    })
  elseif storetype == 'MANY' then
    self.__mdb:update(self.__collection, {_id=self._id}, {
      ['$addToSet'] = {
        ffield = foreignid
      }
    })
    
  elseif storetype == 'LIST' then
    self.__mdb:update(self.__collection, {_id=self._id}, {
      ['$push'] = {
        ffield = foreignid
      }
    })
    
  elseif storetype == 'FIFO' then
    local fifolen = fld.fifolen or 100
    local fgobj = self[ffield]
    self.__mdb:update(self.__collection, {_id=self._id}, {
      ['$push'] = {
        ffield = foreignid
      }
    })
    tinsert(fgobj, foreignid)
    
    if type(fgobj) == 'table' and #fgobj > fifolen then
      -- remove one
      self.__mdb:update(self.__collection, {_id=self._id}, {
        ['$pop'] = {
          ffield = -1
        }
      })
      tremove(fgobj, 1)
    end
  elseif storetype == 'ZFIFO' then
    local fifolen = fld.fifolen or 100
    local fgobj = self[ffield]
    
    self.__mdb:update(self.__collection, {_id=self._id}, {
      ['$addToSet'] = {
        ffield = foreignid
      }
    })
    local newObj = self.__mdb:findOne(self.__collection, {_id=self._id}, {
      [ffield] = true
    })
    fgobj = newObj[ffield]
    
    if type(fgobj) == 'table' and #fgobj > fifolen then
      -- remove one
      self.__mdb:update(self.__collection, {_id=self._id}, {
        ['$pop'] = {
          ffield = -1
        }
      })
      tremove(fgobj, 1)
    end
    self[ffield] = fgobj
  end

  return self
end

local getForeignIds = function (self, ffield, start, stop, is_rev)
  local obj = self
  if obj[ffield] then
    if start then
      return List(obj[ffield]):slice(start, stop, is_rev)
    else
      return List(obj[ffield])
    end
  else
    if start then
      obj = self.__mdb:findOne(self.__collection, {_id=self._id}, {[ffield] = {
      ['$slice'] = {start-1, stop-start+1}
      }})
    else
      obj = self.__mdb:findOne(self.__collection, {_id=self._id}, {[ffield] = true})
    end
    
    if is_rev == 'rev' then
      return List(obj[ffield]):reverse()
    else
      return List(obj[ffield])
    end
    
  end
  
end

local getForeign = function (self, ffield, fields, start, stop, is_rev)
  local fld = self.__fields[ffield]
  local storetype = fld.st
  local fname = fld.foreign
  if fname == 'ANYOBJ' or fname == 'ANYSTRING' then
    return getForeignIds(self, ffield)
  end
  
  local ids = getForeignIds(self, ffield, start, stop, is_rev)
  if not ids then return nil end
  
  local this = {__mdb=self.__mdb, __collection=self.__collection}
  if storetype == 'ONE' then
    local id = ids
    local obj = getById(this, id, fields)
    
    return obj
  else
    -- for normal model cases, MANY|LIST|FIFO|ZFIFO
    local ids = getForeignIds(self, ffield)
    ids = ids:slice(start, stop, is_rev)
    
    local objs = getByIds(this, ids, fields)
    return objs
  end

end

-- carefull
local reorderForeignMembers = function (self, ffield, neworder_ids)
  -- check neworder_ids' length
  
  -- check each is matched
  
  -- replace
  self.__mdb:update(self.__collection, {_id=self._id}, {
    ['$set'] = {
      [ffield] = neworder_ids
    }
  })
  
  return self
end

local removeForeignMember = function (self, ffield, id)
  self.__mdb:update(self.__collection, {_id=self._id}, {
    ['$pull'] = {
      [ffield] = id
    }
  })
  
  return self
end

local delForeign = function (self, ffield)
  self.__mdb:update(self.__collection, {_id=self._id}, {
    ['$unset'] = {
      [ffield] = "" -- this value doesn't matter
    }
  })
  
  return self
end

local deepDelForeign = function (self, ffield)
  local ids = getForeignIds(self, ffield)
  local fname = self.__fields[ffield].foreign
  if fname == 'ANYOBJ' or fname == 'ANYSTRING' then
    -- nothing to do
  else
    if type(ids) == 'table' then
      self.__mdb:remove(fname, { _id = {
          ['$in'] = ids
        }
      })
    else 
      self.__mdb:remove(fname, { _id = ids })
    end
  end
  
  self.__mdb:update(self.__collection, {_id=self._id}, {
    ['$unset'] = {
      [ffield] = ""
    }
  })
  
  return self
end


local hasForeignMember = function (self, ffield, id)
  local ids = getForeignIds(self, ffield)
  local rids = {}
  if type(ids) == 'table' then
    for i, id in ipairs(ids) do
      rids[id] = true
    end
    
    if rids[id] then
      return true
    else
      return false
    end
  else
    return id == ids
  end  
  
end

local numForeign = function (self, ffield)
  local ids = getForeignIds(self, ffield)
  if type(ids) == 'table' then
    return #ids
  else
    return 1
  end
end

-- NOTE: here, we check instance's foreign key field, not the model's
-- model's filed check is in __fields[field]
local hasForeignKey = function (self, ffield)
  local obj = self.__mdb:findOne(self.__collection, {_id = self._id, [ffield] = { ['$exists'] = true }})
  
  return obj and true or false
end


--[[
-------- CLASS
getById
getByIds
allIds
sliceIds
all
slice
numbers
get
filter
count
delById
trueDelById

已删除对象相关的操作，放一个mixin里面来做。

--------- INSTANCE

save
update
del (含真删，假删，但是是由一个mixin的嵌入来覆盖原有的行为)
trueDel

addForeign
getForeign
getForeignIds
rearrangeForeignMembers

removeForeignMember
delForeign
deepDelForeign

hasForeignMember
numForeign
hasForeignKey
--]]





return {

  getById = getById,
  getByIds = getByIds,
  allIds = allIds,
  sliceIds = sliceIds,
  all = all,
  slice = slice,
  numbers = numbers,
  get = get,
  filter = filter,
  count = count,
  delById = delById,
  trueDelById = trueDelById,

  save = trueDelById,
  update = update,
  del = del,
  trueDel = trueDel,

  addForeign = addForeign,
  getForeign = getForeign,
  getForeignIds = getForeignIds,
  rearrangeForeignMembers = rearrangeForeignMembers,

  removeForeignMember = removeForeignMember,
  delForeign = delForeign,
  deepDelForeign = deepDelForeign,

  hasForeignMember = hasForeignMember,
  numForeign = numForeign,
  hasForeignKey = hasForeignKey

}
