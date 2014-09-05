local loadZip = require('zip')
local await = require('await')
local uv = require('luv')

-- To test, run the Makefile in the current directory. It will zip the modules
-- folder and combine that with the luvit binary in your path.

-- Oh, and the luv.luvit module in this repo is compiled for a macbook, you may
-- need to replace it if your arch differs.  Or I can use luvit's builtin libuv
-- bindings instead of depending on the external luv addon.

-- Once this is done, run this script with `./combined test.lua`

coroutine.wrap(function ()
  local fd = await(uv.fs_open, uv.execpath(), "r", tonumber("644", 8))
  local zip = assert(loadZip(fd))
  -- p(zip)
  -- p(assert(zip.stat("zip")))
  -- p(assert(zip.readdir("/")))
  -- p(assert(zip.readdir("zip")))
  p(assert(zip.readfile("logo.txt")))
  p(assert(zip.readfile("test.txt")))
  p(assert(zip.readfile("zip/init.lua")))

end)()
