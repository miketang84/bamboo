
local tinsert = table.insert
local tremove = table.remove
local tupdate = table.update
local ObjectId = require('mongol.object_id').ObjectId

--local db = BAMBOO_MDB
--assert(db, '[ERROR] no mongodb connection!')

-------------------------------------------------------
-- helpers
-------------------------------------------------------
local function checkObjectId (id)
  return #tostring(id) == 24
end

local function attachId(obj)
  if obj and obj._id then
    obj.id = tostring(obj._id)
  end
end

local function attachIds(objs)
  for i, obj in ipairs(objs) do
    attachId(obj)
  end
  
  return objs
end


local function transId(id)
  if checkObjectId(id) then
    return ObjectId(id)
  else
    return id
  end
end

local function transIds(ids)
  local nids = {}
  for i, id in ipairs(ids) do
    nids[i] = transId(id)
  end
  
  return nids
end


local function normalizeEdge (start, stop, total)
  if not start then start = 1 end
  if not stop then stop = total end
  if start < 0 then start = total + start + 1 end
  if stop < 0 then stop = total + stop + 1 end
  
  return start, stop, total
end


-- fields form:  {
--   field_a = true,
--   field_b = true
-- }
local getById = function (self, id, fields)
  id = transId(id)
  local obj = self.__db:findOne(self.__collection, {_id = id}, fields)
  
  attachId(obj)

  return obj
end

local getByIds = function (self, ids, fields)
  ids = transIds(ids)
  
  local objs = self.__db:find(self.__collection, {_id = {
    ['$in'] = ids
  }}, fields):all()
  
  -- rearrange objs by ids' element order
  local robjs = {}
  for i, obj in ipairs(objs) do
    robjs[tostring(obj._id)] = obj
  end
  
  local orderedObjs = List()
  for i, id in ipairs(ids) do
    tinsert(orderedObjs, robjs[tostring(id)])
  end
  
  attachIds(orderedObjs)
  return orderedObjs
end

local allIds = function (self, is_rev)
  local idobjs = self.__db:find(self.__collection, {}, {_id=true}):all()
  
  local ids = List()
  if is_rev == 'rev' then
    local idobj
    for i=#idobjs, 1, -1 do
      idobj = idobjs[i]
      tinsert(ids, tostring(idobj._id))
    end
  else
    for i, idobj in ipairs(idobjs) do
      tinsert(ids, tostring(idobj._id))
    end
  end
  return ids
end

local sliceIds = function (self, start, stop, is_rev)
  local total = self.__db:count(self.__collection)
  start, stop = normalizeEdge(start, stop, total)
  
  local idobjs = self.__db:find(self.__collection, {
    ['$query'] = {},
    --['$maxScan'] = stop -- stop - start + 1 + start-1,
    
  }, {_id=true}, start-1, stop - start + 1):all()
  
  local ids = List()
  if is_rev == 'rev' then
    local idobj
    for i=#idobjs, 1, -1 do
      idobj = idobjs[i]
      tinsert(ids, tostring(idobj._id))
    end
  else
    for i, idobj in ipairs(idobjs) do
      tinsert(ids, tostring(idobj._id))
    end
  end

  return ids
end

local all = function (self, fields, is_rev)
  local objs = self.__db:find(self.__collection, {}, fields):all()
 
  attachIds(objs)
  if is_rev == 'rev' then
    return List(objs):reverse()
  else
    return List(objs)
  end
end

local slice = function (self, start, stop, is_rev, fields)
  local total = self.__db:count(self.__collection)
  start, stop = normalizeEdge(start, stop, total)

  local objs = self.__db:find(self.__collection, {
    ['$query'] = {},
    --['$maxScan'] = stop, -- stop - start + 1 + start - 1,
  }, fields, start-1, stop-start+1):all()
  
  attachIds(objs)
  if is_rev == 'rev' then
    return List(objs):reverse()
  else
    return List(objs)
  end

end

local numbers = function (self)
  return self.__db:count(self.__collection)

end

local get = function (self, query_args, fields, skip)
  local obj = self.__db:findOne(self.__collection, query_args, fields, skip)
  
  attachId(obj)
  return obj
end

local filter = function (self, query_args, fields, skip, ntr)
  --local objs = self.__db:findMany(self.__collection, query_args, fields, skip)
  local objs = self.__db:find(self.__collection, query_args, fields, skip, ntr):all()
  
  attachIds(objs)
  return objs
end

local count = function (self, query_args)
  return self.__db:count(self.__collection, query_args)
end

local delById = function (self, id)
  id = transId(id)  
  
  if idtype == 'string' then
    self.__db:remove(self.__collection, {_id=id})
  end

  return self
end

-- local trueDelById = delById

-------------------------------------------------------
-- instance api
-------------------------------------------------------

