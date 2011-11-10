# Bamboo Admin
Bamboo Admin is the admin interface of bamboo.  
## Installation
By default, use `bamboo createapp` will create the admin directories and files for you.  
Manually, you can use `git clone git@github.com:littlehaker/bamboo_admin.git` to get the recent release of bamboo admin.
The directory structure is like this:

	bamboo_admin
	├── admin.lua
	├── admin_unlogined.lua
	├── media
	└── view

Copy `bamboo_admin` to your project directory as `admin` and copy `media` to your project directory as `media/admin`.
## How to use
Add following codes to `handler_entry.lua`:

	local admin = require 'admin.admin'
	bamboo.registerModule(admin)

Then, start and visit `/admin` in the browser, you can see the login page.
To login, it's time to create a super user.  
Because different projects may use different user model, you should use `bamboo.registerMainUser(User)` to replace `bamboo.registerModel(User)`.  
Note: The `User` model must contain `username`, `password` and `perms` fields.  
Then, run `bamboo createsuperuser`, follow the instruction to create a super user.  
Type the username and password to login and enjoy Bamboo Admin.
## Feedback
If you have any suggestion or ideas, sending a mail to `littlehaker@gmail.com` or `bamboo@librelist.com` will be appreciated.
