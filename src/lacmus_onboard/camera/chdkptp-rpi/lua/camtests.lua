--[[
 Copyright (C) 2013-2019 <reyalp (at) gmail dot com>
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
some tests to run against the camera
--]]
local m={}

function m.make_stats(stats)
	local r={
		total=0
	}

	if #stats == 0 then
		return r
	end

	for i,v in ipairs(stats) do
		if not r.max or v > r.max then
			r.max = v
		end
		if not r.min or v < r.min then
			r.min = v
		end
		r.total = r.total + v
	end
	r.mean = r.total/#stats
	return r
end


--[[
repeatedly start scripts, measuring time
opts:{
	count=number -- number of iterations
	code=string  -- code to run
}
]]
function m.exectime(opts)
	opts = util.extend_table({count=100, code="dummy=1"},opts)
	if not con:is_connected() then
		error('not connected')
	end
	local times={}
	local tstart = ticktime.get()
	for i=1,opts.count do
		local t0 = ticktime.get()
		con:exec(opts.code,{nodefaultlib=true})
		table.insert(times,ticktime.elapsed(t0))
		-- wait for the script to be done
		con:wait_status{run=false}
	end
	local wall_time = ticktime.elapsed(tstart)
	local stats = m.make_stats(times)
	printf("exec %d mean %.4f min %.4f max %.4f total %.4f (%.4f/sec) wall %.4f (%.4f/sec)\n",
		opts.count,
		stats.mean,
		stats.min,
		stats.max,
		stats.total, opts.count / stats.total, 
		wall_time, opts.count / wall_time)
end

--[[
repeatedly exec code and wait for return, checking that returned value = retval
opts:{
	count=number -- number of iterations
	code=string  -- code to run, should return something
	retval=value -- value code is expected to return
}
--]]
function m.execwaittime(opts)
	opts = util.extend_table({count=100, code="return 1",retval=1},opts)
	if not con:is_connected() then
		error('not connected')
	end
	local times={}
	local tstart = ticktime.get()
	for i=1,opts.count do
		local t0 = ticktime.get()
		local r = con:execwait(opts.code,{nodefaultlib=true,poll=50})
		if r ~= opts.retval then
			error('bad retval '..tostring(r) .. ' ~= '..tostring(opts.retval))
		end
		table.insert(times,ticktime.elapsed(t0))
	end
	local wall_time = ticktime.elapsed(tstart)
	local stats = m.make_stats(times)
	printf("execw %d mean %.4f min %.4f max %.4f total %.4f (%.4f/sec) wall %.4f (%.4f/sec)\n",
		opts.count,
		stats.mean,
		stats.min,
		stats.max,
		stats.total, opts.count / stats.total, 
		wall_time, opts.count / wall_time)
end

function m.fake_rsint_input(seq)
	return function()
		while true do
			-- ensure sequence ends
			if #seq == 0 then
				return 'l'
			end
			local op=table.remove(seq,1)
			if type(op) == 'number' then
				sys.sleep(op)
			elseif type(op) == 'string' then
				return op
			end
		end
	end
end

--[[
repeatedly time memory transfers from cam
opts:{
	count=number -- number of iterations
	size=number  -- size to transfer
	addr=number  -- address to transfer from (default 0x1900)
	buffer=bool  -- use camera side buffered getmem
}
]]
function m.xfermem(opts)
	opts = util.extend_table({count=100, size=1024*1024,addr=0x1900,buffer=false},opts)
	if not con:is_connected() then
		error('not connected')
	end
	local times={}
	local tstart = ticktime.get()
	local flags = 0
	if opts.buffer then
		flags = 1
	end
	for i=1,opts.count do
		local t0 = ticktime.get()
		local v=con:getmem(opts.addr,opts.size,'string',flags)
		table.insert(times,ticktime.elapsed(t0))
	end
	local wall_time = ticktime.elapsed(tstart)
	local stats = m.make_stats(times)
	printf("%d x %d bytes mean %.4f min %.4f max %.4f total %.4f (%d byte/sec) wall %.4f (%d byte/sec)\n",
		opts.count,
		opts.size,
		stats.mean,
		stats.min,
		stats.max,
		stats.total, opts.count*opts.size / stats.total, 
		wall_time, opts.count*opts.size / wall_time)
end
local tests = {}

function m.cliexec(cmd)
	local status,err=cli:execute(cmd)
	if not status then
		error(err,2)
	end
	cli:print_status(true,err)
end

