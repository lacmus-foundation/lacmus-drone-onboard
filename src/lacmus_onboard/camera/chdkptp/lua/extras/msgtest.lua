--[[
 Copyright (C) 2010-2019 <reyalp (at) gmail dot com>
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

]]
--[[
a script for stressing the usb layer and message system

usage:
!m=require'extras/msgtest'
!m.test(options)
opions:{
	size=number     -- initial message size
	sizeend=number  -- end message size
	sizeinc=number  -- increment size by N
	count=number    -- number of messages
	verbose=number  -- level of verbosity, 2 = print a line for each message
	checkmem=bool   -- check free memory and lua allocated memory for each message
	memverbose=bool -- print memory stats for each message
	gc=string|false -- garbage collection mode, 'step', 'collect' or false
					-- defaults to 'step' if message size varies
	busy=bool		-- stress test keeping lua busy instead of yielding to wait for messages
	teststr=string  -- string to use for test messages, repeated / truncated as needed for size
	                --   should not include any msg_shell commands!
	showfailed=bool -- print failed. use 'hex' for hexdump, true for escaped string
	noscript=bool   -- send messages without script running allows arbitrary size
	                -- but content integrity and lua not tested
}
example
!m.test{size=100,sizeinc=10,sizeend=200,verbose=0,memverbose=true,checkmem=true,gc='step'}
]]
local m={}

local default_opts = {
	verbose = 2,
	checkmem = false,
	memverbose = false,
	gc = nil,
	teststr = 'x',
	showfailed = 'hex',
	noscript = false,
}

m.opts = {}

m.detailmsg = util.make_msgf( function() return m.opts.verbose end, 2)

function m.init_test()
	m.fail_count = 0
	m.run_count = 0
	m.send_time = 0
	if m.opts.checkmem then
		m.memstats = {
			free={},
			count={}
		}
	end
	if m.opts.noscript then
		if con:script_status().run then
			error('script is running')
		end
	else
		m.load()
		m.set_gc(m.opts.gc)
	end
	m.t0=ticktime.get()
	return true
end

