static_ajaxpaginator_test = { type="dir", base='sites/ajaxpaginator_test/', index_file='index.html', default_ctype='text/plain' }

handler_ajaxpaginator_test = { type="handler", send_spec='tcp://127.0.0.1:10001',
                send_ident='ba06f707-8647-46b9-b7f7-e641d6419909',
                recv_spec='tcp://127.0.0.1:10002', recv_ident=''}

main = {
    bind_addr = "127.0.0.1",
    uuid="505417b8-1de4-454f-98b6-07eb9225cca1",
    access_log="logs/access.log",
    error_log="logs/error.log",
    chroot="./",
    pid_file="run/mongrel2.pid",
    default_host="ajaxpaginator_test",
    name="main",
    port=6767,
    hosts= { 
		{   
			name="ajaxpaginator_test",
			matching = "xxxxxx", 
			routes={ 
				['/'] = handler_ajaxpaginator_test,
                ['/media/'] = static_ajaxpaginator_test
			} 
        },
    }
}


settings = {	
	['zeromq.threads'] = 1, 
	['limits.content_length'] = 20971520, 
	['upload.temp_store'] = '/tmp/mongrel2.upload.XXXXXX' 
}

mimetypes = {}

servers = { main }

