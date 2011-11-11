README
======

## Introduction

Bamboo is a powerful web framework, written in lua. It is designed to be the most popular web framework in lua community, like Django in python, ROR in ruby.

## Features

- Bamboo is a MVC framework;
- cooperates with mongrel2, zeromq and redis;
- stateless handler;
- powerful views rendering engine;
- a strict single inheritance OOP model style;
- use a lua table as the main URL router;
- in each module, there can be another URL router related to this module (URL moduled);
- project init(), finish(); module init(), finish();  
- a whole set of filter system for handler function;
- flexible ORM wrapper, specific to redis;
- powerful MVM (model-to-view mapping) function;
- decorators on database related actions, to reduce manual code;
- builtin User, Group and Permission models and a set of permission checking procedure;
- builtin test framework (based on telescope).

## What does it look like?
### Project Directory Structure
	One project										# This project's directory
	├── app											# control code directory
	│   └── handler_entry.lua						# entry file
	├── initial										# place where put db's initial data
	├── media										# static files directory
	│   ├── css
	│   ├── images
	│   ├── js
	│   ├── plugins
	│   └── uploads
	├── models										# place where put model defined files
	├── plugins										# plugins directory
	├── settings.lua								# project setting file
	└── views										# place where put views (html) files
		└── index.html


### Entry file 
In Bamboo's project, file `app/handler_entry.lua` is the entry of this project. This file can contain the following parts:

1. require 'bamboo' (MUST)
2. require other classes and modules (MUST)
3. register permissions (Optional)
4. register filters (Optional)
5. register models used by this project (Optional)
6. register modules related by this project (Optional)
7. handlers of this project (Optional)
8. main URL router (MUST)

This file looks usually like follows:

	------------------------------------------------------------------------
	-- bamboo import
	require 'bamboo'
	
	-- Other Class and module required
	local Form = require 'bamboo.form'
	local View = require 'bamboo.view'
	local Session = require 'bamboo.session'
	local registerModel = bamboo.registerModel
	local registerModule = bamboo.registerModule

	------------------------------------------------------------------------
	-- Model Registrations
	local User = require 'bamboo.models.user'
	registerModel(User)
	local IPUser = require 'models.ipuser'
	registerModel(IPUser)
	local Upload = require 'bamboo.models.upload'
	registerModel(Upload)
	local Image = require 'bamboo.models.image'
	registerModel(Image)
	local Permission = require 'bamboo.models.permission'
	registerModel(Permission)
	
	------------------------------------------------------------------------
	-- Module Registrations
	local module1 = require 'app.module1'
	registerModule(module1)
	local module2 = require 'app.module2'
	registerModule(module2)
	local upload = require 'app.upload'
	registerModule(upload)
	
	------------------------------------------------------------------------
	-- Some handlers
	local function index(web, req)
	   web:page(View("index.html"){})
	end
	
	local function get(web, req)
	   ...
	end
	
	local function put(web, req)
	   ...
	end
	
	------------------------------------------------------------------------
	-- URL router
	URLS = { '/',
		['/'] = index,
		['/index/'] = index,
		['/get/'] = get,
		['/put/'] = put,
	}

### How to start it
- Start mongrel2;

	`cd ~/workspace/monserver`  
	`bamboo loadconfig`  
	`bamboo startserver main`  
If mongrel2 server occupy this terminal, open a new terminal before next step;  

- Start redis server;

	`cd ~`  
	`redis-server /etc/redis.conf`  

- Start bamboo project;

	`cd ~/workspace/your_project`  
	`bamboo start`  
If this step goes smoothly, you will see what like follows:  
CONNECTING / 45564ef2-ca84-a0b5-9a60-0592c290ebd0 tcp://127.0.0.1:9999 tcp://127.0.0.1:9998  

- Open the web browser and input `http://localhost:6767` and enter, you will see your project page, if everything is OK;
- END.

## Installation
Please see doc/0.INSTALL.md in this source package.

## Some Websites Using Bamboo Now

- http://www.top-edu.cn
- http://www.51jianzhiwang.cn
- http://www.onewin.cn
- http://www.artjia.cn



## Mailing List
Bamboo use the following mailing list:
  
bamboo@librest.com

You can send mail with anything to it, when you receive an reply mail, you reply this mail again, then you will join into this mailing list automatically.