local save = function (self)
  
  if self.id or self._id then
    local _id = self._id
    self._id = nil
    self.id = nil
    
    -- here, may save extra fields, because we don' check the validance of each field
    self.__db:update(self.__collection, {_id = _id}, {
      ['$set'] = self
    })
  else
    -- here, mongo will generate _id for us, but self will not contain _id now
    self.__db:insert(self.__collection, {self})
    -- retrieve _id from mongo.
    -- _id is already ordered, so this is very rapid
    local obj = self.__db:findOne(self.__collection, {
      ['$query'] = {},
      ['$orderby'] = {_id = -1},
      --['$maxScan'] = 1
    }, {_id=true})
    
    self._id = obj._id
  end
  
  attachId(self)
  return self
end

local update = function (self, field, value)
  if not value then
    self.__db:update(self.__collection, {_id = self._id}, {
      ['$unset'] = { [field] = ''}
    })
  else
    self.__db:update(self.__collection, {_id = self._id}, {
      ['$set'] = { [field] = value}
    })
  end
  -- update to memory
  self[field] = value
    
  return self
end

local del = function (self)
  self.__db:remove(self.__collection, {_id=self._id})

  return self
end

--local trueDel = del


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
    self.__db:update(self.__collection, {_id=self._id}, {
      ['$set'] = {
        [ffield] = foreignid
      }
    })
  elseif storetype == 'MANY' then
    self.__db:update(self.__collection, {_id=self._id}, {
      ['$addToSet'] = {
        [ffield] = foreignid
      }
    })
    
  elseif storetype == 'LIST' then
    self.__db:update(self.__collection, {_id=self._id}, {
      ['$push'] = {
        [ffield] = foreignid
      }
    })
    
  elseif storetype == 'FIFO' then
    local fifolen = fld.fifolen or 100
    -- add it
    self.__db:update(self.__collection, {_id=self._id}, {
      ['$push'] = {
        [ffield] = foreignid
      }
    })

    local fgobj = self.__db:findOne(self.__collection, {_id=self._id}, {[ffield]=true})[ffield]
    
    if type(fgobj) == 'table' and #fgobj > fifolen then
      -- remove one
      self.__db:update(self.__collection, {_id=self._id}, {
        ['$pop'] = {
          [ffield] = -1
        }
      })
      tremove(fgobj, 1)
    end
    
  elseif storetype == 'ZFIFO' then
    local fifolen = fld.fifolen or 100
    
    self.__db:update(self.__collection, {_id=self._id}, {
      ['$addToSet'] = {
        [ffield] = foreignid
      }
    })
    local fgobj = self.__db:findOne(self.__collection, {_id=self._id}, {
      [ffield] = true
    })[ffield]
    
    if type(fgobj) == 'table' and #fgobj > fifolen then
      -- remove one
      self.__db:update(self.__collection, {_id=self._id}, {
        ['$pop'] = {
          [ffield] = -1
        }
      })
      tremove(fgobj, 1)
    end
  
  end

  return self
end

local getForeignIds = function (self, ffield, start, stop, is_rev)
    local fdt = self.__fields[ffield]
    local st = fdt.st

    local obj
    if start then
      -- no 'ONE' mode
      obj = self.__db:findOne(self.__collection, {_id=self._id}, {[ffield] = {
      ['$slice'] = {start-1, stop-start+1}
      }})
    else
      -- retreive all (string, or array)
      obj = self.__db:findOne(self.__collection, {_id=self._id}, {[ffield] = true})
    end

    if st == 'ONE' then
      if not obj or not obj[ffield] then 
        return nil 
      else
        return obj[ffield]
      end
    else
      if not obj or not obj[ffield] then
        return List() 
      else
        if is_rev == 'rev' then
          return List(obj[ffield]):reverse()
        else
          return List(obj[ffield])
        end
      end
    end
  
end

local getForeign = function (self, ffield, start, stop, is_rev, fields)
  local fld = self.__fields[ffield]
  local storetype = fld.st
  local fname = fld.foreign
  if fname == 'ANYOBJ' or fname == 'ANYSTRING' then
    return getForeignIds(self, ffield)
  end
  
  local ids = getForeignIds(self, ffield, start, stop, is_rev)
  if not ids then return nil end
  
  local this = {__db=self.__db, __collection=fname}
  if storetype == 'ONE' then
    local id = ids
    local obj = getById(this, id, fields)
    
    return obj
  else
    -- for normal model cases, MANY|LIST|FIFO|ZFIFO
    --local ids = getForeignIds(self, ffield, start, stop, is_rev)
    --ids = ids:slice(start, stop, is_rev)
    
    local objs = getByIds(this, ids, fields)
    return objs
  end

end

