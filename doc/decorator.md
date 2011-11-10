# Decorator
## What is a decorator?
In many cases, you may need callbacks when an instance is saved, updated or got from the database. To do this, you can add `__decorators` to model definition like this:

	local Mymodel = Model:extend {
		...
		__decorators = {
			update = function(update)
				return function(self, ...)
					--Your code here
					return update(self, ...)
				end
			end;		
		};
		...
	}

So, a decorator is a function which returns a function. Now calling `inst:update(...)` equals calling `Mymodel.__decorators.update(Mymodel.update)(inst, ...)`, and so your extra code will be executed.  
For now, decorator is available for `'update', 'save', 'del', 'addForeign', 'delForeign', 'getById'`.  
## When to use?
Decorator can be used widely, such as to update a very field when the instance is got from database; to let `father:addForeign('son', son)` when `son:addFroeign('father', father)` and so on. Brainstorm and you can make full use of it.
