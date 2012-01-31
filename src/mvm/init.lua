module(..., package.seeall)



local function constructHtmlTable(instance, field, value, fdt)
	local h = {
		template =[[<label>$caption:</label><input type="text" class="$class" name="$field" $attr value="$value" >]],
		class={},
	}

	for desc, val in pairs(fdt) do

		if desc == 'required' then
			if val == true then
				table.insert(h.class, 'required')
			end
		elseif desc == 'editable' then
			if val == false then
				local wtype = fdt.widget_type
				if wtype == 'url' then
					h.template = [[<label>$caption:</label><a href="http://$value" target='blank'>$value</a>]]
				else
					h.template = [[<label>$caption:</label><span>$value</span>]]
				end
			else
				local wtype = fdt.widget_type
				if wtype == 'text' then
					-- h.template = [[<label>$field:</label><input type="text" class="$class" $attr value="$value" >]]
					table.insert(h.class, 'textInput')
				elseif wtype == 'textarea' then
					h.template = [[<label>$caption:</label><textarea class="$class" name="$field" $attr>$value</textarea>]]
				elseif wtype == 'enum' then
					h.template = [[<label>$caption:</label><select name="$field" class="$class">$enum</select>]]
					local str_enum = ''
					for _, v in ipairs(fdt.enum) do
						if v == value then
							str_enum = str_enum .. '<option selected>' .. v .. '</option>'
						else
							str_enum = str_enum .. '<option>' .. v .. '</option>'
						end
					end
					h.template = h.template:gsub('$enum', str_enum)
				elseif wtype == 'date' then
					table.insert(h.class, 'date')
					h.yearstart = '-100'
					h.yearend = '0'
				elseif wtype == 'email' then
					table.insert(h.class, 'email')
				elseif wtype == 'mobilephone' then
					table.insert(h.class, 'digits')
					h.minlength = 11
					h.maxlength = 11
				elseif wtype == 'image' then
					h.template = [==[
							<label>$caption:</label>
								<img src="/$value" /><br/><label></label>
								<input type="text" value="$value" name="$field" />
								<div id="__upload"></div>

								<script type="text/javascript" src="/media/js/fileuploader.js"></script>
								<script type="text/javascript">
								$(function(){
										  var uploader = new qq.FileUploader({
									 element: $('#__upload')[0],
									 action: '/admin/upload',
									 debug: false,
									 sizeLimit: 500000,
									 maxConnections: 1,
									 //listElement: page_upload_list_table[0],
									 fileTemplate: '<div class="qq-uploading hide">' +
										 '<span class="qq-upload-file"></span>' +
										 '<span class="qq-upload-spinner"></span>' +
										 '<span class="qq-upload-size"></span>' +
										 '<a class="qq-upload-cancel" href="#">Cancel</a>' +
										 '<span class="qq-upload-failed-text">Failed</span>' +
										 '</div>',
									 template: '<div class="qq-uploader">' +
										 '<div class="qq-upload-drop-area"><span>Drop files here to upload</span></div>' +
										 '<div class="qq-upload-button"><a>上传</a></div>' +
										 '<ul class="qq-upload-list"></ul>' +
										 '</div>',
									 messages: {
										 typeError: "{file} 扩展名不合要求。只有扩展名为 {extensions} 的文件被允许上传。",
										 sizeError: "{file} 文件太大，最大限制为 {sizeLimit}。",
										 minSizeError: "{file} 文件太小，最小限制为 {minSizeLimit}。",
										 emptyError: "{file} 文件是空的，请重新选择文件。",
										 onLeave: "文件正在上传，如果此时离开，将会停止上传。"            
									 },
									 onComplete: function(){navTab.reload('')}		
												 });
								 });        
							 </script>

						]==]
				else
					h.template =[[<label>$caption:</label><input type="text" class="$class" $attr value="$value" name="$field"/>]]
				end
			end
		elseif desc == 'foreign' then
			if fdt.st == 'ONE' then

			end
		elseif desc == 'st' then
			if val == 'ONE' then
				local foreign_instance = instance:getForeign(field)

				local model = bamboo.getModelByName(fdt.foreign)
				local instances = model:all()

				local str_opt = ''
				local indexfd = 'id'
				if model.__indexfd and model.__indexfd ~= '' then indexfd = model.__indexfd end

				for _, v in ipairs(instances) do
					if foreign_instance and foreign_instance.id == v.id then
						str_opt = str_opt .. '<option selected value="' .. v.id .. '">' .. tostring(v[indexfd]) .. '</option>'
					else
						str_opt = str_opt .. '<option value="' .. v.id .. '">' .. tostring(v[indexfd]) .. '</option>'
					end
				end
				
				h.template = '<label>$caption:</label><select name="$field"><option value="0"></option>' .. str_opt .. '</select>'
			elseif val == 'MANY' then
				local foreign_instances = instance:getForeign(field)

				local model = bamboo.getModelByName(fdt.foreign)
				local instances = model:all()

				local str_opt = ''
				local indexfd = 'id'
				if model.__indexfd and model.__indexfd ~= '' then indexfd = model.__indexfd end
				
				for _, v in ipairs(instances) do
					local eq = false
					for _, foreign_instance in ipairs(foreign_instances) do
						if foreign_instance.id == v.id then
							eq = true
						end
					end
					if eq then 
						str_opt = str_opt .. '<label><input type="checkbox" checked name="' .. field .. '[]" value="'.. v.id .. '"/>' ..tostring(v[indexfd]) .. '</label>'
					else
						str_opt = str_opt .. '<label><input type="checkbox" name="' .. field  .. '[]" value="'.. v.id .. '"/>' ..tostring(v[indexfd]) .. '</label>'
					end
				end

				h.template = '<label>$field:</label><div style="overflow:auto; width:200px; max-height:200px; border:1px solid black"><input type="hidden" name="' .. field ..'[]" value="0" />' .. str_opt .. '</div>'
			end
		elseif desc == 'wrap' then
		elseif desc == 'enum' then
		elseif desc == 'caption' then
		elseif desc == 'widget_type' then
		elseif desc == 'vl' then
		elseif desc == 'class' then
		elseif desc == 'new_field' then
		elseif desc == 'template' then
		elseif desc == 'max_length' then
			h['maxlength'] = val
		elseif desc == 'min_length' then
			h['minlength'] = val
		else
			h[desc] = val			
		end
	end

	return h
