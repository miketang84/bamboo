module(..., package.seeall)

local Upload = require 'bamboo.models.upload'
local gdutil = require 'bamboo.lib.gdutil'

local Image = Upload:extend {
  __name = 'Image';
  __fields = {
    ['width'] = {},
    ['height'] = {},
    
  };
  
  init = function (self, t)
    if not t then return self end
    local imgobj = gdutil.getGdObj(self.innerpath)
    if imgobj then
      local width, height = imgobj:sizeXY()
      self.width = width
      self.height = height
    end		
    return self
  end;

}

return Image
