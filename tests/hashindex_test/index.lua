#!/usr/bin/env lua  
redis = require 'redis'
require 'lglib'


local DB_HOST = '127.0.0.1'
local DB_PORT =  6379
local WHICH_DB = 0
local AUTH = nil
-- create a redis connection in this process
-- we will create one redis connection for every process
local db = redis.connect(DB_HOST, DB_PORT)
assert(db, '[Error] Database connection is failed.')
if AUTH then assert(db:command("auth",AUTH)); end
assert(db:select(WHICH_DB));


BAMBOO_DB = db
require 'bamboo'

-- load file handler_xxx.lua, make its environment as childenv, extract global variables in handler_xxx.lua to childenv
setfenv(assert(loadfile("settings.lua")), setmetatable(bamboo.config, {__index=_G}))()


local Model = require 'bamboo.model'


local Test = Model:extend{
    __tag = 'Object.Model.Test';
	__name = 'Test';
	__desc = 'Basic user definition.';
--	__indexfd = {name = "string" , score = "number"};
	__fields = {
		['name'] = { indexType="string", required=true },
		['score'] = { indexType="number", required=true },
	};

    init = function (self,t)
        if not t then return self end;

        self.name = t.name;
        self.score = t.score;
        self.created_time = os.time();

        return self
    end

}

bamboo.registerModel(Test)

function test_string_field_hash(obj,field)
    local hash_value = db:hget("Test:"..field..":__hash",obj[field]);
    
    if tonumber(hash_value) then 
        if tonumber(hash_value) ~= tonumber(obj.id) then 
            assert(false, "the hash vaule must be the id");
        else
            return;
        end
    else
        assert(hash_value=="Test:"..field..":"..obj[field]..":__set","error field set key");
        local ids = Set(db:smembers(hash_value));
        assert(ids[obj.id] ,"the id must in the set");
        for k,v in pairs(ids) do
            assert(db:hget("Test:"..k,field) == obj[field],"the object field value must equal the key means");
        end
    end
end
function test_number_field_hash(obj,field)
    assert(tonumber(db:zscore("Test:"..field..":__zset",tostring(obj.id))) == tonumber(obj[field]), "the hash vaule must be the id"); 
end

