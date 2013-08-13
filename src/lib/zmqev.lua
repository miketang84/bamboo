-- Copyright (c) 2010-2011 by Robert G. Jakabosky <bobby@neoawareness.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

local setmetatable = setmetatable
local print = print
local tinsert = table.insert
local tremove = table.remove
local pairs = pairs
local error = error
local type = type

local ev = require"ev"

assert(ev.Idle,"handler.zmq requires a version of lua-ev > 1.3 that supports Idle watchers.")

local zmq = require"zmq"
local z_SUBSCRIBE = zmq.SUBSCRIBE
local z_UNSUBSCRIBE = zmq.UNSUBSCRIBE
local z_IDENTITY = zmq.IDENTITY
local z_NOBLOCK = zmq.NOBLOCK
local z_RCVMORE = zmq.RCVMORE
local z_SNDMORE = zmq.SNDMORE
local z_EVENTS = zmq.EVENTS
local z_POLLIN = zmq.POLLIN
local z_POLLOUT = zmq.POLLOUT
local z_POLLIN_OUT = z_POLLIN + z_POLLOUT

local mark_SNDMORE = {}

local default_send_max = 50
local default_recv_max = 50

local function zsock_getopt(self, ...)
	return self.socket:getopt(...)
end

local function zsock_setopt(self, ...)
	return self.socket:setopt(...)
end

local function zsock_sub(self, filter)
	return self.socket:setopt(z_SUBSCRIBE, filter)
end

local function zsock_unsub(self, filter)
	return self.socket:setopt(z_UNSUBSCRIBE, filter)
end

local function zsock_identity(self, filter)
	return self.socket:setopt(z_IDENTITY, filter)
end

local function zsock_bind(self, ...)
	return self.socket:bind(...)
end

local function zsock_connect(self, ...)
	return self.socket:connect(...)
end

local function zsock_close(self)
	local send_queue = self.send_queue
	self.is_closing = true
	if not send_queue or #send_queue == 0 or self.has_error then
		if self.io_recv then
			self.io_recv:stop(self.loop)
		end
		self.io_idle:stop(self.loop)
		if self.socket then
			self.socket:close()
			self.socket = nil
		end
	end
end

local function zsock_handle_error(self, err)
	local handler = self.handler
	local errFunc = handler.handle_error
	self.has_error = true -- mark socket as bad.
	if errFunc then
		errFunc(self, err)
	else
		print('zmq socket: error ' .. err)
	end
	zsock_close(self)
end

local function zsock_enable_idle(self, enable)
	if enable == self.idle_enabled then return end
	self.idle_enabled = enable
	if enable then
		self.io_idle:start(self.loop)
	else
		self.io_idle:stop(self.loop)
	end
end

local function zsock_send_data(self, data, more)
	local s = self.socket

	local flags = z_NOBLOCK
	-- check for send more marker
	if more then
		flags = flags + z_SNDMORE
	end
	local sent, err = s:send(data, flags)
	if not sent then
		-- got timeout error block writes.
		if err == 'timeout' then
			-- block sending, data will queue until we can send again.
			self.send_blocked = true
			-- data in queue, mark socket for sending.
			self.need_send = true
			-- make sure idle watcher is running.
			zsock_enable_idle(self, true)
		else
			-- report error
			zsock_handle_error(self, err)
		end
		return false
	end
	if not more and self.state == "SEND_ONLY" then
		-- sent whole message, switch to receiving state
		self.state = "RECV_ONLY"
		-- make sure the idle callback is started
		zsock_enable_idle(self, true)
	end
	return true
end

local function zsock_send_queue(self)
	local send_max = self.send_max
	local count = 0
	local s = self.socket
	local queue = self.send_queue

	repeat
		local data = queue[1]
		-- check for send more marker
		local more = (queue[2] == mark_SNDMORE)
		local sent = zsock_send_data(self, data, more)
		if not sent then
			return
		end
		-- pop sent data from queue
		tremove(queue, 1)
		-- pop send more marker
		if more then
			tremove(queue, 1)
		else
			-- whole message sent
			count = count + 1
		end
		-- check if queue is empty
		if #queue == 0 then
			-- un-block socket
			self.need_send = false
			self.send_blocked = false
			-- finished queue is empty
			return
		end
	until count >= send_max
	-- hit max send and still have more data to send
	self.need_send = true
	-- make sure idle watcher is running.
	zsock_enable_idle(self, true)
	return
end

