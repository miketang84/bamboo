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
        <input type="submit" value="Update">
	</form>
	
