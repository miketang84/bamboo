-- 假删
-- 目前只提供删除功能，后面找个时间把删除的恢复功能加上
-- 现在相当于是放到垃圾箱里面

local driver = require 'bamboo.db.driver'

return function (...)
    
    
    return {
      -- delete self instance object
      trueDelById = function (self, id)
        I_AM_CLASS(self)
        return driver.delById(self, id)
      end,
      
      fakeDelById = function (self, id)
        I_AM_CLASS(self)
        return driver.fakeDelById(self, id)
      end,
      
      delById = function (self, id)
        I_AM_CLASS(self)
        return driver.fakeDelById(self)
      end,
    
      -- delete self instance object
      trueDel = function (self)
        I_AM_INSTANCE(self)
        return driver.del(self)
      end,
      
      fakedel = function (self)
        I_AM_INSTANCE(self)
        return driver.fakedel(self)
      end,
      
      del = function (self)
        I_AM_INSTANCE(self)
        return driver.fakedel(self)
      end,
      
      
    }

end