local function zsock_receive_data(self)
	local recv_max = self.recv_max
	local count = 0
	local s = self.socket
	local handler = self.handler
	local msg = self.recv_msg
	self.recv_msg = nil

	repeat
    local data, err = s:recv(z_NOBLOCK)
		if err then
			-- check for blocking.
			if err == 'timeout' then
				-- store any partial message we may have received.
				self.recv_msg = msg
				-- recv blocked
				self.recv_enabled = false
			else
				-- report error
				zsock_handle_error(self, err)
			end
			return
		end
		-- check for more message parts.
		local more = s:getopt(z_RCVMORE)
		if msg ~= nil then
			tinsert(msg, data)
		else
			if more == 1 then
				-- create multipart message
				msg = { data }
			else
				-- simple one part message
				msg = data
			end
		end
		if more == 0 then
			-- finished receiving whole message
			if self.state == "RECV_ONLY" then
				-- switch to sending state
				self.state = "SEND_ONLY"
			end
			-- pass read message to handler
			err = handler.handle_msg(self, msg)
			if err then
				-- report error
				zsock_handle_error(self, err)
				return
			end
			-- can't receive any more messages when in send_only state
			if self.state == "SEND_ONLY" then
				self.recv_enabled = false
				return
			end
			msg = nil
			count = count + 1
		end
	until count >= recv_max or self.is_closing

	-- save any partial message.
	self.recv_msg = msg

	-- hit max receive and we are not blocked on receiving.
	self.recv_enabled = true
	-- make sure idle watcher is running.
	zsock_enable_idle(self, true)
end

local function zsock_dispatch_events(self)
	local s = self.socket
	local readable = false
	local writeable = false

	-- check ZMQ_EVENTS
	local events = s:getopt(z_EVENTS)
	if events == z_POLLIN_OUT then
		readable = true
		writeable = true
	elseif events == z_POLLIN then
		readable = true
	elseif events == z_POLLOUT and self.need_send then
		writeable = true
	else
		-- no events read block until next read event.
		return zsock_enable_idle(self, false)
	end

	-- always read when the socket is readable
	if readable then
		zsock_receive_data(self)
	else
		-- recv is blocked
		self.recv_enabled = false
	end
	-- if socket is writeable and the send queue is not empty
	if writeable and self.need_send then
		zsock_send_queue(self)
	end
end

local function _queue_msg(queue, msg, offset, more)
	local parts = #msg
	-- queue first part of message
	tinsert(queue, msg[offset])
	for i=offset+1,parts do
		-- queue more marker flag
		tinsert(queue, mark_SNDMORE)
		-- queue part of message
		tinsert(queue, msg[i])
	end
	if more then
		-- queue more marker flag
		tinsert(queue, mark_SNDMORE)
	end
end

local function zsock_send(self, data, more)
	if type(data) == 'table' then
		local i = 1
		-- if socket is not blocked
		if not self.send_blocked then
			local parts = #data
			-- try sending message
			while zsock_send_data(self, data[i], true) do
				i = i + 1
				-- send last part of the message with the value from 'more'
				if i == parts then
					-- try sending last part of message
					if zsock_send_data(self, data[i], more) then
						return true, nil
					end
					-- failed to send last chunk, it will be queued
					break
				end
			end
		end
		-- queue un-sent parts of message
		_queue_msg(self.queue, data, i, more)
	else
		-- if socket is not blocked
		if not self.send_blocked then
			if zsock_send_data(self, data, more) then
				-- data sent we are finished
				return true, nil
			end
		end
		-- queue un-sent data
		local queue = self.send_queue
		-- queue simple data.
		tinsert(queue, data)
		-- check if there is more data to send
		if more then
			-- queue a marker flag
			tinsert(queue, mark_SNDMORE)
		end
	end
	return true, nil
end

local zsock_mt = {
send = zsock_send,
setopt = zsock_setopt,
getopt = zsock_getopt,
identity = zsock_identity,
bind = zsock_bind,
connect = zsock_connect,
close = zsock_close,
}
zsock_mt.__index = zsock_mt

local zsock_no_send_mt = {
setopt = zsock_setopt,
getopt = zsock_getopt,
identity = zsock_identity,
bind = zsock_bind,
connect = zsock_connect,
close = zsock_close,
}
zsock_no_send_mt.__index = zsock_no_send_mt

local zsock_sub_mt = {
setopt = zsock_setopt,
getopt = zsock_getopt,
sub = zsock_sub,
unsub = zsock_unsub,
identity = zsock_identity,
bind = zsock_bind,
connect = zsock_connect,
close = zsock_close,
}
zsock_sub_mt.__index = zsock_sub_mt

