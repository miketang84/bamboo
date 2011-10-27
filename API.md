本文档中的所有类方法都可以供所有继承自Model的类使用，所有实例方法可供所有这些类以及类的实例使用。 
Class methods can be used by classes inheriting from Model.
Instance methods can be used by classes inheriting from Model and instances of those classes.

## Class methods

`model_obj:getIdByIndex (index)`  
Return the id of instance whose index field equals _index_.  
Index field is declared by model.__indexfd. If undeclared, it is the id field.  

`model_obj:getIndexById (id)`  
Return the _index_ of instance whose id equals _id_.
Index field is declared by model.__indexfd. If undeclared, it is the id field.  

`model_obj:getById (id)`  
Return the instance whose id equals _id_.

`model_obj:getByIndex (index)`  
Return the instance whose index field equals _index_.

`model_obj:allIds (is_rev)`  
Return all instance ids. Reversed when _is\_rev_ equals 'rev'.  


返回此模型的所有实例id组成的一个列表的一个切片 
Lua代码  
model_obj:sliceIds (start, stop, is_rev)        获取此model旗下的所有id的一个切片，并返回此id列表  
  
start:  可选，正数的话从1开始，可以为负的索引  
stop:   可选，不能小于start，可以为负的索引，最后一个为-1  
is_rev: 是否反向标志。此值只有当为字符串'rev'时，表示反向生成结果列表；反之省略此参数或者取其它任何值都表示正向生成结果列表  


取出此模型的所有实例对象 
Lua代码  
model_obj:all (is_rev)      获取此model旗下的所有实例对象，并返回此对象列表  
  
is_rev: 是否反向标志。此值只有当为字符串'rev'时，表示反向生成结果列表；反之，省略此参数或者取其它任何值都表示正向生成结果列表  


取出此模型的所有实例对象的一个切片 
Lua代码  
model_obj:slice (start, stop, is_rev)   获取此model旗下的所有实例对象的一个切片，并返回此对象列表  
  
start:  可选，正数的话从1开始，可以为负的索引  
stop:   可选，不能小于start，可以为负的索引，最后一个为-1  
is_rev: 是否反向标志。此值只有当为字符串'rev'时，表示反向生成结果列表；反之，省略此参数或者取其它任何值都表示正向生成结果列表  


取出此模型的所有有效keys 
Lua代码  
model_obj:allKeys ()        获取此model旗下的所有keys，并返回此key列表  


测量当前数据库中此类的真实实例个数 
Lua代码  
model_obj:numbers ()        获取此model旗下的实例的总数目，并返回此整数  


根据query参数取出此模型的一个实例。query的讲解参见专门的章节。 
Lua代码  
model_obj:get (query, is_rev)       返回此对象实例  
  
query:  query参数表  
is_rev: 是否反向查找  


根据query参数取出此模型的一批实例。query的讲解参见专门的章节。 
Lua代码  
model_obj:filter (query, is_rev, starti, length, dir)   并返回此对象实例  
  
query:  query参数表  
is_rev: 可选。是否反向生成中间id列表，会影响过滤结果方向  
starti: 可选。查找的范围中开始时的list索引  
length: 可选。需要查找的长度  
dir:    可选。取值为1（正向）或-1（反向）。在is_rev的基础上，指定基于开始点朝前或朝后一段距离的方向  


清除此模型的所有实例对象 
Lua代码  
model_obj:clearAll ()   无返回参数  
  
注意：此操作非常危险，除非你确实知道自己在干什么，否则请不要使用。  


向数据库中存入一些自定义的键值对 
Lua代码  
model_obj:setCustom (key, val, st)  向数据库中存入自定义键值对，目前已经支持字符串和list的存入。  
  
key:    自定义键  
val:    自定义值  
st:     存储形式。如果没有st或st不为 “LIST”，就表明存储string，（这时val必须为string）；  
        如果st为“LIST”，就表明存储list，这时，val必须为list。  


取出数据库中的自定义键值对 
Lua代码  
model_obj:getCustom (key, st)   目前来讲，返回的是字符串或list  
  
key:    自定义键  
st:     存储形式。st一般可以不写，只不过当存储的是一个list时，不写st会产生一个警告，不会报错。  


删除数据库中的自定义键值对 
Lua代码  
model_obj:delCustom (key)   删除成功，返回true；反之，返回false  
  
key:    自定义键  


基于数据库的定义对提交的数据进行验证 
Lua代码  
model_obj:validate (params) 传进来的参数一条一条验证后，完全符合要求的，返回true；只要有一条验证不满足，就返回false，以及一条错误信息  
  
params: 一个key-value的table，一般为从客户端传上来的参数解析（用Form:parse()等）后的结果；  


====================================================================== 

实例方法 

保存本实例对象（的非外键部分）到数据库 
Lua代码  
instance_obj:save ()    无返回值  
  
提示：这是将数据存入数据库中的最常用的方法  


更新本实例对象的某一个字段（非外键）到数据库（避免全部保存拖低效率） 
Lua代码  
instance_obj:update (field, new_value)  无返回值  
  
field:  要更新的域  
new_value:  此域的新值  
  
注意：此接口无法对外键域进行操作  


获取模型计数器的值 
Lua代码  
instance_obj:getCounter ()  返回当前模型计数器的值，整数  
  
注：此函数除了实例可以调用外，类对象也可以调用  


删除本实例对象或本实例对象列表 
Lua代码  
instance_obj:del ()     删除此对象  
  
提示：  
可以看到，我们要删除一个实例对象，必须先取出它来，再执行删除。这样设计的目的是更加保证安全性、有效性  


添加一个外链模型的实例new_obj的id到本对象的域field中来 
Lua代码  
instance_obj:addForeign(field, new_obj)     返回self  
  
field:  记录外键的域。要求此实例的此域必须要有外键属性（定时模型时必须指定）  
new_obj:    待添加的对象  
  
提示：  
在外键域中记录的是外键对象的id，但要求传入数据为一个对象，主要也是为了使操作更加安全。  


获取本对象的外键域的外键实例 
Lua代码  
instance_obj:getForeign (field, start, stop, is_rev)        返回外键对象或外键对象列表，没有就返回nil  
  
field:  外键域。要求，此域在定义的时候必须声明外键属性  
start:  可选。起始位置。用于限制返回结果的切片  
stop:   可选。结束位置。用于限制返回结果的切片  
is_rev: 可选。如果有的话，如果等于”rev”，就反向生成结果list；否则，正向生成  


释放本对象的一个域中所存储的外链模型的实例列表的一个片断 
Lua代码  
instance_obj:delForeign (field, fr_obj)     返回self  
  
field:  外键域  
fr_obj: 要被删除的外键对象  


得到本对象外键域当前外键的数目 
Lua代码  
instance_obj:numForeign (field)     返回当前外键域中的外链对象的数目，整数  
  
field:  外键域  


根据域名称获取相应的字段的信息 
Lua代码  
instance_obj:fieldInfo (field)      返回指定域在模型定义时的信息  
  
field:  域名称，字符串 