function testMain()
    Test:all():del();
    db:del("Test:score:__zset");
    db:del("Test:name:__hash");
    db:del("Test:name:xxxx1:__set");
    db:del("Test:name:xxxx:__set");
    db:del("Test:name:xxxx2:__set");
    db:del("Test:__index");
    db:del("Test:__counter");

    local test1 = Test({name = "xxxx",score = 1.0})
    local test2 = Test({name = "xxxx",score = 1.1})
    local test3 = Test({name = "xxxx",score = 1.2})
    local test4 = Test({name = "xxxx1",score = 2.0})
    local test5 = Test({name = "xxxx1",score = 2.1})
    local test6 = Test({name = "xxxx2",score = 3.0})
    local test7 = Test({name = "xxxx3",score = 2.0})
    
    print("TEST INDEX");
    test1:save(); print("test1",test1.id,test1.name,test1.score);
    test_string_field_hash(test1,"name");
    test_number_field_hash(test1,"score");

    test2:save(); print("test2",test2.id,test2.name,test2.score);
    test_string_field_hash(test2,"name");
    test_number_field_hash(test2,"score");

    test3:save(); print("test3",test3.id,test3.name,test3.score);
    test_string_field_hash(test3,"name");
    test_number_field_hash(test3,"score");

    test4:save(); print("test4",test4.id,test4.name,test4.score);
    test_string_field_hash(test4,"name");
    test_number_field_hash(test4,"score");

    test5:save(); print("test5",test5.id,test5.name,test5.score);
    test_string_field_hash(test5,"name");
    test_number_field_hash(test5,"score");

    test6:save(); print("test6",test6.id,test6.name,test6.score);
    test_string_field_hash(test6,"name");
    test_number_field_hash(test6,"score");

    test7:save(); print("test7",test7.id,test7.name,test7.score);
    test_string_field_hash(test7,"name");
    test_number_field_hash(test7,"score");
   
    test_string_field_hash(test1,"name");
    test_number_field_hash(test1,"score");
    test_string_field_hash(test2,"name");
    test_number_field_hash(test2,"score");
    test_string_field_hash(test3,"name");
    test_number_field_hash(test3,"score");
    test_string_field_hash(test4,"name");
    test_number_field_hash(test4,"score");
    test_string_field_hash(test5,"name");
    test_number_field_hash(test5,"score");
    test_string_field_hash(test6,"name");
    test_number_field_hash(test6,"score");
    test_string_field_hash(test7,"name");
    test_number_field_hash(test7,"score");
    print("HASH INDEX CREATE PASSED");

  
    --test number eq
    local ids = Test:filter({score = eq(1.1)})
    for i=1,#ids do  ids[i] = ids[i].id end
    assert(#ids == 1, "test number eq failed");
    assert(tonumber(ids[1]) == 2, "test number eq failed");
    ids = Test:filter({score = eq(2.0)})
    for i=1,#ids do  ids[i] = ids[i].id end
    assert(#ids == 2, "test number eq failed");
    assert(tonumber(ids[1]) == 4 or tonumber(ids[1]) == 7, "test number eq failed");
    assert(tonumber(ids[2]) == 4 or tonumber(ids[2]) == 7, "test number eq failed");
    ids = Test:filter({score = eq(210.0)})
    for i=1,#ids do  ids[i] = ids[i].id end
    assert(#ids == 0, "test number eq failed");
    ids = Test:filter({score = 1.1})
    for i=1,#ids do  ids[i] = ids[i].id end
    assert(#ids == 1, "test number eq failed");
    assert(tonumber(ids[1]) == 2, "test number eq failed");
    ids = Test:filter({score = 2.0})
    for i=1,#ids do  ids[i] = ids[i].id end
    assert(#ids == 2, "test number eq failed");
    assert(tonumber(ids[1]) == 4 or tonumber(ids[1]) == 7, "test number eq failed");
    assert(tonumber(ids[2]) == 4 or tonumber(ids[2]) == 7, "test number eq failed");
    ids = Test:filter({score = 210.0})
    for i=1,#ids do  ids[i] = ids[i].id end
    assert(#ids == 0, "test number eq failed");
    print("number eq PASSED");


    --test number uneq
    ids = Test:filter({score = uneq(1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test number uneq failed");
    ids = Set(ids);
    assert(ids['2']==nil, "test number uneq failed");
    ids = Test:filter({score = uneq(2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test number uneq failed");
    ids = Set(ids);
    assert(ids['4'] ==nil, "test number uneq failed");
    assert(ids['7'] ==nil, "test number uneq failed");
    ids = Test:filter({score = uneq(210.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 7, "test number uneq failed");
    print("number uneq PASSED");

    --test number lt
    ids = Test:filter({score = lt(1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test number lt failed");
    ids = Set(ids);
    assert(ids['1'], "test number lt failed");
    ids = Test:filter({score = lt(2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test number lt failed");
    ids = Set(ids);
    assert(ids['1'], "test number lt failed");
    assert(ids['2'], "test number lt failed");
    assert(ids['3'], "test number lt failed");
    ids = Test:filter({score = lt(3)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test number lt failed");
    assert(ids['6']==nil, "test number lt failed");
    print("number lt PASSED");


    --test number gt
    ids = Test:filter({score = gt(1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test number gt failed");
    ids = Set(ids);
    assert(ids['1']==nil, "test number gt failed");
    assert(ids['2']==nil, "test number gt failed");
    ids = Test:filter({score = gt(2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number gt failed");
    ids = Set(ids);
    assert(ids['5'], "test number gt failed");
    assert(ids['6'], "test number gt failed");
    ids = Test:filter({score = gt(3)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test number gt failed");
    print("number gt PASSED");

    --test number le
    ids = Test:filter({score = le(1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number le failed");
    ids = Set(ids);
    assert(ids['1'], "test number le failed");
    assert(ids['2'], "test number le failed");
    ids = Test:filter({score = le(2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test number le failed");
    ids = Set(ids);
    assert(ids['1'], "test number le failed");
    assert(ids['2'], "test number le failed");
    assert(ids['3'], "test number le failed");
    assert(ids['4'], "test number le failed");
    assert(ids['7'], "test number le failed");
    ids = Test:filter({score = le(3)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 7, "test number le failed");
    print("number le PASSED");



    --test number ge
    ids = Test:filter({score = ge(1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test number ge failed");
    ids = Set(ids);
    assert(ids['1']==nil, "test number ge failed");
    ids = Test:filter({score = ge(2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test number ge failed");
    ids = Set(ids);
    assert(ids['5'], "test number ge failed");
    assert(ids['6'], "test number ge failed");
    assert(ids['4'], "test number ge failed");
    assert(ids['7'], "test number ge failed");
    ids = Test:filter({score = ge(3)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test number ge failed");
    ids = Set(ids);
    assert(ids['6'], "test number ge failed");
    print("number ge PASSED");


    --test number bt
    ids = Test:filter({score = bt(0,1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test number bt failed");
    ids = Set(ids);
    assert(ids['1'], "test number bt failed");
    ids = Test:filter({score = bt(1,2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number bt failed");
    ids = Set(ids);
    assert(ids['2'], "test number bt failed");
    assert(ids['3'], "test number bt failed");
    ids = Test:filter({score = bt(2,30)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number bt failed");
    ids = Set(ids);
    assert(ids['5'], "test number bt failed");
    assert(ids['6'], "test number bt failed");
    print("number bt PASSED");


    --test number be
    ids = Test:filter({score = be(0,1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number be failed");
    ids = Set(ids);
    assert(ids['1'], "test number be failed");
    assert(ids['2'], "test number be failed");
    ids = Test:filter({score = be(1,2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test number be failed");
    ids = Set(ids);
    assert(ids['1'], "test number be failed");
    assert(ids['2'], "test number be failed");
    assert(ids['3'], "test number be failed");
    assert(ids['4'], "test number be failed");
    assert(ids['7'], "test number be failed");
    ids = Test:filter({score = be(2,30)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test number be failed");
    ids = Set(ids);
    assert(ids['4'], "test number be failed");
    assert(ids['5'], "test number be failed");
    assert(ids['6'], "test number be failed");
    assert(ids['7'], "test number be failed");
    print("number be PASSED");


    --test number outside
    ids = Test:filter({score = outside(0,1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test number outside failed");
    ids = Set(ids);
    assert(ids['5'], "test number outside failed");
    assert(ids['6'], "test number outside failed");
    assert(ids['3'], "test number outside failed");
    assert(ids['4'], "test number outside failed");
    assert(ids['7'], "test number outside failed");
    ids = Test:filter({score = outside(1,2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number outside failed");
    ids = Set(ids);
    assert(ids['6'], "test number outside failed");
    assert(ids['5'], "test number outside failed");
    ids = Test:filter({score = outside(2,30)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test number outside failed");
    ids = Set(ids);
    assert(ids['1'], "test number outside failed");
    assert(ids['2'], "test number outside failed");
    assert(ids['3'], "test number outside failed");
    print("number outside PASSED");


    --test number inset
    ids = Test:filter({score = inset(0,1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test number inside failed");
    ids = Set(ids);
    assert(ids['2'], "test number inside failed");
    ids = Test:filter({score = inset(1,2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test number inside failed");
    ids = Set(ids);
    assert(ids['1'], "test number inside failed");
    assert(ids['4'], "test number inside failed");
    assert(ids['7'], "test number inside failed");
    ids = Test:filter({score = inset(2,30)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number inside failed");
    ids = Set(ids);
    assert(ids['4'], "test number inside failed");
    assert(ids['7'], "test number inside failed");
    print("number inset PASSED");



    --test number uninset
    ids = Test:filter({score = uninset(0,1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test number uninset failed");
    ids = Set(ids);
    assert(ids['1'], "test number uninset failed");
    assert(ids['3'], "test number uninset failed");
    assert(ids['4'], "test number uninset failed");
    assert(ids['5'], "test number uninset failed");
    assert(ids['6'], "test number uninset failed");
    assert(ids['7'], "test number uninset failed");
    ids = Test:filter({score = uninset(1,2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test number uninset failed");
    ids = Set(ids);
    assert(ids['2'], "test number uninset failed");
    assert(ids['3'], "test number uninset failed");
    assert(ids['5'], "test number uninset failed");
    assert(ids['6'], "test number uninset failed");
    ids = Test:filter({score = uninset(2,30)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test number uninset failed");
    ids = Set(ids);
    assert(ids['1'], "test number uninset failed");
    assert(ids['2'], "test number uninset failed");
    assert(ids['3'], "test number uninset failed");
    assert(ids['5'], "test number uninset failed");
    assert(ids['6'], "test number uninset failed");
    print("number uninset PASSED");

    --test string eq
    ids = Test:filter({name = eq("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string eq failed");
    ids = Set(ids);
    assert(ids['1'], "test string eq failed");
    assert(ids['2'], "test string eq failed");
    assert(ids['3'], "test string eq failed");
    ids = Test:filter({name = eq("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string eq failed");
    ids = Set(ids);
    assert(ids['4'], "test string eq failed");
    assert(ids['5'], "test string eq failed");
    ids = Test:filter({name = eq("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['7'], "test string eq failed");
    ids = Test:filter({name = "xxxx"})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string eq failed");
    ids = Set(ids);
    assert(ids['1'], "test string eq failed");
    assert(ids['2'], "test string eq failed");
    assert(ids['3'], "test string eq failed");
    ids = Test:filter({name = "xxxx1"})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string eq failed");
    ids = Set(ids);
    assert(ids['4'], "test string eq failed");
    assert(ids['5'], "test string eq failed");
    ids = Test:filter({name = "xxxx3"})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['7'], "test string eq failed");
    print("string eq PASSED");



    --test string uneq
    ids = Test:filter({name = uneq("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test string uneq failed");
    ids = Set(ids);
    assert(ids['4'], "test string uneq failed");
    assert(ids['5'], "test string uneq failed");
    assert(ids['6'], "test string uneq failed");
    assert(ids['7'], "test string uneq failed");
    ids = Test:filter({name = uneq("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test string uneq failed");
    ids = Set(ids);
    assert(ids['1'], "test string uneq failed");
    assert(ids['2'], "test string uneq failed");
    assert(ids['3'], "test string uneq failed");
    assert(ids['6'], "test string uneq failed");
    assert(ids['7'], "test string uneq failed");
    ids = Test:filter({name = uneq("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test string uneq failed");
    ids = Set(ids);
    assert(ids['1'], "test string uneq failed");
    assert(ids['2'], "test string uneq failed");
    assert(ids['3'], "test string uneq failed");
    assert(ids['6'], "test string uneq failed");
    assert(ids['4'], "test string uneq failed");
    assert(ids['5'], "test string uneq failed");
    print("string uneq PASSED");

    --test string lt
    ids = Test:filter({name = lt("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string lt failed");
    ids = Set(ids);
    ids = Test:filter({name = lt("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string lt failed");
    ids = Set(ids);
    assert(ids['1'], "test string lt failed");
    assert(ids['2'], "test string lt failed");
    assert(ids['3'], "test string lt failed");
    ids = Test:filter({name = lt("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test string lt failed");
    ids = Set(ids);
    assert(ids['1'], "test string lt failed");
    assert(ids['2'], "test string lt failed");
    assert(ids['3'], "test string lt failed");
    assert(ids['6'], "test string lt failed");
    assert(ids['4'], "test string lt failed");
    assert(ids['5'], "test string lt failed");
    print("string lt PASSED");

    --test string gt
    ids = Test:filter({name = gt("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test string gt failed");
    ids = Set(ids);
    assert(ids['4'], "test string gt failed");
    assert(ids['5'], "test string gt failed");
    assert(ids['6'], "test string gt failed");
    assert(ids['7'], "test string gt failed");
    ids = Test:filter({name = gt("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string gt failed");
    ids = Set(ids);
    assert(ids['6'], "test string gt failed");
    assert(ids['7'], "test string gt failed");
    ids = Test:filter({name = gt("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string gt failed");
    ids = Set(ids);
    print("string gt PASSED");

    --test string le
    ids = Test:filter({name = le("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string le failed");
    ids = Set(ids);
    assert(ids['1'], "test string le failed");
    assert(ids['2'], "test string le failed");
    assert(ids['3'], "test string le failed");
    ids = Test:filter({name = le("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test string le failed");
    ids = Set(ids);
    assert(ids['1'], "test string le failed");
    assert(ids['2'], "test string le failed");
    assert(ids['3'], "test string le failed");
    assert(ids['4'], "test string le failed");
    assert(ids['5'], "test string le failed");
    ids = Test:filter({name = le("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 7, "test string le failed");
    ids = Set(ids);
    assert(ids['1'], "test string le failed");
    assert(ids['2'], "test string le failed");
    assert(ids['3'], "test string le failed");
    assert(ids['6'], "test string le failed");
    assert(ids['4'], "test string le failed");
    assert(ids['5'], "test string le failed");
    assert(ids['7'], "test string le failed");
    print("string le PASSED");

    --test string ge
    ids = Test:filter({name = ge("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 7, "test string ge failed");
    ids = Set(ids);
    assert(ids['1'], "test string ge failed");
    assert(ids['2'], "test string ge failed");
    assert(ids['3'], "test string ge failed");
    assert(ids['4'], "test string ge failed");
    assert(ids['5'], "test string ge failed");
    assert(ids['6'], "test string ge failed");
    assert(ids['7'], "test string ge failed");
    ids = Test:filter({name = ge("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test string ge failed");
    ids = Set(ids);
    assert(ids['4'], "test string ge failed");
    assert(ids['5'], "test string ge failed");
    assert(ids['6'], "test string ge failed");
    assert(ids['7'], "test string ge failed");
    ids = Test:filter({name = ge("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string ge failed");
    ids = Set(ids);
    assert(ids['7'], "test string ge failed");
    print("string ge PASSED");

    --test string bt
    ids = Test:filter({name = bt("a","xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string bt failed");
    ids = Set(ids);
    ids = Test:filter({name = bt("aa","xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids ==3, "test string bt failed");
    ids = Set(ids);
    assert(ids['1'], "test string bt failed");
    assert(ids['2'], "test string bt failed");
    assert(ids['3'], "test string bt failed");
    ids = Test:filter({name = bt("xxxx","xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string bt failed");
    ids = Set(ids);
    assert(ids['6'], "test string bt failed");
    assert(ids['4'], "test string bt failed");
    assert(ids['5'], "test string bt failed");
    print("string bt PASSED");

    --test string be
    ids = Test:filter({name = be("a","xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string be failed");
    ids = Set(ids);
    assert(ids['1'], "test string be failed");
    assert(ids['2'], "test string be failed");
    assert(ids['3'], "test string be failed");
    ids = Test:filter({name = be("aa","xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids ==5, "test string be failed");
    ids = Set(ids);
    assert(ids['1'], "test string be failed");
    assert(ids['2'], "test string be failed");
    assert(ids['3'], "test string be failed");
    assert(ids['4'], "test string be failed");
    assert(ids['5'], "test string be failed");
    ids = Test:filter({name = be("xxxx","xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 7, "test string be failed");
    ids = Set(ids);
    assert(ids['6'], "test string be failed");
    assert(ids['1'], "test string be failed");
    assert(ids['2'], "test string be failed");
    assert(ids['7'], "test string be failed");
    assert(ids['3'], "test string be failed");
    assert(ids['4'], "test string be failed");
    assert(ids['5'], "test string be failed");
    print("string be PASSED");

    --test string outside
    ids = Test:filter({name = outside("a","xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test string outside failed");
    ids = Set(ids);
    assert(ids['4'], "test string outside failed");
    assert(ids['5'], "test string outside failed");
    assert(ids['6'], "test string outside failed");
    assert(ids['7'], "test string outside failed");
    ids = Test:filter({name = outside("aa","xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids ==2, "test string outside failed");
    ids = Set(ids);
    assert(ids['6'], "test string outside failed");
    assert(ids['7'], "test string outside failed");
    ids = Test:filter({name = outside("xxxx","xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string outside failed");
    ids = Set(ids);
    print("string outside PASSED");

    --test string contains
    ids = Test:filter({name = contains("xx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 7, "test string contains failed");
    ids = Set(ids);
    assert(ids['1'], "test string contains failed");
    assert(ids['2'], "test string contains failed");
    assert(ids['3'], "test string contains failed");
    assert(ids['4'], "test string contains failed");
    assert(ids['5'], "test string contains failed");
    assert(ids['6'], "test string contains failed");
    assert(ids['7'], "test string contains failed");
    ids = Test:filter({name = contains("x1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string contains failed");
    ids = Set(ids);
    assert(ids['4'], "test string contains failed");
    assert(ids['5'], "test string contains failed");
    ids = Test:filter({name = contains("3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string contains failed");
    ids = Set(ids);
    assert(ids['7'], "test string contains failed");
    print("string contains PASSED");

    --test string uncontains
    ids = Test:filter({name = uncontains("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string uncontains failed");
    ids = Set(ids);
    ids = Test:filter({name = uncontains("x1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test string uncontains failed");
    ids = Set(ids);
    assert(ids['1'], "test string uncontains failed");
    assert(ids['2'], "test string uncontains failed");
    assert(ids['3'], "test string uncontains failed");
    assert(ids['6'], "test string uncontains failed");
    assert(ids['7'], "test string uncontains failed");
    ids = Test:filter({name = uncontains("xxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test string uncontains failed");
    ids = Set(ids);
    assert(ids['1'], "test string uncontains failed");
    assert(ids['2'], "test string uncontains failed");
    assert(ids['3'], "test string uncontains failed");
    assert(ids['6'], "test string uncontains failed");
    assert(ids['4'], "test string uncontains failed");
    assert(ids['5'], "test string uncontains failed");
    print("string uncontains PASSED");

    --test string startsWith
    ids = Test:filter({name = startsWith("xxxx2")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string startsWith failed");
    ids = Set(ids);
    assert(ids['6'], "test string startsWith failed");
    ids = Test:filter({name = startsWith("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string startsWith failed");
    ids = Set(ids);
    assert(ids['4'], "test string startsWith failed");
    assert(ids['5'], "test string startsWith failed");
    ids = Test:filter({name = startsWith("a")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string startsWith failed");
    ids = Set(ids);
    print("string startsWith PASSED");

    --test string unstartsWith
    ids = Test:filter({name = unstartsWith("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string unstartsWith failed");
    ids = Set(ids);
    ids = Test:filter({name = unstartsWith("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test string unstartsWith failed");
    ids = Set(ids);
    assert(ids['1'], "test string unstartsWith failed");
    assert(ids['2'], "test string unstartsWith failed");
    assert(ids['3'], "test string unstartsWith failed");
    assert(ids['6'], "test string unstartsWith failed");
    assert(ids['7'], "test string unstartsWith failed");
    ids = Test:filter({name = unstartsWith("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test string unstartsWith failed");
    ids = Set(ids);
    assert(ids['1'], "test string unstartsWith failed");
    assert(ids['2'], "test string unstartsWith failed");
    assert(ids['3'], "test string unstartsWith failed");
    assert(ids['6'], "test string unstartsWith failed");
    assert(ids['4'], "test string unstartsWith failed");
    assert(ids['5'], "test string unstartsWith failed");
    print("string unstartsWith PASSED");

    --test string endsWith
    ids = Test:filter({name = endsWith("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string endsWith failed");
    ids = Set(ids);
    assert(ids['1'], "test string endsWith failed");
    assert(ids['2'], "test string endsWith failed");
    assert(ids['3'], "test string endsWith failed");
    ids = Test:filter({name = endsWith("xx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string endsWith failed");
    ids = Set(ids);
    assert(ids['4'], "test string endsWith failed");
    assert(ids['5'], "test string endsWith failed");
    ids = Test:filter({name = endsWith("xxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string endsWith failed");
    ids = Set(ids);
    assert(ids['7'], "test string endsWith failed");
    print("string endsWith PASSED");

    --test string unendsWith
    ids = Test:filter({name = unendsWith("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test string unendsWith failed");
    ids = Set(ids);
    assert(ids['4'], "test string unendsWith failed");
    assert(ids['5'], "test string unendsWith failed");
    assert(ids['6'], "test string unendsWith failed");
    assert(ids['7'], "test string unendsWith failed");
    ids = Test:filter({name = unendsWith("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 5, "test string unendsWith failed");
    ids = Set(ids);
    assert(ids['1'], "test string unendsWith failed");
    assert(ids['2'], "test string unendsWith failed");
    assert(ids['3'], "test string unendsWith failed");
    assert(ids['6'], "test string unendsWith failed");
    assert(ids['7'], "test string unendsWith failed");
    ids = Test:filter({name = unendsWith("xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 6, "test string unendsWith failed");
    ids = Set(ids);
    assert(ids['1'], "test string unendsWith failed");
    assert(ids['2'], "test string unendsWith failed");
    assert(ids['3'], "test string unendsWith failed");
    assert(ids['6'], "test string unendsWith failed");
    assert(ids['4'], "test string unendsWith failed");
    assert(ids['5'], "test string unendsWith failed");
    print("string unendsWith PASSED");

    --test string inset
    ids = Test:filter({name = inset("a","xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string inset failed");
    ids = Set(ids);
    assert(ids['1'], "test string inset failed");
    assert(ids['2'], "test string inset failed");
    assert(ids['3'], "test string inset failed");
    ids = Test:filter({name = inset("aa","xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids ==2, "test string inset failed");
    ids = Set(ids);
    assert(ids['4'], "test string inset failed");
    assert(ids['5'], "test string inset failed");
    ids = Test:filter({name = inset("xxxx","xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test string inset failed");
    ids = Set(ids);
    assert(ids['1'], "test string inset failed");
    assert(ids['2'], "test string inset failed");
    assert(ids['3'], "test string inset failed");
    assert(ids['7'], "test string inset failed");
    print("string inset PASSED");

    --test string uninset
    ids = Test:filter({name = uninset("a","xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 4, "test string uninset failed");
    ids = Set(ids);
    assert(ids['4'], "test string uninset failed");
    assert(ids['5'], "test string uninset failed");
    assert(ids['6'], "test string uninset failed");
    assert(ids['7'], "test string uninset failed");
    ids = Test:filter({name = uninset("aa","xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids ==5, "test string uninset failed");
    ids = Set(ids);
    assert(ids['1'], "test string uninset failed");
    assert(ids['2'], "test string uninset failed");
    assert(ids['3'], "test string uninset failed");
    assert(ids['6'], "test string uninset failed");
    assert(ids['7'], "test string uninset failed");
    ids = Test:filter({name = uninset("xxxx","xxxx3")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string uninset failed");
    ids = Set(ids);
    assert(ids['4'], "test string uninset failed");
    assert(ids['5'], "test string uninset failed");
    assert(ids['6'], "test string uninset failed");
    print("string uninset PASSED");

    --test logic "or"
    ids = Test:filter({"or", name = "xxxx", score=1.0})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string "or" failed");
    ids = Set(ids);
    assert(ids['1'], "test string "or" failed");
    assert(ids['2'], "test string "or" failed");
    assert(ids['3'], "test string "or" failed");
    ids = Test:filter({"or",name = "xxxx1",score=3})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids ==3, "test string "or" failed");
    ids = Set(ids);
    assert(ids['4'], "test string "or" failed");
    assert(ids['5'], "test string "or" failed");
    assert(ids['6'], "test string "or" failed");
    ids = Test:filter({"or",name = "xxxryx3", score=2})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string "or" failed");
    ids = Set(ids);
    assert(ids['4'], "test string "or" failed");
    assert(ids['7'], "test string "or" failed");
    ids = Test:filter({"or",name = "xxxryx3", score=2.15})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string "or" failed");
    ids = Set(ids);
    ids = Test:filter({"or",name = "xxxx3", score=2.20})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string "or" failed");
    ids = Set(ids);
    assert(ids['7'], "test string "or" failed");
    print("logic 'or' PASSED");

    --test logic "and"
    ids = Test:filter({"and", name = "xxxx", score=1.0})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string "and" failed");
    ids = Set(ids);
    assert(ids['1'], "test string "and" failed");
    ids = Test:filter({"and",name = "xxxx1",score=3})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids ==0, "test string "and" failed");
    ids = Set(ids);
    ids = Test:filter({"and",name = "xxxryx3", score=2})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string "and" failed");
    ids = Set(ids);
    ids = Test:filter({"and",name = "xxxryx3", score=2.15})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string "and" failed");
    ids = Set(ids);
    ids = Test:filter({"and",name = "xxxx3", score=2.0})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string "and" failed");
    ids = Set(ids);
    assert(ids['7'], "test string "and" failed");
    print("logic 'and' PASSED");
    

    --for update 
    --test number eq
    test1:update("score", 2.0);
    test3:update("score", 1.1);
    test5:update("score", 0.1);

    ids = Test:filter({score = eq(1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number eq failed");
    ids = Set(ids);
    assert(ids['2'], "test number eq failed");
    assert(ids['3'], "test number eq failed");
    ids = Test:filter({score = eq(2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test number eq failed");
    ids = Set(ids);
    assert(ids['1'], "test number eq failed");
    assert(ids['4'], "test number eq failed");
    assert(ids['7'], "test number eq failed");
    ids = Test:filter({score = eq(1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test number eq failed");
    ids = Set(ids);
    ids = Test:filter({score = eq(1.2)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test number eq failed");
    ids = Set(ids);
    ids = Test:filter({score = eq(0.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test number eq failed");
    ids = Set(ids);
    assert(ids['5'], "test number eq failed");
    test1:update("score", 1.0);
    test3:update("score", 1.2);
    test5:update("score", 2.1);


    --test string uneq
    test1:update("name", "yyy");
    test3:update("name", "xxxx1");
    ids = Test:filter({name = eq("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['2'], "test string eq failed");
    ids = Test:filter({name = eq("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string eq failed");
    ids = Set(ids);
    assert(ids['3'], "test string eq failed");
    assert(ids['4'], "test string eq failed");
    assert(ids['5'], "test string eq failed");
    ids = Test:filter({name = eq("yyy")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['1'], "test string eq failed");
    test1:update("name", "xxxx");
    test3:update("name", "xxxx");
    print("HASH INDEX for Model:update() PASSED");

   
    --for save() 
    --test number eq
    test1["score"] = 2.0; test1:save()
    test3["score"] = 1.1;test3:save()
    test5["score"] = 0.1;test5:save()

    ids = Test:filter({score = eq(1.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test number eq failed");
    ids = Set(ids);
    assert(ids['2'], "test number eq failed");
    assert(ids['3'], "test number eq failed");
    ids = Test:filter({score = eq(2.0)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test number eq failed");
    ids = Set(ids);
    assert(ids['1'], "test number eq failed");
    assert(ids['4'], "test number eq failed");
    assert(ids['7'], "test number eq failed");
    ids = Test:filter({score = eq(1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test number eq failed");
    ids = Set(ids);
    ids = Test:filter({score = eq(1.2)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test number eq failed");
    ids = Set(ids);
    ids = Test:filter({score = eq(0.1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test number eq failed");
    ids = Set(ids);
    assert(ids['5'], "test number eq failed");
    test1:update("score", 1.0);
    test3:update("score", 1.2);
    test5:update("score", 2.1);


    --test string uneq
    test1.name= "yyy"; test1:save()
    test3.name= "xxxx1"; test3:save()
    ids = Test:filter({name = eq("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['2'], "test string eq failed");
    ids = Test:filter({name = eq("xxxx1")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string eq failed");
    ids = Set(ids);
    assert(ids['3'], "test string eq failed");
    assert(ids['4'], "test string eq failed");
    assert(ids['5'], "test string eq failed");
    ids = Test:filter({name = eq("yyy")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['1'], "test string eq failed");
    test1:update("name", "xxxx");
    test3:update("name", "xxxx");
    print("HASH INDEX for Model:save() PASSED");


    test1:fakeDel();
    test6:fakeDel();
    ids = Test:filter({name = eq("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 2, "test string eq failed");
    ids = Set(ids);
    assert(ids['2'], "test string eq failed");
    assert(ids['3'], "test string eq failed");
    ids = Test:filter({name = eq("xxxx2")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string eq failed");
    ids = Set(ids);
    
    ids = Test:filter({score = eq(1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string eq failed");
    ids = Set(ids);
    ids = Test:filter({score = eq(3)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string eq failed");
    ids = Set(ids);

    Test:restoreDeleted(1);
    Test:restoreDeleted(6);
    ids = Test:filter({name = eq("xxxx")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 3, "test string eq failed");
    ids = Set(ids);
    assert(ids['1'], "test string eq failed");
    assert(ids['2'], "test string eq failed");
    assert(ids['3'], "test string eq failed");
    ids = Test:filter({name = eq("xxxx2")})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['6'], "test string eq failed");

    ids = Test:filter({score = eq(1)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['1'], "test string eq failed");
    ids = Test:filter({score = eq(3)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['6'], "test string eq failed");
    print("HASH INDEX for Model:fakeDelFromRedis() and Model:restoreDeleted() PASSED");



    test7:del();
    ids = Test:filter({score = eq(2)})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 1, "test string eq failed");
    ids = Set(ids);
    assert(ids['4'], "test string eq failed");
    ids = Test:filter({name = "xxxx3"})
    for i=1,#ids do  ids[i] = tostring(ids[i].id) end
    assert(#ids == 0, "test string eq failed");
    ids = Set(ids);
    print("HASH INDEX for Model:delFromRedis() PASSED");


    print("HASH INDEX FILTER PASSED");
    print("!!!!!!!!!!!!! congaratulations !!!!!!!!!!!!!");
end



testMain()