-- return output on success instead of printing
function m.cliexec_ret_ok(cmd)
	local status,err=cli:execute(cmd)
	if not status then
		error(err,2)
	end
	return err
end

-- return output on on fail, assert on success
function m.cliexec_ret_fail(cmd)
	local status,err=cli:execute(cmd)
	if not status then
		return err
	end
	error('command succeeded when expected to fail')
end

function m.makelocalfile(path,content)
	fsutil.mkdir_parent(path)
	fsutil.writefile_e(content,path,'wb')
end

function m.readlocalfile(path)
	assert(lfs.attributes(path,'mode') == 'file')
	local content=fsutil.readfile_e(path,'b')
	assert(content)
	return content
end

function m.comparefiles(path1,path2)
	local mode=lfs.attributes(path1,'mode')
	assert(mode == lfs.attributes(path2,'mode'))
	if mode ~= 'file' then
		return
	end
	assert(m.readlocalfile(path1)==m.readlocalfile(path2))
end

function m.fmt_meminfo_num(v)
	if v then 
		return string.format('%d',v)
	end
	return '-'
end

function m.fmt_meminfo(mi)
	local start
	if mi.start_address then
		start=string.format('%#08x',mi.start_address)
	else
		start='-'
	end
	return string.format('%s heap start:%s size:%s free:%s free_block_max:%s',
						mi.name,start,
						m.fmt_meminfo_num(mi.total_size),
						m.fmt_meminfo_num(mi.free_size),
						m.fmt_meminfo_num(mi.free_block_max_size))
end

function tests.xfer()
	m.xfermem({count=50})
end
function tests.xferbuf()
	m.xfermem({count=50,buffer=true})
end

function tests.exectimes()
	m.execwaittime({count=50})
	m.exectime({count=50})
end

function tests.exec_errors()
	con:exec('sleep(500)')
	local status,err=con:exec_pcall('print"test"')
	assert((not status) and err.etype == 'execlua_scriptrun')
	-- test killscript if compatible
	if con:is_ver_compatible(2,6) then
		con:execwait('print"kill"',{clobber=true})
	else
		-- otherwise just wait
		sys.sleep(600)
	end
	status,err=con:exec_pcall('bogus(')
	assert((not status) and err.etype == 'execlua_compile')
end
function tests.not_connected()
	if con:is_connected() then
		error('already connected')
	end
	local status,err=con:script_status_pcall()
	assert((not status) and err.ptp_rc == ptp.ERROR_NOT_CONNECTED)
end

-- prepare for connected tests by connecting
-- devspec is a string for connect
function tests.connect(devspec)
	local devs=chdk.list_usb_devices()
	if #devs == 0 and not devspec then
		error('no usb devices available')
	end
	if con:is_connected() then
		error('already connected')
	end
	local cmd = 'c'
	if devspec then
		cmd = cmd .. ' ' .. devspec
	else
		printf('using default device\n')
	end
	m.cliexec(cmd)
	assert(con:is_connected())
end

function tests.cam_info()
	local bi,meminfo,sdinfo=con:execwait[[
return get_buildinfo(),{
	combined=get_meminfo(),
	system=get_meminfo('system'),
	aram=get_meminfo('aram'),
	exmem=get_meminfo('exmem')
},{
	size=get_disk_size(),
	free=get_free_disk_space(),
}
]]
	printf('platform:%s-%s version:%s-%s built:%s %s\n',
			bi.platform,bi.platsub,bi.build_number,bi.build_revision,
			bi.build_date,bi.build_time)
	printf('CHDK core start:%#08x size:%d total free:%s\n',
			meminfo.combined.chdk_start,
			meminfo.combined.chdk_size,
			m.fmt_meminfo_num(meminfo.combined.free_size))
	for _,heapname in ipairs({'system','aram','exmem'}) do
		local mi=meminfo[heapname]
		if mi then
			printf('%s\n',m.fmt_meminfo(mi))
		end
	end
	printf('SD size:%d KB free:%d KB\n',sdinfo.size,sdinfo.free)
end

function tests.list_connected()
	local list=m.cliexec_ret_ok('list')
	local lines=util.string_split(list,'\n',{plain=true,empty=false})
	for i,l in ipairs(lines) do
		-- match the current (marked *) device, grab bus and dev name
		local bus,dev=string.match(lines[1],'^%*%d+:.*b=([%S]+) d=([%S]+)')
		if bus then
			assert(bus==con.condev.bus and dev==con.condev.dev)
			return true
		end
	end
	error('current dev not found')
