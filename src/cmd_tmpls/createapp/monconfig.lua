static_$PROJECT_NAME$ = { type="dir", base='sites/$PROJECT_NAME$/', index_file='index.html', default_ctype='text/plain' }

handler_$PROJECT_NAME$ = { type="handler", send_spec='tcp://127.0.0.1:10001',
                send_ident='ba06f707-8647-46b9-b7f7-e641d6419909',
                recv_spec='tcp://127.0.0.1:10002', recv_ident=''}

main = {
    bind_addr = "127.0.0.1",
    uuid="505417b8-1de4-454f-98b6-07eb9225cca1",
    access_log="logs/access.log",
    error_log="logs/error.log",
    chroot="./",
    pid_file="run/mongrel2.pid",
    default_host="$PROJECT_NAME$",
    name="main",
    port=6767,
    hosts= { 
		{   
			name="$PROJECT_NAME$",
			matching = "xxxxxx", 
			routes={ 
				['/'] = handler_$PROJECT_NAME$,
                ['/media/'] = static_$PROJECT_NAME$
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

