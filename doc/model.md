# 
In many cases, web applications need to interact with databases, traditionally, we use SQL sentences. But in bamboo, we use model to do the interaction, which increases the robustness.  
# Configuring the database
In settings.lua, WHICH_DB tells bamboo which database of redis you want to use. Defaultly, it is 0.  
If you want to use datebase 10, just write `WHICH_DB = 10`.  
# Your first model
Go to your project direction, then `cd models`, run `bamboo createmodel Mymodel`, you will find a file nemed `mymodel.lua` is generated like below.  
	
	module(..., package.seeall)

	local Model = require 'bamboo.model'

	local Mymodel = Model:extend {
    __tag = 'Bamboo.Model.Mymodel';
    __name = 'Mymodel';
    __desc = 'Generitic Mymodel definition';
    __indexfd = 'name',
    __fields = { 
		['name'] = {},  
    
    };  
    
    init = function (self, t)
		if not t then return self end 
    
		self.name = t.name
    
		return self
    end;

	}

	return Mymodel

`local Mymodel = Model:extend{...}` means Mymodel inherit from Model, the details of this oop feature is shown in Appendix A. `__tag` shows the inheriting order of Mymodel, `__name`, `__desc` shows the name and some description. `__indexfd` indicates the index field used by `getIdByIndex` and `getByIndex`(Pay attention, a field is set to `__indexfd` means the value of this field must be unique). `__fields` is a table cantains the field information of this model, `['name'] = {}` means field's name is 'name', `{}` is a table containing information about field `name` called FDT short for Field Describe Table. `init` function is like the a constructor.  
We want to add some fields, so we edit `__fields` like this:
	
	__fields = { 
		['name'] = {},  
		['age'] = {},
		['gender'] = {},
    };
	
Note: Each model has a primary key `id` auto-incremented.
# Use the model
To use this model, open `app/handler_entry.lua`, and add following sentences.  
	
	Mymodel = require 'models.mymodel'
	registerModel(Mymodel)

Note: In each module using Mymodel, `Mymodel = require 'models.mymodel'` is required.  
To use Mymodel to create an instance is like this: `inst = Mymodel{name='Young'}`. Then we can save it to the database by `inst:save()`, update it by `inst:update('gender', 'male')`. To delete the instance from database, use `inst:del()`.
To get this instance from database, just use `inst_got = Mymodel:getByIndex('Young')`, then we get this instance. 
More model and instance methods are shown at the end of this file.  
# Foreign field
In many cases, a model has a field linking to another instance. For example, a student model has a field `school` linking to a school model, on the other hand, the school model has a field `students` linking to the student model, they should be written in bamboo like this:  
	
	Student = Model:extend {
		...
		__fields = {
			...
			['school'] = {foreign='School', st='ONE'},
			...
		},
		...
	}
	
	School = Model:extend {
		...
		__fields = {
			...
			['students'] = {foreign='Student', st='MANY'},
			...
		},
		...
	}
	
As we see, the FDT of `Student`'s field `school` tells bamboo that this field is a foreign field linking to the `School` model, `st='ONE'` means a school instance is linked to a student instance. `st='MANY'` in the FDT of `School`'s field `students` means many student instances are linked to a school instance.  
Suppose that `stu_inst` is an instance of `Student`, `sch_inst` is an instance of `School`, you can add instance to a foreign field by `stu_inst:addForeign('school', sch_inst)` and `sch_inst:addForeign('students', stu_inst)`, delete by `stu_inst:delForeign('school', sch_inst)` and `sch_inst:delForeign('students', stu_inst)`.  
To get foreign instances, use `sch_inst_got = stu_inst:getForeign('school')`. Note that for `st='MANY'` condition, `sch_inst:getForeign('students')` returns a QuerySet(more information in Appendix A) of instances.
# Query
To get instances from database, you can use `model:getById(id)`, which is the basic function. Also, you can use `model:getByIndex(index)`, `model:all(is_rev)`, `model:filter(query, is_rev, starti, length, dir)`, those functions all call `model:getById(id)`.  
To query from database, you can use `model:get(query, is_rev, starti, length, dir)` or `model:filter(query, is_rev, starti, length, dir)`, where `query` is a table contains the query parameters. For example, to get the instances of `Mymodel` whose `gender` equals `male` and `age` is greater than 20, you can use `insts = Mymodel:filter({gender='male', age=gt(20)})`, `insts` is what you want.  
`gt(x)` stands for 'greater than x', like this, wo also offer `lt(x)` for 'less than x', `ge(x)` for 'greater than or equal to x', `le(x)` for 'less than or equal to x', `contains(x)` for 'contains substring x', `startsWith(x)` for 'starts with substring x', `endsWith(x)` for 'ends with substring x'.  
Note: `query` is not available for field `id`.
# API
Class methods can be used by classes inheriting from Model.
Instance methods can be used by the instances of classes inheriting from Model.