end
function tests.wait_status()
	local status=con:wait_status{msg=true,timeout=100}
	assert(status.timeout)
	local pstatus,status=con:wait_status_pcall{msg=true,timeout=100,timeout_error=true}
	assert(status.etype=='timeout')
end
function tests.msgfuncs()
	-- test script not running
	local status,err=con:write_msg_pcall("test")
	assert((not status) and err.etype == 'msg_notrun')
	-- test flushmsgs
	con:exec('write_usb_msg("msg1") return 2,3')
	con:wait_status{run=false}
	status = con:script_status()
	assert(status.msg == true)
	con:flushmsgs()
	status = con:script_status()
	assert(status.msg == false)
	con:exec('write_usb_msg("msg2") return 1')
	local m=con:wait_msg({mtype='user'})
	assert(m.type=='user' and m.value == 'msg2')
	m=con:wait_msg({mtype='return'})
	assert(m.type=='return' and m.value == 1)
	status,err=pcall(con.wait_msg,con,{mtype='return',timeout=100})
	assert(err.etype=='timeout',tostring(err))
	con:exec('return 1')
	status,err=pcall(con.wait_msg,con,{mtype='user'})
	assert(err.etype=='wrongmsg',tostring(err))
end

function m.do_filexfer(ldir,size,teststr)
	if not teststr then
		teststr='The quick brown fox jumps over the lazy dog\n\0more after the null!\xff\n1234567890'
	end
	local fn
	if size > 1024*1024 then
		fn=string.format('TST%04dM.dat',size/(1024*1024))
	elseif size > 1024 then
		fn=string.format('TST%04dK.dat',size/1024)
	else
		fn=string.format('TEST%04d.dat',size)
	end
	local lfn=string.format('%s/%s',ldir,fn)
	local dfn=string.format('%s/d_%s',ldir,fn)
	local s1=util.str_rep_trunc_to(teststr,size)
	m.makelocalfile(lfn,s1)
	m.cliexec('u '..lfn)
	m.cliexec('d '..fn .. ' ' .. dfn)
	local s2=m.readlocalfile(dfn)
	assert(s1==s2)
	m.cliexec('rm '..fn)
end

function tests.filexfer()
	local ldir='camtest'

	for i,size in ipairs({511,512,4096,(256*1024),(500*1024)}) do
		m.do_filexfer(ldir,size)
	end
	fsutil.rm_r(ldir)
end

function tests.mfilexfer()
	local ldir='camtest'
	-- names are in caps since cam may change, client may be case sensitive
	m.makelocalfile(ldir..'/up/EMPTY.TXT','')
	m.makelocalfile(ldir..'/up/ONE.TXT','one')
	m.makelocalfile(ldir..'/up/SUB1/SUB.TXT',string.rep('subtext',1000))
	fsutil.mkdir_m(ldir..'/up/EMPTYSUB')
	m.cliexec('mup '..ldir..'/up muptest')
	m.cliexec('mdl muptest '..ldir..'/dn')
	m.comparefiles(ldir..'/up/EMPTY.TXT',ldir..'/dn/EMPTY.TXT')
	m.comparefiles(ldir..'/up/ONE.TXT',ldir..'/dn/ONE.TXT')
	m.comparefiles(ldir..'/up/SUB1/SUB.TXT',ldir..'/dn/SUB1/SUB.TXT')
	m.comparefiles(ldir..'/up/EMPTYSUB',ldir..'/dn/EMPTYSUB')
	-- test with subst strings
	m.cliexec('mdl muptest '..ldir..'/dn2/${s_lower,${basename}${ext}}')
	m.comparefiles(ldir..'/up/EMPTY.TXT',ldir..'/dn2/empty.txt')
	m.comparefiles(ldir..'/up/ONE.TXT',ldir..'/dn2/one.txt')
	m.comparefiles(ldir..'/up/SUB1/SUB.TXT',ldir..'/dn2/sub.txt')
	m.comparefiles(ldir..'/up/EMPTYSUB',ldir..'/dn2/emptysub')
	m.cliexec('rm muptest')
	-- test on non-existing dir
	local s=m.cliexec_ret_fail('mdl muptest '..ldir)
	assert(string.sub(s,1,10) == 'A/muptest:') -- exact message varies by cam
	fsutil.rm_r(ldir)
end

