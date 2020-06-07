--[[
 Copyright (C) 2019 <reyalp (at) gmail dot com>

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
--]]
--[[
utilities for measuring time intervals
]]

local ticktime={}
-- backward compatible with old binaries
if type(sys.gettick) == 'function' then
	ticktime.get = sys.gettick
else
	function ticktime.get()
		local sec, usec = sys.gettimeofday()
		return sec + usec/1000000
	end
end

function ticktime.elapsed(t)
	return ticktime.get()-t
end

function ticktime.elapsedms(t)
	return (ticktime.get()-t)*1000
end

return ticktime
