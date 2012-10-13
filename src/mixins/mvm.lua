


	toHtml = function (self, params)
		 I_AM_INSTANCE(self)
		 params = params or {}

		 if params.field and type(params.field) == 'string' then
			 for k, v in pairs(params.attached) do
				 if v == 'html_class' then
					 self.__fields[params.field][k] = self.__fields[params.field][k] .. ' ' .. v
				 else
					 self.__fields[params.field][k] = v
				 end
			 end

			 return (self.__fields[params.field]):toHtml(self, params.field, params.format)
		 end

		 params.attached = params.attached or {}

		 local output = ''
		 for field, fdt_old in pairs(self.__fields) do
			 local fdt = table.copy(fdt_old)
			 setmetatable(fdt, getmetatable(fdt_old))
			 for k, v in pairs(params.attached) do
				 if type(v) == 'table' then
					 for key, val in pairs(v) do
						 fdt[k] = fdt[k] or {}
						 fdt[k][key] = val
					 end
				 else
					 fdt[k] = v
				 end
			 end

			 local flag = true
			 params.filters = params.filters or {}
			 for k, v in pairs(params.filters) do
				 -- to redundant query condition, once meet, jump immediately
				 if not fdt[k] then
					 -- if k == 'vl' then self.__fields[field][k] = 0 end
					 if k == 'vl' then fdt[k] = 0 end
				 end

				 if type(v) == 'function' then
					 flag = v(fdt[k] or '')
					 if not flag then break end
				 else
					 if fdt[k] ~= v then flag=false; break end
				 end
			 end

			 if flag then
				 output = output .. fdt:toHtml(self, field, params.format or nil)
			 end

		 end

		 return output
	 end

