url = 'http://localhost'
project_name = "lgcms"
host = "lgcms"
sender_id = 'c2405186-5c67-8b7e-e584-915901e5a02c'
io_threads = 1
views = "views/"
config_file = 'config.lua'
WHICH_DB = 27

rule_index_support = false

debug_level = 1
PRODUCTION =false 
prof =false 

index_hash = true
mmseg_dict_path = 'dict/mmseg'
sensitive_dict_path = 'dict/sensitive'

auto_reload_when_code_change = true


--全文搜索
fulltext_index_support = true
search_threshold = 20 --搜索门限值

--审核时间
verify_time_start = 24
verify_time_end = 24

--假删
use_fake_deletion = true

--每页显示数目
forum_npp = 10
article_npp = 10

--初始界面（0 = 正常， 1 = 只看帖， 2 = 只聊天)
oo_style_status = 2