function m.fmt_memstats(stats)
	local min=1000000000
	local max=0 
	local total = 0
	if #stats == 0 then
		return "no stats"
	end

	for i,v in ipairs(stats) do
		if v > max then
			max = v
		end
		if v < min then
			min = v
		end
		total = total + v
	end
	return string.format("min %d max %d avg %d",min, max, total/#stats)
end

function m.finish_test()
	if not m.opts.noscript then
		m.quit()
	end
	printf("ran %d fail %d time %.4f send time %.4f\n",m.run_count,m.fail_count,ticktime.elapsed(m.t0),m.send_time)
	if m.opts.checkmem then
		printf("free   (bytes): %s\n",m.fmt_memstats(m.memstats.free))
		printf("lua alloc (kb): %s\n",m.fmt_memstats(m.memstats.count))
	end
	return (m.fail_count == 0)
end

function m.load()
	con:exec('msg_shell:run()',{libs={'msg_shell','serialize'}})
	con:write_msg([[exec
msg_shell.read_msg_timeout = nil
msg_shell.default_cmd=function(msg)
	if msgtest_gc then
		collectgarbage(msgtest_gc)
	end
	write_usb_msg(msg)
end
msg_shell.cmds.memstats=function()
	write_usb_msg(serialize({mem=get_meminfo().free_size,lmem=collectgarbage('count')}))
end
]])
	if m.opts.busy then
		con:write_msg([[exec
set_yield(-1,-1)
msg_shell.read_msg_timeout = 0
msg_shell.idle = function()
	for i=1,1000 do
		x=string.format("0x%x",math.random(0xffff))
	end
	sleep(10)
	collectgarbage('step')
end
]])
	end
end

function m.quit()
	-- write quit message, wait for script to end
	local status,err=pcall(function()
		con:write_msg('quit')
		con:wait_status_pcall{run=false,timeout=500}
	end)
	if not status then
		printf("quit failed %s\n",tostring(err))
		m.fail_count = m.fail_count + 1
	end
end

function m.test_msg(len)
	m.run_count = m.run_count + 1
	local s=util.str_rep_trunc_to(m.opts.teststr,len)
	local t0=ticktime.get()
	if m.opts.noscript then
		local status,e=pcall(function() con:write_msg(s) end)
		m.send_time = m.send_time + ticktime.elapsed(t0)
		if status then
			error('script running') -- abort test if a script is running
		elseif type(e) == 'table' and e.etype == 'msg_notrun' then
			-- expect script not running error
			m.detailmsg('ok\n')
		else
			m.fail_count = m.fail_count + 1
			-- other error - re-throw
			error(e)
		end
		return
	end
	con:write_msg(s)
	m.send_time = m.send_time + ticktime.elapsed(t0)
	local r = con:wait_msg({mtype='user'})
	if s == r.value then 
		m.detailmsg('ok\n')
	else
		m.fail_count = m.fail_count + 1
		printf('failed\nmsg %d len %d not equal\n',m.run_count,len)
		if m.opts.showfailed then
			-- TODO should probably save and print at the end so they don't get lost in scrollback
			if m.opts.showfailed == 'hex' then
				printf('sent:\n%s\nrecv:\n%s\n',util.hexdump(s),util.hexdump(tostring(r.value)))
			else 
				printf('>%s\n<%s\n',util.str_escape_strict(s),util.str_escape_strict(tostring(r.value)))
			end
		end
	end
	if m.opts.checkmem then
		con:write_msg('memstats')
		r = con:wait_msg({mtype='user',munserialize=true})
		table.insert(m.memstats.free,r.mem)
		table.insert(m.memstats.count,r.lmem)
		if m.opts.memverbose then
			printf('free:%d lua alloc:%d kb\n',r.mem,r.lmem)
		end
	end
end

function m.test(opts)
	opts = util.extend_table_multi({},{default_opts,opts})
	
	m.opts = opts

	-- backward compatible for version that only supported positive inc
	if opts.sizemax then
		if opts.sizeend then
			error('sizemax and sizeend cannot be combined')
		end
		opts.sizeend = opts.sizemax
	end

	if opts.noscript then
		opts.gc = false -- gc makes no sense with noscript
		if opts.checkmem then
			error("noscript cannot be combined with checkmem")
		end
	end
	if not opts.size then 
		error("missing size")
	end

	if not opts.count then
		if opts.sizeinc and opts.sizeend then
			opts.count = math.floor((opts.sizeend - opts.size )/opts.sizeinc) + 1
			if opts.count <= 0 then
				error('invalid count '..opts.count)
			end
		else
			error("missing count")
		end
	end
	if opts.sizeinc == 0 then
		opts.sizeinc = nil
	end

	if opts.sizeinc and not opts.sizeend then
		opts.sizeend = opts.size + opts.count * opts.sizeinc
	end
	if opts.sizeend and opts.sizeend <= 0 then
		error('invalid sizeend '..tostring(opts.sizeend))
	end

	-- default gc to step if varying size
	if opts.sizeinc and opts.gc == nil then
		opts.gc='step'
	end
	if opts.gc and not util.in_table({'collect','step'},opts.gc) then
		error("invalid gc value "..tostring(opts.gc))
	end

	local size = opts.size

	printf("testing %d messages size %d",opts.count,size)
	if opts.sizeinc then
		printf("-%d, inc %d",opts.sizeend,opts.sizeinc)
	end
	if opts.noscript then
		printf(' no script')
	end
	if opts.gc then
		printf(' gc=%s',opts.gc)
	end
	printf("\n")
	m.init_test()
	for i=1,opts.count do
		m.detailmsg("send %d size:%d 0x%x...",i,size,size)
		local status,err=pcall(m.test_msg,size)
		if not status then
			printf("%s\n",tostring(err))
			printf("aborted at send %d size:%d 0x%0x, communication error\n",i,size,size)
			m.finish_test()
			return false
		end
		if opts.sizeinc and size ~= opts.sizeend then
			size = size + opts.sizeinc
		end
	end 
	return m.finish_test()
end

function m.set_gc(mode)
	if not mode then
		mode='nil'
	else
		mode = '"'..mode..'"'
	end
	con:write_msg('exec msgtest_gc='..mode)
end
return m
