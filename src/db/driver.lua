

local mongo_driver = require 'bamboo.db.mongo.mongo_driver'

local default_driver = 'mongo'
local driver_selected = bamboo.config.dbdriver or default_driver



if driver_selected == 'mongo' then
  return mongo_driver
else
  error('No db driver selected!')
end

