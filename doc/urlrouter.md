# URL Routers

In the previous chapter, you have seen an lua-table URLS for router configurations in the handler_entry.lua file. Generally speaking, URLS is a global variable, which contains one list-element and key-value pairs. For example, 
	
	URLS = { '/',
		['/'] = index,
		['/index/'] = index,
		['/form_submit/'] = form_submit,
	}
		
where the value of first element `URLS[1]` is corresponding to router setting in the mongrel2.conf. Usually, it is chosen as `\` for non-complicated applications. The key of key-value pair is the url for each equest, and it must have an unique handler function. The convention of keys follows as:

+ first character of url string with more than one letter should be not '/', like '/index/' ---> 'index/'
+ the last character with '/' preferred, like '/form_submit' ----> 'form_submit/'
+ the url string can also be lua regular expression, that mapping a batch of requests with the same pattern into one handler function

After setting up URLS table, Bamboo splits URLS into two parts, specific-url part and general-url part. For a given url string, how does Bamboo find out the proper handler function? The procedures follow as:

1. Given a url string, bamboo does the hash search in specific-url part of URLS table with O(1);
2. If not found, bamboo would search general-url part of URLS table to match the given url string with O(N), where N is the number of urls with regular expressions; 
3. If still not found, response code **404** will be returned to clients.