## Class methods

### `model_obj:getIdByIndex (index)`  
Return the id of instance whose index field equals `index`.  
Index field is declared by `model_obj.__indexfd`. If undeclared, it is the id field.  

### `model_obj:getIndexById (id)`  
Return the `index` of instance whose id equals `id`.  
Index field is declared by `model_obj.__indexfd`. If undeclared, it is the id field.  

### `model_obj:getById (id)`  
Return the instance whose id equals `id`.

### `model_obj:getByIndex (index)`  
Return the instance whose index field equals `index`.

### `model_obj:allIds (is_rev)`  
Return all instance ids. Reversed when `is_rev` equals 'rev'.  

### `model_obj:sliceIds (start, stop, is_rev)`  
Return a slice of instance ids from `start` to `stop`. Reversed when `is_rev` equals 'rev'.  
`start` is optional, can be positive bigger than 0 or negetive.  
`stop` is optional, can be positive bigger than 'start' or negetive.

### `model_obj:all (is_rev)`  
Return all instances. Reversed when `is_rev` equals 'rev'.

### `model_obj:slice (start, stop, is_rev)`  
Return a slice of instances from `start` to `stop`. Reversed when `is_rev` equals 'rev'.  
`start` is optional, can be positive bigger than 0 or negetive.  
`stop` is optional, can be positive bigger than `start` or negetive.

### `model_obj:numbers ()`  
Return the number of all instances of `model_obj`.

### `model_obj:get (query, is_rev)`  
Return the first(last when `is_rev` equals 'rev') instance which matches the condition _query_. 
  
### `model_obj:filter (query, is_rev, starti, length, dir)`  
Return instances which matches the condition `query`. Reversed when `is_rev` equals 'rev'.  
_starti_ is optional, means the beginning of query range.  
`length` is optional, means the range length of query range.  
`dir` is optional, 1 means query from `starti` to `starti`+`length`, -1 means query from `starti` to `starti`-`length`.

### `model_obj:setCustom (key, val, st)`  
Store a key-value pair to redis.    
`key`, `val` mean the key and value of the pair.
`st` means the storage type of value. If `st` equals 'LIST', `val` should be a LIST, else, `val` should be a string.

### `model_obj:getCustom (key, st)`  
Return the value of `key` set by `model_obj:setCustom (key, val, st)`.   
`st` means the storage type of value. If value is a LIST, `st` should equal 'LIST'.

### `model_obj:delCustom (key)`  
Delete the key-value pair set by `model_obj:setCustom (key, val, st)`.  

### `model_obj:updateCustom (key, val)`
Update the value of `key` to `val` set by `model_obj:setCustom (key, val, st)`.   

### `model_obj:validate (params)`  
Return true when `params` is valid, else, return false, err\_msg.  
`params` is a key-value table, usually generated by `Form:parse(req)`.  
`err\_msg` is a table contains the error messages.

====================================================================== 

## Instance methods
### `instance_obj:save ()`  
Save `instance_obj` to database.  
Return `instance_obj`.

### `instance_obj:update (field, new_value)`  
Update `field` of `instance_obj` to new\_value.  
Return `instance_obj`.  
Note： This function cannot be used to foreign fields.

### `instance_obj:del ()`  
Delete `instance_obj` from database.  
Note: To delete an instance from database, you should firstly get the instance from database.

### `instance_obj:addForeign(field, new_obj)`  
Add foreign instance `new_obj` to `field`. `instance_obj.__fields.field` must contains foreign attrs.  
Return `instance_obj`.  
Note: Foreign field only save the id of foreign instance, to input the instance increase the reliability.

### `instance_obj:getForeign (field, start, stop, is_rev)`  
Return instances in `field` of `instance_obj` from 'start' to `stop`. Reversed when `is_rev` equals 'rev'.

### `instance_obj:delForeign (field, fr_obj)`  
Delete `fr_obj` from `field` of `instance_obj`.
Return `instance_obj`.

### `instance_obj:numForeign (field)`  
Return the number of foreign instances in `field` of `instance_obj`.

### `instance_obj:toHtml(params)`  
Return the html output of `instance_obj`.  
`params` is a parameter table, available keys contain `field`, `filters`, `attached`, `format`.  
`field` means which field you want to generate html element, all fields when `nil`.  
`filters` means which fields you want to generate html elements, all fields when `nil`.  
`attached` means extra information adding to field describe table.  
`format` means how the html elements will be generated, such as `'$label: $widget$help'`
