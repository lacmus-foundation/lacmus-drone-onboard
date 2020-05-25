props=require("propcase")

zoom_setpoint = 0      --"Zoom position" { Off 0% 10% 20% 30% 40% 50% 60% 70% 80% 90% 100% }
focus_at_infinity = true  --"Focus @ Infinity"

-- @subtitle Exposure Settings
tv96min = 2       --"Tv Minimum (sec)"   { None 1/60 1/100 1/200 1/400 1/640 1/800 1/1000 1/1250 1/1600 1/2000 }
tv96target = 5       --"TV Target  (sec)"   { 1/100 1/200 1/400 1/640 1/800 1/1000 1/1250 1/1600 1/2000 1/5000
tv96max = 3       --"Tv Maximum (sec)"   { 1/1000 1/1250 1/1600 1/2000 1/5000 1/10000 }
av96minimum = 4       --"Av Minimimum (f-stop)" { 1.8 2.0 2.2 2.6 2.8 3.2 3.5 4.0 4.5 5.0 5.6 6.3 7.1 8.0 }
av96target = 7       --"Av Target    (f-stop)" { 1.8 2.0 2.2 2.6 2.8 3.2 3.5 4.0 4.5 5.0 5.6 6.3 7.1 8.0 }
av96max = 13      --"Av Maximim   (f-stop)" { 1.8 2.0 2.2 2.6 2.8 3.2 3.5 4.0 4.5 5.0 5.6 6.3 7.1 8.0 }
sv96min = 1       --"ISO Minimum  " {  80 100 200 400 800 1250 1600 }
sv96max1 = 2       --"ISO Maximum 1" { 100 200 400 800 1250 1600 }
sv96max2 = 3       --"ISO Maximum 2" { 100 200 400 800 1250 1600 }
allow_nd_filter = true    --"Allow use of ND filter?"
ec96adjust = 6       --"Exposure Comp (stops)" { -2.0 -1.66 -1.33 -1.0 -0.66 -0.33 0.0 0.33 0.66 1.00 1.33 1.66 2.00 }


-- convert user parameter to more useful values
tv_table        = { -320, 576, 640, 736, 832, 896, 928, 960, 992, 1024, 1056, 1180, 1276}
tv96target      = tv_table[tv96target+3]
tv96max         = tv_table[tv96max+8]
tv96min         = tv_table[tv96min+1]
sv_table        = { 381, 411, 507, 603, 699, 761, 795 }             -- ISO market to sv96 real
sv96min         = sv_table[sv96min+1]
sv96max1        = sv_table[sv96max1+2]
sv96max2        = sv_table[sv96max2+2]
av_table        = { 171, 192, 218, 265, 285, 322, 347, 384, 417, 446, 477, 510, 543, 576 }
av96target      = av_table[av96target+1]
av96minimum     = av_table[av96minimum+1]
av96max         = av_table[av96max+1]
ec96adjust      = (ec96adjust - 6)*32

nd96offset = 3*96
infx = 50000


if ( zoom_setpoint==0 ) then zoom_setpoint = nil  else zoom_setpoint = (zoom_setpoint-1)*10 end
-- if ( script_timeout ~= 0 ) then script_timeout = get_tick_count() + script_timeout*60000 end

-- Basic exposure calculation using shutter speed, iris and ISO
--   called for iris-only and "both" cameras (cameras with an iris & ND filter)
function basic_iris_calc()
    tv96setpoint = tv96target
    av96setpoint = av96target
 -- calculate required ISO setting
    sv96setpoint = tv96setpoint + av96setpoint - bv96meter
 -- low ambient light ?
    if (sv96setpoint > sv96max1 ) then                                 -- check if required ISO setting is too high
        sv96setpoint = sv96max1                                        -- clamp at first ISO limit
        av96setpoint = bv96meter + sv96setpoint - tv96setpoint         -- calculate new aperture setting
        if ( av96setpoint < av96min ) then                             -- check if new setting is goes below lowest f-stop
            av96setpoint = av96min                                     -- clamp at lowest f-stop
            sv96setpoint = tv96setpoint + av96setpoint - bv96meter     -- recalculate ISO setting
            if (sv96setpoint > sv96max2 ) then                         -- check if the result is above max2 ISO
                sv96setpoint = sv96max2                                -- clamp at highest ISO setting if so
                tv96setpoint = math.max(bv96meter+sv96setpoint-av96setpoint,tv96min)  -- recalculate required shutter speed down to tv minimum
            end
        end
 -- high ambient light ?
    elseif (sv96setpoint < sv96min ) then                              -- check if required ISO setting is too low
        sv96setpoint = sv96min                                         -- clamp at minimum ISO setting if so
        tv96setpoint = bv96meter + sv96setpoint - av96setpoint         -- recalculate required shutter speed
        if (tv96setpoint > tv96max ) then                              -- check if shutter speed now too fast
            tv96setpoint = tv96max                                     -- clamp at maximum shutter speed if so
            av96setpoint = bv96meter + sv96setpoint - tv96setpoint     -- calculate new aperture setting
            if ( av96setpoint > av96max ) then                         -- check if new setting is goes above highest f-stop
                av96setpoint = av96max                                 -- clamp at highest f-stop
                tv96setpoint = bv96meter + sv96setpoint - av96setpoint -- recalculate shutter speed needed and hope for the best
            end
        end
    end
end

-- calculate exposure for cams with both adjustable iris and ND filter
function exposure_both()
    insert_ND_filter = false                                           -- NOTE : assume ND filter never used automatically by Canon firmware
    basic_iris_calc()
    if (tv96setpoint > tv96max ) then                                  -- check if shutter speed now too fast
        insert_ND_filter = true                                        -- flag the ND filter to be inserted
        bv96meter = bv96meter - nd96offset                             -- adjust meter for ND offset
        basic_iris_calc()                                              -- start over, but with new meter value
        bv96meter = bv96meter + nd96offset                             -- restore meter for later logging
    end
end


-- wait for a CHDK function to be true/false with a timeout
function wait_timeout(func , state, interval, delay, msg)
    local timestamp = get_tick_count()
    local timeout = false
    repeat
        sleep(delay)
        -- update_sync_led(6)
        timeout = get_tick_count() > timestamp + interval
    until (func() == state ) or timeout
    if timeout and (msg ~= nil) then printf(msg) end
    return timeout
end

-- set focus at infinity if requested (maybe redundant for AFL & MF mode but makes sure it's set right)
if (focus_at_infinity == true) then
    set_focus(infx)
    sleep(100)
end

set_prop(props.FLASH_MODE, 2)                                  -- disable built-in flash
set_prop(props.AF_ASSIST_BEAM,0)                               -- AF assist off if supported for this camera

-- check exposure if not taking bracketing shots
bracket_offset = 0
press("shoot_half")
wait_timeout(get_shooting, true, 2000, 50, "Warning : unable to focus / set exposure")
bv96raw=get_bv96()                              -- get meter reading values
tv96meter=get_tv96()
av96meter=get_av96()
sv96meter=get_sv96()

bv96meter=bv96raw-ec96adjust+bracket_offset         -- add in exposure compensation & bracketing offset

-- set minimum Av to larger of user input or current minimum for zoom setting
av96min= math.max(av96minimum, get_prop(props.MIN_AV))
if (av96target < av96min) then av96target = av96min end

-- calculate required setting for current ambient light conditions

exposure_both()


-- set up all exposure overrides
set_tv96_direct(tv96setpoint)
set_sv96(sv96setpoint)
if( av96setpoint ~= nil) then set_av96_direct(av96setpoint) end

if (insert_ND_filter == true) then         -- ND filter available and needed?
    set_nd_filter(1)                                        -- activate the ND filter
    nd_string="NDin"
else
    set_nd_filter(2)                                        -- make sure the ND filter does not activate
    nd_string="NDout"
end

print("Tv ", tv96setpoint)
-- shoot !!
-- ecnt=get_exp_count()
-- hook_shoot.set(10000)                                           -- set the hook just before shutter release for timing
press('shoot_full')                                             -- and finally shoot the image
-- wait_timeout(hook_shoot.is_ready, true, 2000, 10, "timeout on hook_shoot.is_ready")  -- wait until the hook is reached
return "Abs!!"