-- carefull
local reorderForeignMembers = function (self, ffield, neworder_ids)
  -- check neworder_ids' length
  
  -- check each is matched
  
  -- replace
  self.__db:update(self.__collection, {_id=self._id}, {
    ['$set'] = {
      [ffield] = neworder_ids
    }
  })
  
  return self
end

local removeForeignMember = function (self, ffield, id)

  local fdt = self.__fields[ffield]
  local ftype = fdt.foreign
  local st = fdt.st
  if st == 'ONE' then
    local obj = self.__db:findOne(self.__collection, {_id=self._id},
    { [ffield] = true })
    local fobj = obj[ffield]
    if fobj then
      local fobjtype = type(fobj)
      if fobjtype == 'string' then
        if fobj == id then
          self.__db:update(self.__collection, {_id=self._id}, {
            ['$unset'] = {
              [ffield] = ''
            }
          })
        end
      elseif fobjtype == 'table' then
        local cid = fobj.id or tostring(fobj._id)
        if cid == id then
          self.__db:update(self.__collection, {_id=self._id}, {
            ['$unset'] = {
              [ffield] = ''
            }
          })
        end
      
      end
    end
  else
    if ftype == 'ANYOBJ' then
      self.__db:update(self.__collection, {_id=self._id}, {
        ['$pull'] = {
          [ffield] = {
            id = id
          }
        }
      })
    else
      self.__db:update(self.__collection, {_id=self._id}, {
        ['$pull'] = {
          [ffield] = id
        }
      })
    end
  end
  
  return self
end

local delForeign = function (self, ffield)
  self.__db:update(self.__collection, {_id=self._id}, {
    ['$unset'] = {
      [ffield] = "" -- this value doesn't matter
    }
  })
  
  return self
end

local deepDelForeign = function (self, ffield)
  -- ids is string, or array
  local ids = getForeignIds(self, ffield)
  -- foreign model's name
  local fname = self.__fields[ffield].foreign
  if fname == 'ANYOBJ' or fname == 'ANYSTRING' then
    -- nothing to do
  else
  
    fptable(ids)
  
    -- for none 'ONE' case
    if type(ids) == 'table' then
      ids = transIds(ids)
      self.__db:remove(fname, { _id = {
          ['$in'] = ids
        }
      })
    else 
      -- for 'ONE' case
      ids = transId(ids)
      self.__db:remove(fname, { _id = ids })
    end
  end
  
  -- remove this field
  self.__db:update(self.__collection, {_id=self._id}, {
    ['$unset'] = {
      [ffield] = ""
    }
  })
  
  return self
end

-- XXX: this algorithm need to be optimized
-- and for ANYOBJ, is inefficent
local hasForeignMember = function (self, ffield, id)
  local fdt = self.__fields[ffield]
  local foreign = fdt.foreign
  if foreign == 'ANYSTRING' then
    local ids = getForeignIds(self, ffield)
    for i, v in ipairs(ids) do
      if v == id then return true end
    end
    return false
  elseif foreign == 'ANYOBJ' then
    local ids = getForeignIds(self, ffield)
    if not ids then return false end
    if #ids == 0 then
      if ids.id or ids._id then
        local cid = ids.id or tostring(ids._id)
        return cid == id
      else
        return false
      end
    else
      for i, v in ipairs(ids) do
        if v.id == id or tostring(v._id) == id then return true end
      end
      return false
    end
  else
  
    local ids = getForeignIds(self, ffield)
    if type(ids) == 'table' then
      for i, v in ipairs(ids) do
        if id == v then return true end
      end
      return false
    else
      print(ids, id)
      return id == ids
    end  
  end
  
end

local numForeign = function (self, ffield)
  local fdt = self.__fields[ffield]
  local st = fdt.st
  local ids = getForeignIds(self, ffield)
  if not ids then
    return 0
  else
    if st == 'ONE' then
      return 1
    else
      return #ids
    end
  end
end

-- NOTE: here, we check instance's foreign key field, not the model's
-- model's filed check is in __fields[field]
local hasForeignKey = function (self, ffield)

  local fdt = self.__fields[ffield]
  if not fdt or not fdt.foreign then return false end

  local obj = self.__db:findOne(self.__collection, {_id = self._id, [ffield] = { ['$exists'] = true }})
  
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
--  trueDelById = trueDelById,

  save = save,
  update = update,
  del = del,
  trueDel = trueDel,

  addForeign = addForeign,
  getForeign = getForeign,
  getForeignIds = getForeignIds,
  reorderForeignMembers = reorderForeignMembers,

  removeForeignMember = removeForeignMember,
  delForeign = delForeign,
  deepDelForeign = deepDelForeign,

  hasForeignMember = hasForeignMember,
  numForeign = numForeign,
  hasForeignKey = hasForeignKey

}
