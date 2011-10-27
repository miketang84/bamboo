README
======

## Introduction

Bamboo is a powerful web framework, written in lua. It is designed to be the most popular web framework in lua community, like Django in python, ROR in ruby.

## Features

- Bamboo is a MVC framework;
- cooperates with mongrel2, zeromq and redis;
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
- builtin test framework (based on telescope);

## What does it look like?
### Project Directory Structure
	.
	├── app
	│   └── handler_entry.lua
	├── initial
	├── media
	│   ├── css
	│   ├── images
	│   ├── js
	│   ├── plugins
	│   └── uploads
	├── models
	├── plugins
	├── settings.lua
	└── views


### Entry file

### How to start it
- Start mongrel2;
- Start redis server;
- Start bamboo project;


	
	

## Installation
link to another installation document.

## Some Websites Using Bamboo

## Mailing List

bamboo@librest.com
