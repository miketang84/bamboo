# Session&User&Registration
## Session
To use session, firstly you should require the module `local Session = require 'bamboo.session'`.  
To store the data, use `Session:setKey(key, value)`.  
To get the data, use `value = Session:getKey(key)`.  
Each session has a expiration time, you can add `expiration = 1800` in `settings.lua` to set the expiration time to 30 minutes.
## User & Registration
User is a special model, bamboo provides a User model, and you can use it by `local User = require 'bamboo.models.user'`. Also, you can define your own model by extending User model.  
To register the User model, you'd better user `bamboo.registerMainUser(User)` instead `bamboo.registerModel(User)`. Only in this way can you use the [bamboo admin interface][admin].  
`User.encrypt` is a function to describe how the password is encrypted, by default md5. This function is used when generating the user instance and authenticating.  
### Login & Logout
To login, use `User:login{username='username', password='password'}`. Always, `username` and `password` will be submitted, so we can use `User:login(Form:parse(req))` to handle this.  
To logout, just use `User:logout()`.  
Note: In fact, the information of logined or not is stored to session.
### Registration
To register, use `User:register{username='username', password='password'}`. Always, `username` and `password` will be submitted, so we can use `User:register(Form:parse(req))` to handle this.  

[admin]:https://github.com/littlehaker/bamboo_admin
