module(..., package.seeall)


function process( instance, restcode )
print(instance, restcode)
    assert(loadstring('_t = {' + restcode + ' }'), '[Error] wrong syntax in view tag {**}.')()
		assert(type(_t) == 'table')

		local filters = _t.filters
		assert(type(filters) == 'nil' or type(filters) == 'table')
		local attached = _t.attached
		assert(type(filters) == 'nil' or type(attached) == 'table')

    print(instance, restcode)

    return modelToViewMapping(instance, filters, attached)

end

function modelToViewMapping(instance, filters, attached)
  local output = ''
  
  local value_type = type(instance)
  if value_type == 'string' or value_type == 'number' then
    output = output + ('<span>%s</span>'):format(instance)

  elseif value_type == 'table' and isValidInstance(instance) then
    local field_desc = instance.__fields
    for k, v in pairs(instance) do
      if k ~= 'id' then
        local fdt = field_desc[k]
        if fdt.widget_type == 'text' then
          local str = [[<input type='text' value='%s'>]]
          output = output + str:format(v)
        elseif fdt.widget_type == 'textarea' then
        
        end
      end
      
    end
  else
    output = output + ''
  end

  return output
end
