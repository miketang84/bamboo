#!/usr/bin/env luajit
-- this is a tool for rebuilding hash index for all the objects of the
--    specify Model. First , it delete all the data of the hash index of 
--    the Model, and second, it build the new hash index of the objects 
--    one by one. 
-- you must specify the db and model name 


redis = require 'redis'
require 'lglib'

if arg[1] == nil or arg[2] == nil then 
    print("HAS no DB args  or the Models args "); 
    return; 
end

if not tonumber(arg[1]) then 
    print("First argment [WHICH DB] must be number "); 
    return; 
end



local DB_HOST = '127.0.0.1'
local DB_PORT =  6379
local WHICH_DB = tonumber(arg[1])
local AUTH = nil
-- create a redis connection in this process
-- we will create one redis connection for every process
local db = redis.connect(DB_HOST, DB_PORT)
assert(db, '[Error] Database connection is failed.')
if AUTH then assert(db:command("auth",AUTH)); end
assert(db:select(WHICH_DB));


BAMBOO_DB = db
require 'bamboo'
local Model = require 'bamboo.model'
local mih = require 'bamboo.model-indexhash'


local modelName = "models." .. string.lower(arg[2]);

local TagModel = require(modelName)
if TagModel == nil then 
    print("HAS no the Models: " .. arg[2]); 
    return; 
end

--del all hash index 
local fields = TagModel.__fields;
for k,v in pairs(fields) do
    if v.indexType == "string" then 
        local setKeys = db:keys(arg[2] .. ":" .. k .. ":*__set");
        for _,setKey in pairs(setKeys) do 
            db:del(setKey);
        end
        db:del(arg[2] .. ":" .. k .. ":__hash");
    elseif v.indexType == 'number' then 
        db:del(arg[2] .. ":" .. k .. ":__zset");
    else
    end
end

local all = TagModel:all();
local count = 0;
for i,obj in pairs(all) do 
--    print(obj.title, obj.id )
    mih.index(obj,true);
    count = count +1 ;
end


print("make hash index for all " .. count .. " objects of " .. modelName);


