# View and Template
## Response in HTML
To respond a page, you can use `web:page(html_str)`, so the browser will recieve `html_str`.  
Always, we want to seperate html from handler to loose coupling. But how to communicate between handler and html, bamboo provides a powerful template system.
## Template system
For example:

	<html>
		<head><title>Fruit</title></head>
		<body>
			<p>Hello, {{ username }}!</p>
			<p>Here are the fruits you liked:</p>
			<ul>
				{% for _, fruit in ipaires(fruits) %}
					<li>{{ fruit }}</li>
				{% end %}
			</ul>
		</body>
	</html>

Save this html file as 'views/test.html'. To render this file, use following code:

	local View = require 'bamboo.view'
	local html_str = View('test.html'){ username='Young', fruits={'Apple', 'Orange', 'Watermelon'} }
	
After this, html_str will be:

	<html>
		<head><title>Fruit</title></head>
		<body>
			<p>Hello, Young!</p>
			<p>Here are the fruits you liked:</p>
			<ul>
				<li>Apple</li>
				<li>Orange</li>
				<li>Watermelon</li>
			</ul>
		</body>
	</html>
	
`{{ variable }}` means use the return value of `tostring(variable)` to replace this in the template.  
`{% statement %}` means `statement` will be executed as lua code.  
Usually, you can use `web:page(View('test.html'){ username='Young', fruits={'Apple', 'Orange', 'Watermelon'}})` to respond the rendered page.
Note: You can modify which directory to find html files by editing `views = "views/"` in `settings.lua`.
## Template Including & Inheritance
In many cases, you may slice the html file into several parts.
## Response in JSON
To respond in JSON format, you can use `web:json(data)`, where `data` is a table which will be transformed to a JSON format.
