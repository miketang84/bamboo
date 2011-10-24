module(..., package.seeall)

function validateMax(value, field, limit_value)
	local num = tonumber(value)
	if num and num > limit_value then
		return false, ('The max input of $field is $limit_value'):gsub('$field', field):gsub('$limit_value', limit_value)
	end
	return true
end

function validateMin(value, field, limit_value)
	local num = tonumber(value)
	if num and num < limit_value then
		return false, ('The min input of $field is $limit_value'):gsub('$field', field):gsub('$limit_value', limit_value)
	end
	return true
end

function validateMinLength(value, field, limit_value)
	if #value < limit_value then
		return false, ('The minlength of $field is $limit_value'):gsub('$field', field):gsub('$limit_value', limit_value)
	end
	return true
end

function validateMaxLength(value, field, limit_value)
	if #value > limit_value then
		return false, ('The maxlength of $field is $limit_value'):gsub('$field', field):gsub('$limit_value', limit_value)
	end
	return true
end

function validateRange(value, field, limit_value)
	local min, max = unpack(limit_value)
	if validateMin(value, field, min) and validateMax(value, field, max) then
		return true
	else
		return false, ('The value of $field should be in the range of $min to $max'):gsub('$max', max):gsub('$min', min):gsub('$field', field)
	end
end

function validateRangeLength(value, field, limit_value)
	local min, max = unpack(limit_value)
	if validateMinLength(value, field, min) and validateMaxLength(value, field, max) then
		return true
	else
		return false, ('The length of $field should be in the range of $min to $max'):gsub('$max', max):gsub('$min', min):gsub('$field', field)
	end
end

function validateRequired(value, field, limit_value)
	if limit_value then
		if isEmpty(value) or value == '' then
			return false, ('Field $field is required'):gsub('$field', field)
		end
	end
	return true
end

function validateEmail(value, field, limit_value)
	if limit_value == true and value ~= '' then
		local regxp = '[%w_%.]+@%w+%.%w+'
		if not value:find(regxp) then
			return false, ('Please input an Email address to $field'):gsub('$field', field)
		end
	end
	return true
end

function validateDateISO(value, field, limit_value)
	if limit_value == true and value ~= '' then
		local regxp1 = '%d%d%d%d/%d%d/%d%d'
		local regxp2 = '%d%d%d%d%-%d%d%-%d%d'
		print(value)
		if not value:find(regxp1) and not value:find(regxp2) then
			return false, ('Please input a date to $field, the format is yyyy/mm/dd or yyyy-mm-dd'):gsub('$field', field) 
		end
	end
	return true
end

validators = {
	max = validateMax,
	min = validateMin,
	range = validateRange,
	minlength = validateMinLength,
	maxlength = validateMaxLength,
	rangelength = validateRangeLength,
	required = validateRequired,
	email = validateEmail,
	dateISO = validateDateISO,
}

return validators