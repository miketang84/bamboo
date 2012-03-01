
MONDIR=~/workspace/monserver
GITDIR=~/GIT
SHAREDIR=/usr/local/share/lua/5.1
LIBDIR=/usr/local/lib/lua/5.1

all:
install:
	# monserver
	cd ../monserver && make && make install && cd -
	# lua-zmq
	cd ../lua-zmq && make &&  cp zmq.so ${LIBDIR} && cd -
	# lgstring
	cd ../lgstring && make && make install && cd -
	# monserver-lua
	ln -sdf  ${GITDIR}/monserver-lua/src   ${SHAREDIR}/monserver
	# redis-lua
	ln -sf  ${GITDIR}/redis-lua/src/redis.lua   ${SHAREDIR}
	# tnetstrings
	ln -sf  ${GITDIR}/tnetstrings.lua/tnetstrings.lua   ${SHAREDIR}
	# luajson
	cd ../luajson && make install && cd -
	# lglib
	ln -sdf ${GITDIR}/lglib/src  ${SHAREDIR}/lglib 
	# bamboo
	ln -sdf ${GITDIR}/bamboo/src   ${SHAREDIR}/bamboo 
	ln -sf ${SHAREDIR}/bamboo/bin/bamboo /usr/local/bin/ 
	ln -sf ${SHAREDIR}/bamboo/bin/bamboo_handler /usr/local/bin/ 
	# monserver dir
	mkdir -p ${MONDIR}/logs ${MONDIR}/run ${MONDIR}/sites ${MONDIR}/tmp ${MONDIR}/sites/apptest 
	chown -R ~/workspace/
	
	