function tests.rmemfile()
	local ldir='camtest'
	local fn=ldir..'/rmem.dat'
	local out=m.cliexec_ret_ok('rmem 0x1900 0x400 -f='..fn)
	assert(out == '0x00001900 1024 '..fn..'\n')
	assert(lfs.attributes(fn).size == 1024)
	fsutil.rm_r(ldir)
end

function tests.lvdump()
	local ldir='camtest'
	m.cliexec('lvdumpimg -count=2 -vp='..ldir..'/${frame}.ppm -bm='..ldir..'/${frame}.pam -quiet')
	assert(lfs.attributes(ldir..'/000001.pam','mode') == 'file')
	assert(lfs.attributes(ldir..'/000001.ppm','mode') == 'file')
	m.cliexec('lvdump -count=2 -quiet '..ldir..'/test.lvdump')
	assert(lfs.attributes(ldir..'/test.lvdump','mode') == 'file')
	fsutil.rm_r(ldir)
end


function tests.msgs()
	local mt=require'extras/msgtest'
	assert(mt.test({size=1,sizeinc=1,count=100,verbose=0}))
	assert(con:wait_status{run=false})
	assert(mt.test({size=10,sizeinc=10,count=100,verbose=0}))
end

function tests.xferbug_0x23f4()
	local mt=require'extras/msgtest'
	-- early dryos (e.g. D10) fail transfers to cached memory where size=0x23f4 + n*512
	-- https://chdk.setepontos.com/index.php?topic=4338.1150
	assert(mt.test({size=0x23f4,sizeinc=128,count=8,verbose=0,teststr='Hello world'}))
	assert(con:wait_status{run=false})
end

function tests.xferbug_0x1f5()
	local mt=require'extras/msgtest'
	-- cameras which fail on multiple recv_data calls where total size
	-- (512*n) - 11 to (512*n)
	-- https://chdk.setepontos.com/index.php?topic=4338.msg140577#msg140577

	-- default code transfers in chunks up to free_block_max_size/2
	local mi=con:execwait([[return get_meminfo()]])
	local msize=math.floor((mi.free_block_max_size/2)/512)*512 - 11
	-- running 600 takes care of variation due to lua being loaded for get_meminfo, 
	-- without script running, sent messages are discarded in chunks so no risk of OOM
	assert(mt.test({noscript=true,size=msize,sizeinc=512,count=600,verbose=0}))
	-- test near 256K, 512K in case using native buffer
	assert(mt.test({noscript=true,size=1024*255 - 11,sizeinc=512,count=5,verbose=0}))
	assert(mt.test({noscript=true,size=1024*511 - 11,sizeinc=512,count=5,verbose=0}))
	-- file - tests data, but less exhaustive size range
	local ldir='camtest'

--	problem size (256*1024 + 501 - 4 - 13)
	for i,size in ipairs({(256*1024 + 501 - 17),msize - 17,msize+512-17}) do
		m.do_filexfer(ldir,size)
	end
	fsutil.rm_r(ldir)
end

function tests.rec()
	m.cliexec('rec')
	sys.sleep(250)
end

