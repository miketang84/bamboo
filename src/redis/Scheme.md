In bamboo's backend redis, there may be the following key pattern:

Normal model record
--------------------
Model_name:[0-9]*		   :	redis hash
Model_name:__counter	   :	redis string, number
Model_name:__index		   :	redis zset, score is xxx, member is xxxx

Foreign field record
--------------------
Model_name:[0-9]*:field		   :	zset (MANY), list (LIST, FIFO), zset (ZFIFO)

Custom record
--------------------
Model_name:custom:custom_string			:	model custom key. type can be string, list, set, zset, hash
Model_name:[0-9]*:custom:custom_string	:	instance custom key. type can be string, list, set, zset, hash

Cache type
--------------------
Model_name:cache:cache_string			:	  string, zset
CACHETYPE:Model_name:cache:cache_string       string

Deleted Data
--------------------
DELETED:Model_name:[0-9]*  					: redis hash
DELETED:Model_name:[0-9]*:field   			: foreign zset, list

Session Data
-------------------
Session:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx	: hash
Session:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx:field_name:[string|list|set|zset]	: list, set, zset

Dynamic fields
-------------------
Model_name:dynamic_field:field_string		: hash
Model_name:dynamic_field:__index			: list

Rule Index
-------------------
_index_manager:Model_name					: zset, value is query_args_str, score is the counter number
_RULE:Model_name:score_num					: list, value is instance ids

Fulltext Index
-------------------
_fulltext_words:Model_name					: set, value is word
_FT:Model_name:word							: set, value is instance id
_RFT:Model_name:[0-9]*						: set, value is word





In every redis wapper module, there must be a standard API:

save	 	   : create, batch import
update		   : update batch import
retrieve	   : get all data once
del			   : del the whole
add (append)   : add one element to object set
remove (pop)   : remove one element from object set
num	(len)	   : measure the number of length of object set
has			   : check if it is in object set


