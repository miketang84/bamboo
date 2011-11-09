Installation Guide For Other Platform
========================================

If you have no Ubuntu/Debian Environment, you can refer this command line list to install Bamboo.

Use the value of variable XXX defined in PREDEFINED table to replace the coresponding ${XXX} in the DIRECTIVES table. And input those commands in your terminal.

Good luck :)

	-- version define
	PREDEFINED = {
		LUA = "lua5.1",
		ZEROMQ = "zeromq-2.1.9",
		LIBLUA = "liblua5.1-0",
		SQLITE = "sqlite3",
		LIBSQLITE = "libsqlite3",
		MONGREL2 = "mongrel2-1.7.5",
		REDIS = "redis-2.2.13",
		LUAGD = "lua-gd-2.0.33r2",
		LUALIB_PATH = "/usr/local/lib/lua/5.1",
		LUASHARE_PATH = "/usr/local/share/lua/5.1",
	}
	
	-- directives
	DIRECTIVES = {
		-- install system dependencies
		'sudo apt-get install build-essential',
		'sudo apt-get install ${LIBLUA} ${LIBLUA}-dev luarocks',
		'sudo apt-get install uuid-dev ${SQLITE} ${LIBSQLITE}-dev git-core',
		'sudo apt-get install libgd2-noxpm libgd2-noxpm-dev',
		
		-- install source code
		'tar xvf tars/${ZEROMQ}.tar.gz && cd ${ZEROMQ} && ./configure && make && sudo make install && sudo ldconfig && cd ..',
		'tar xvf tars/${MONGREL2}.tar.bz2 && cd ${MONGREL2} && make && sudo make install && cd ..',
		'tar xvf tars/${REDIS}.tar.gz && cd ${REDIS} && make && sudo make install && cd .. && sudo cp -af configs/redis.conf /etc/',
		'tar xvf tars/${LUAGD}.tar.gz && cd ${LUAGD} && make && sudo cp -af gd.so ${LUALIB_PATH} && cd ..',
		'sudo cp -af configs/luarocks_config.lua /etc/luarocks/config.lua',
		'sudo mkdir -p /var/db/ && sudo chmod -R 777 /var/db/',
		
		-- install rocks
		'sudo luarocks  install lpeg ',
		'sudo luarocks  install lsqlite3 ',
		'sudo luarocks  install lua_signal ',
		'sudo luarocks  install lunit ',
		'sudo luarocks  install luajson ',
		'sudo luarocks  install luaposix ',
		'sudo luarocks  install luasocket ',
		'sudo luarocks  install md5 ',
		'sudo luarocks  install telescope ',
		
		-- install git source code
		'cd ~ && mkdir -p GIT',
		'cd ~/GIT && git clone git://github.com/iamaleksey/lua-zmq.git && cd lua-zmq && make && sudo cp -af zmq.so ${LUALIB_PATH}/',
		'cd ~/GIT && git clone git://github.com/jsimmons/mongrel2-lua.git && sudo ln -sdf  ~/GIT/mongrel2-lua/mongrel2  ${LUASHARE_PATH}/',
		'cd ~/GIT && git clone git://github.com/nrk/redis-lua.git && sudo ln -sf ~/GIT/redis-lua/src/redis.lua  ${LUASHARE_PATH}/',
		'cd ~/GIT && git clone git://github.com/jsimmons/tnetstrings.lua.git && sudo ln -sf ~/GIT/tnetstrings.lua/tnetstrings.lua ${LUASHARE_PATH}/',
		'cd ~/GIT && git clone git://github.com/daogangtang/lglib.git && sudo ln -sdf ~/GIT/lglib/src ${LUASHARE_PATH}/lglib',
		'cd ~/GIT && git clone git://github.com/daogangtang/bamboo.git && sudo ln -sdf ~/GIT/bamboo/src ${LUASHARE_PATH}/bamboo',
		'sudo ln -sf ${LUASHARE_PATH}/bamboo/bin/bamboo /usr/local/bin/',
		'sudo ln -sf ${LUASHARE_PATH}/bamboo/bin/bamboo_handler /usr/local/bin/',
		
		-- create workspace directory and global bamboo setting file workspace/settings.lua
		[[ cd ~ && mkdir -p workspace && echo monserver_dir = \"$(pwd)/workspace/monserver/\" >> settings.lua && echo bamboo_dir = \"$(pwd)/GIT/bamboo/\" >> settings.lua  ]],
		[[ cd ~/workspace && mkdir -p monserver && cd monserver && mkdir -p conf logs run sites tmp sites/apptest ]],
		[[ cp -af configs/mongrel2.conf ~/workspace/monserver/conf/ ]],
		
	}
	