function tests.rec_info()
	local ri=con:execwait[[
props=require'propcase'
capmode=require'capmode'
function get_halfpress_vals(ri)
	ri.tv=get_prop(props.TV)
	ri.av=get_prop(props.AV)
	ri.min_av=get_prop(props.MIN_AV)
	ri.sv=get_prop(props.SV)
	ri.sv_market=get_prop(props.SV_MARKET)
	ri.bv=get_prop(props.BV)
	ri.sd=get_focus()
	ri.sd_ok=get_focus_ok()
	ri.nd=get_nd_current_ev96()
end

is_rec,is_vid,mode=get_mode()
ri={
	mode=capmode.get(),
	is_vid=is_vid,
	mode_name=capmode.get_name(),
	iso_mode=get_prop(props.ISO_MODE),
	flash_mode=get_prop(props.FLASH_MODE),
	focus_mode=get_focus_mode(),
	nd_present=get_nd_present(),
	resolution=get_prop(props.RESOLUTION),
	quality=get_prop(props.QUALITY),
	zoom=get_zoom(),
	zoom_steps=get_zoom_steps(),
	rc=get_usb_capture_support(),
	propset=get_propset(),
}
if is_vid or not is_rec then
	get_halfpress_vals(ri)
else
	press'shoot_half'
	timeout=get_tick_count()+2000
	repeat
		sleep(10)
		if get_tick_count() > timeout then
			ri.timeout=true
		end
	until get_shooting() or ri.timeout
	get_halfpress_vals(ri)
	release'shoot_half'
end
return ri
]]
	printf('Rec info:\n')
	local mode_type
	if ri.is_vid then
		mode_type = ',video'
	elseif ri.mode == 0 then
		mode_type = ''
	else
		mode_type = ',still'
	end
	printf('Propset:%d mode:%s (%d%s) flash_m:%d iso_m:%d ', 
		ri.propset,ri.mode_name,ri.mode,mode_type,ri.flash_mode,ri.iso_mode)
	printf('focus_m:%d ND:%d zoom:%d/%d rc:%d res:%d qual:%d\n',
			ri.focus_mode,ri.nd_present,ri.zoom,ri.zoom_steps,ri.rc,ri.resolution,ri.quality)
	printf('Exposure info:\n')
	if ri.timeout then
		printf('WARNING: half press timed out\n')
	end
	local sd_ok
	if ri.sd_ok then
		sd_ok = 'OK'
	else
		sd_ok = '!OK'
	end
	printf('Tv:%s (%d) Av:%0.1f (%d) minAv:%0.1f (%d) Sv:%d (%d) SvM:%d (%d) Bv:%d (%d) NDEv:%d (%d) SD:%d,%s\n',
			exp.tv96_to_shutter_str(ri.tv),ri.tv,
			exp.av96_to_f(ri.av),ri.av,
			exp.av96_to_f(ri.min_av),ri.min_av,
			exp.sv96_to_iso(ri.sv),ri.sv,
			exp.sv96_to_iso(ri.sv_market),ri.sv_market,
			ri.bv/96,ri.bv,
			ri.nd/96,ri.nd,
			ri.sd,
			sd_ok)
end

function tests.remoteshoot()
	-- check filewrite capability (could do RAW/DNG only)
	if not con:execwait([[ return (bitand(get_usb_capture_support(),7) == 7) ]]) then
		printf('cam does not support remote capture, skipping\n')
		return
	end
	-- try to set the camera to a normal shooting mode
	con:execwait([[
capmode=require'capmode'
if not capmode.set('P') then
	error('capmode.set failed')
end
sleep(200)
if capmode.get_name() ~= 'P' then
	error('failed to set mode')
end
]])
	local ldir='camtest'
	fsutil.mkdir_m(ldir)
	-- TODO would be good to sanity check files
	m.cliexec(string.format('remoteshoot -jpg -jpgdummy %s/',ldir))

	m.cliexec(string.format('remoteshoot -seq=100 -dng -jpg -jpgdummy %s/${imgpfx}_${imgfmt}_${shotseq}${ext}',ldir))
	assert(prefs.cli_shotseq == 101)
	assert(lfs.attributes(ldir..'/IMG_JPG_0100.jpg','mode') == 'file')
	assert(lfs.attributes(ldir..'/IMG_DNG_0100.dng','mode') == 'file')

	m.cliexec(string.format('remoteshoot -raw -dnghdr -jpgdummy %s/${imgfmt}_${shotseq}${ext}',ldir))
	assert(prefs.cli_shotseq == 102)
	assert(lfs.attributes(ldir..'/RAW_0101.raw','mode') == 'file')
	assert(lfs.attributes(ldir..'/DNG_HDR_0101.dng_hdr','mode') == 'file')

	m.cliexec(string.format('remoteshoot -quick=3 -jpg -jpgdummy %s/${imgfmt}_${shotseq}${ext}',ldir))
	assert(prefs.cli_shotseq == 105)
	m.cliexec(string.format('remoteshoot -quick=3 -int=5 -jpg -jpgdummy %s/${imgfmt}_${shotseq}${ext}',ldir))
	-- check if cont mode enabled
	if con:execwait([[ return (get_prop(require'propcase'.DRIVE_MODE) == 1) ]]) then
		m.cliexec(string.format('remoteshoot -cont=3 -jpg -jpgdummy %s/${name}',ldir))
	else
		printf('cont mode not set, skipping remoteshoot cont test\n')
	end
	-- TODO cleanup jpeg dummies on cam, need to be in playback to avoid crash
	fsutil.rm_r(ldir)
end

