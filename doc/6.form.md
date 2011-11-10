# Form
Form is widely used to submit datas. 
## Parse
Suppose a form example:

    <form action="/search/" method="get">
        <input type="text" name="content" value="test">
        <input type="text" name="array[]" value="1">
        <input type="text" name="array[]" value="2">
        <input type="submit" value="Search">
    </form>

Then, in `/search/`'s handler, you can use following statements to parse the parameters.

	local Form = require 'bamboo.form'
	local params = Form:parse(req)
	
`params` is a table contains the data submitted by the form. Here, `params.content` is string 'test', `params.array` is a table `{'1', '2'}`.
Note: Form:parse(req) is suitable for both 'GET' and 'POST' methods. But sometimes you may want to use 'POST' to submit while 'action' contains extra parameters, in this case, use `Form:parseQuery(req)` to parse those parameters.
## MVM
Bamboo has a cool feature to quickly generate html element for field called MVM short for 'model-to-view mapping'. Suppose you have an instance called `inst`, here is a convenient way to generate a information editing form:

	<form action="/update/" method="post">
		{{inst:toHtml()}}
        <input type="submit" value="Update" />
	</form>
	
To enjoy the convenience of MVM, some information is recommended in FDT(Field Describe Table), for example:
	
	Student = Model:extend {
		...
		__field = {
			...
			gender = {enum={{'m', 'Male'}, {'f', 'Female'}}, widget_type='enum', id='gender', help='Select your gender'},
			desc = {widget_type='textarea'},
			...
		},
		...
	}
		
`widget_type` means which type of widget you want to use for this field, it's 'text' by default. There are also 'textarea', 'email', 'enum', 'date', 'foreign'.  
`id` means the the id of the widget, it's `'id_' .. fieldname` by default.  
`help` means the help description of this field, typically there will be a `span` to show the description following the widget.  
`widget_attr` means the extra attributes of the widget. For example, `widget_attr={readonly='true'}` will add `readonly="true"` attribute to the html element.
`widget_class` means the extra classes of the widget. For example, `widget_class={'ClassA', 'ClassB'}` will add class 'ClassA' and 'ClassB' to the html element.
Also, there are `help_attr` and `help_class` for extra information of the 'help' element.  

There is a more complicated example:

	<form action="/update/" method="post">
		{{inst:toHtml(
			format = '<div class="clearfix">$label<div class="input">$widget$help</div></div>',
			filters = {widget_type='enum'},
			attached = {editable=false},
		)}}
        <input type="submit" value="Update" />
	</form>
	
In this case, we input there parameters, `format`, `filters` and `attached`.
`format` is a string where `$lable`, `$widget` and `$help` will be replaced by the html elements, which offers a flexible way to generate a field element.  
`filters` can filter from the fields. In this case, only the fields whose `widget_type='enum'` will be showed.  
`attached` is extra information to all fields, this table will be merged into the FDT of fields. In this case, we make all fields element uneditable.
## Validate
Also, MVM provides a way by adding `rules` in the FDT to make javascript validating easier.  
For example:

	desc = {rules={rangelength={2,200}, required=true}},

Using MVM, you will get html code like this:

	<input type="text" id="id_desc class="" name="desc" validate="{'rangelength':[2,200],'required':true}" />
	
And now, we can use javascript to validate. For example, we use jquery & jquery.metadate & jquery.validation, we can simply add following code to do the validation:
	
	$(function(){
		$.metadata.setType("attr", "validate");
		$('#form').validate();
	});

Magic, isn't it?  
Also, these validation rules can be used on the server. If we want to validate the data submitted before create a new `User` instance, we can use following code:

	local params = Form:parse(req)
	local ret, err_msg = User:validate(params)

`ret` shows wether the data is valid or not. If not, `err_msg` is a table containing the error messages.
