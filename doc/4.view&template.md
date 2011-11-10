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
Usually, you can use `web:page(View('test.html'){ username='Young', fruits={'Apple', 'Orange', 'Watermelon'} })` to respond the rendered page.
Note: You can modify which directory to find html files by editing `views = "views/"` in `settings.lua`.
## Template Including
In many cases, you may slice the html file into several parts. For example, here is a page named index.html:

	<html>
		<head><title>Title</title></head>
		<body>
			<div class="header">
				{( "header.html" )}
			</div>
			<div class="content">
			</div>
			<div class="footer">
				{( "footer.html" )}
			</div>
		</body>
	</html>
	
If you use `web:page(View('index.html'){})`, `{( "header.html" )}` will be replaced by the content of header.html.  
## Template Inheritance
In many cases, there are different pages having similar structure, so you can write a template named base.html like this to reuse:

	<html>
		<head><title>Title</title></head>
		<body>
			<div class="header">
				Same header
			</div>
			<div class="content">
				{[ "content" ]}
			</div>
			<div class="footer">
				Same footer
			</div>
		</body>
	</html>
	
When another page named mypage.html want to inherit from base.html, you should write like this in mypage.html.

	{: "base.html" :}

	{[ ======== "content" ========
		Here is the content of mypage.html
	]}

`{: "base.html" :}` means this page inherits from base.html, whose `{[ "content" ]}` will be replaced by content between `{[ ======== "content" ========` and `]}`.  
So, `web:page(View('mypage.html'){})` will return following page:

	<html>
		<head><title>Title</title></head>
		<body>
			<div class="header">
				Same header
			</div>
			<div class="content">
				Here is the content of mypage.html
			</div>
			<div class="footer">
				Same footer
			</div>
		</body>
	</html>
	
Combining template including and template inheritance will make html editing more effective.
## Response in JSON
To respond in JSON format, you can use `web:json(data)`, where `data` is a table which will be transformed to a JSON format.