function tests.rsint()
	-- setup / cleanup duplicated from remoteshoot
	-- check filewrite capability (could do RAW/DNG only)
	if not con:execwait([[ return (bitand(get_usb_capture_support(),7) == 7) ]]) then
		printf('cam does not support remote capture, skipping\n')
		return
	end
	-- try to set the camera to a normal shooting mode
	con:execwait([[
capmode=require'capmode'
if not capmode.set('P') then
	error('capmode.set failed')
end
sleep(200)
if capmode.get_name() ~= 'P' then
	error('failed to set mode')
end
]])
	local ldir='camtest'
	fsutil.mkdir_m(ldir)
	local rsint=require'rsint'
	-- build arguments for rsint.run instead of using cli so we can override input
	-- have to set some options that default to non-false in cli code (e.g. u)
	assert(rsint.run{
		[1]=ldir..'/${imgfmt}_${shotseq}${ext}',
		u='s',
		seq=200,
		cmdwait=60,
		jpg=true,
		jpgdummy=true,
		input_func=m.fake_rsint_input{
			's',
			5000,
			's',
			5000,
			'q',
		}
	})
	if con:execwait([[ return (get_prop(require'propcase'.DRIVE_MODE) == 1) ]]) then
		assert(rsint.run{
			[1]=ldir..'/',
			u='s',
			cmdwait=60,
			cont=true,
			jpg=true,
			jpgdummy=true,
			input_func=m.fake_rsint_input{
				's',
				5000,
				's',
				5000,
				'l',
			}
		})
	else
		printf('cont mode not set, skipping rsint cont test\n')
	end
	
	fsutil.rm_r(ldir)
end

function tests.shoot()
	local ldir='camtest'
	fsutil.mkdir_m(ldir)
	-- imgfmt avoids depending on camera ext settings
	m.cliexec(string.format('shoot -dng=1 -seq=300 -dl=%s/IMG_${shotseq}.${imgfmt}',ldir))
	assert(prefs.cli_shotseq == 301)
	assert(lfs.attributes(ldir..'/IMG_0300.JPG','mode') == 'file')
	assert(lfs.attributes(ldir..'/IMG_0300.DNG','mode') == 'file')
	-- TODO should clean up camera files
	fsutil.rm_r(ldir)
end

function tests.play()
	sys.sleep(250)
	m.cliexec('play')
	sys.sleep(250)
end

function tests.reconnect()
	assert(con:is_connected())
	m.cliexec('reconnect')
	assert(con:is_connected())
end

function tests.disconnect()
	m.cliexec('dis')
	assert(not con:is_connected())
end

function m.run(name,...)
	if not m.passed then
		m.passed = 0
	end
	if not m.failed then
		m.failed = 0
	end
	if not tests[name] then
		printf('unknown test\n')
		return false
	end
	printf('%s:start\n',name)
	status,msg = xpcall(tests[name],errutil.format_traceback,...)
	printf('%s:',name)
	if status then
		m.passed = m.passed + 1
		printf('ok\n')
		return true
	else
		m.failed = m.failed + 1
		printf('failed %s\n',msg)
		return false
	end
end

--[[
opts:{
	devspec=<usb device spec> -- specify which device to use, default to first available
	bench=bool -- run "benchmark" tests
	xfersizebugs=bool -- test for specific PTP transfer bugs
	filexfer=bool -- run file transfer tests
	shoot=bool -- tests that involve switching to rec mode and shooting
}
NOTE
filexfer creates and deletes various hard coded paths, both locally and on the camera
]]
function m.runbatch(opts)
	opts = util.extend_table({},opts)
	-- if connect fails, don't try to run anything else
	m.passed = 0
	m.failed = 0
	if not m.run('connect',opts.devspec) then
		printf('aborted\n')
		return false
	end
	m.run('cam_info')
	m.run('list_connected')
	m.run('wait_status')
	m.run('exec_errors')
	m.run('msgfuncs')
	if opts.bench then
		m.run('exectimes')
		m.run('xfer')
		m.run('xferbuf')
		m.run('msgs')
	end
	if opts.xfersizebugs then
		m.run('xferbug_0x23f4')
		m.run('xferbug_0x1f5')
	end
	if opts.filexfer then
		m.run('filexfer')
		m.run('mfilexfer')
		m.run('rmemfile')
		m.run('lvdump')
	end
	if opts.shoot then
		if m.run('rec') then
			m.run('rec_info')
			-- save and restore cli_shotseq
			local cli_shotseq = prefs.cli_shotseq
			m.run('remoteshoot')
			m.run('rsint')
			m.run('shoot')
			prefs.cli_shotseq = cli_shotseq
			m.run('play')
		end
	end
	m.run('reconnect')
	m.run('disconnect')
	m.run('not_connected')
	printf("passed %d\nfailed %d\n",m.passed,m.failed)
	return m.failed == 0
end

return m
