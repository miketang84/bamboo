
local gd = require 'gd'

local	getFormat = function(path)
		local file = io.open(path,"r");
		if not file then return nil; end

		local fileType = file:read(1):byte(1,1);
		io.close(file);

		--根据图片类型和路径生成gd对象
		local ext = nil;
		if fileType == 137 then -- png
			ext = ".png"
		elseif fileType == 71 then -- gif
			ext = ".gif"
		elseif fileType == 255 then--jpg
			ext = ".jpg"
		else
		end

		return ext;
	end;

local	getGdObj = function(path)
		local fileType = getFormat(path);
		if not fileType  then 
			return nil;
		end

		local gdObj = nil;
		if fileType == ".png" then -- png
			gdObj = gd.createFromPng(path);
		elseif fileType == ".gif" then -- gif
			gdObj = gd.createFromGif(path);
		elseif fileType == ".jpg" then--jpg
			gdObj = gd.createFromJpeg(path);
		else

		end

		return  gdObj;
	end
  
return {
  getFormat = getFormat,
  getGdObj = getGdObj
}