end




function switch(case1, case2)
	return 
	function(codetable)
		local f = codetable.default
		-- f = codetable[case1][case2] or codetable.default
		if codetable[case1] then
			-- f = codetable[case1]
			if codetable[case1][case2] then
				f = codetable[case1][case2]
			end
			if codetable[case1].default then
				f = codetable[case1].default
			end
		end
		if f then
			if type(f)=="function" then
				return f
			else
				error("case "..tostring(case1).." not a function")
			end
		end
	end
end

function fieldToViewMapping(instance, field, value, fdt, filters, attached)
	local output = ''
	if field ~= 'id' then

		local html_table = {
			template =[[<label>$field:</label><input type="text" class="$class" $attr value="$value" >]],
			class={},
		}
		
		local f = fdt

		for k, v in pairs(attached) do
			if v == 'class' then
				f[k] = f[k] .. ' ' .. v
			else
				f[k] = v
			end
		end

		local html_table = constructHtmlTable(instance, field, value, f)

		-- fptable(html_table)

		local str_class, str_attr = f.class or '', ''
		for k, v in pairs(html_table) do
			if k ~= 'template' then
				if k == 'class' then
					for _, c in ipairs(v) do
						str_class = str_class .. ' ' .. c
					end
				else
					str_attr = str_attr ..' ' .. k .. '="' .. tostring(v) ..'"'
				end
			end
		end
		
		local caption = f.caption
		
		fptable(html_table)
		output = html_table.template:gsub('$class', str_class)
		:gsub('$attr', str_attr)
		:gsub('$value', value or '')
		:gsub('$field', field)
		:gsub('$caption', caption or field)
	else
		-- output = ([[<label>id:</label><span name="id">$id</span>]]):gusb('$id', instance.id)
	end

	if attached.wrap then
		output = attached.wrap:format(output)
	end
	
	return output
end

function modelToViewMapping(instance, filters, attached)
	local output = ''
	
	local value_type = type(instance)
	if value_type == 'string' or value_type == 'number' then
		output = output + ('<span>%s</span>'):format(instance)

	elseif value_type == 'table' and isValidInstance(instance) then
		local fields = instance.__fields
		for field, fdt in pairs(fields) do

			local flag = true
			for k, v in pairs(filters or {}) do
				-- to redundant query condition, once meet, jump immediately
				if not fdt[k] then 
					-- flag=false;
					-- break
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
				output = output + fieldToViewMapping(instance, field, instance[field] or '', fdt, filters, attached)
			end
		end
	else
		output = output + ''
	end

	return output
end

function process( instance, restcode )

    assert(loadstring('_t = {' + restcode + ' }'), '[Error] wrong syntax in view tag {**}.')()
	assert(type(_t) == 'table')

	local filters = _t.filters
	assert(type(filters) == 'nil' or type(filters) == 'table')
	local attached = _t.attached
	assert(type(attached) == 'nil' or type(attached) == 'table')
	attached = attached or {}

    return modelToViewMapping(instance, filters, attached)

end
