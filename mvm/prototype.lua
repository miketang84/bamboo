module(..., package.seeall)

Text = Object:extend {
	validate = function(self, val) 
				   print('text validate') 
			   end,
	toHtml = function(self, val) print('tohtml') end,
}

Email = Text:extend {
	validate = function(self, val)  
				   self._parent.validate(self)
				   print('email')
			   end,
}

fieldType = {
	['text'] = Text,
	['email'] = Email,
}

return fieldType;