local type_info = {
	-- publish/subscribe sockets
	[zmq.PUB]  = { mt = zsock_mt, recv = false, send = true },
	[zmq.SUB]  = { mt = zsock_sub_mt, recv = true, send = false },
	-- push/pull sockets
	[zmq.PUSH] = { mt = zsock_mt, recv = false, send = true },
	[zmq.PULL] = { mt = zsock_no_send_mt, recv = true, send = false },
	-- two-way pair socket
	[zmq.PAIR] = { mt = zsock_mt, recv = true, send = true },
	-- request/response sockets
	[zmq.REQ]  = { mt = zsock_mt, recv = true, send = true, state = "SEND_ONLY" },
	[zmq.REP]  = { mt = zsock_mt, recv = true, send = true, state = "RECV_ONLY" },
	-- extended request/response sockets
	[zmq.XREQ] = { mt = zsock_mt, recv = true, send = true },
	[zmq.XREP] = { mt = zsock_mt, recv = true, send = true },
}

local function zsock_wrap(s, s_type, loop, msg_cb, err_cb)
	local tinfo = type_info[s_type]
	local handler = { handle_msg = msg_cb, handle_error = err_cb}
	-- create zmq socket
	local self = {
		s_type = s_type,
		socket = s,
		loop = loop,
		handler = handler,
		need_send = false,
		recv_enabled = false,
		idle_enabled = false,
		is_closing = false,
		state = tinfo.state, -- copy initial socket state.
	}
	setmetatable(self, tinfo.mt)

	local fd = s:getopt(zmq.FD)
	-- create IO watcher.
	if tinfo.send then
		self.send_blocked = false
		self.send_queue = {}
		self.send_max = default_send_max
	end
	if tinfo.recv then
		local recv_cb = function()
			-- check for the real events.
			zsock_dispatch_events(self)
		end
		self.io_recv = ev.IO.new(recv_cb, fd, ev.READ)
		self.recv_max = default_recv_max
		self.io_recv:start(loop)
	end
	local idle_cb = function()
		-- dispatch events.
		zsock_dispatch_events(self)
	end
	-- this Idle watcher is used to convert ZeroMQ FD's edge-triggered fashion to level-triggered
	self.io_idle = ev.Idle.new(idle_cb)
	if self.state == nil or self.state == 'RECV_ONLY' then
		zsock_enable_idle(self, true)
	end

	return self
end

local function create(self, s_type, msg_cb, err_cb)
	-- create ZeroMQ socket
	local s, err = self.ctx:socket(s_type)
	if not s then return nil, err end

	-- wrap socket.
	return zsock_wrap(s, s_type, self.loop, msg_cb, err_cb)
end

module(...)

-- copy constants
for k,v in pairs(zmq) do
	-- only copy upper-case string values.
	if type(k) == 'string' and k == k:upper() then
		_M[k] = v
	end
end

local meta = {}
meta.__index = meta
local function no_recv_cb()
	error("Invalid this type of ZeroMQ socket shouldn't receive data.")
end
function meta:pub(err_cb)
	return create(self, zmq.PUB, no_recv_cb, err_cb)
end

function meta:sub(msg_cb, err_cb)
	return create(self, zmq.SUB, msg_cb, err_cb)
end

function meta:push(err_cb)
	return create(self, zmq.PUSH, no_recv_cb, err_cb)
end

function meta:pull(msg_cb, err_cb)
	return create(self, zmq.PULL, msg_cb, err_cb)
end

function meta:pair(msg_cb, err_cb)
	return create(self, zmq.PAIR, msg_cb, err_cb)
end

function meta:req(msg_cb, err_cb)
	return create(self, zmq.REQ, msg_cb, err_cb)
end

function meta:rep(msg_cb, err_cb)
	return create(self, zmq.REP, msg_cb, err_cb)
end

function meta:xreq(msg_cb, err_cb)
	return create(self, zmq.XREQ, msg_cb, err_cb)
end

function meta:xrep(msg_cb, err_cb)
	return create(self, zmq.XREP, msg_cb, err_cb)
end

function meta:term()
	return self.ctx:term()
end

function init(loop, io_threads)
	-- create ZeroMQ context
	local ctx, err = zmq.init(io_threads)
	if not ctx then return nil, err end

	return setmetatable({ ctx = ctx, loop = loop }, meta)
end

