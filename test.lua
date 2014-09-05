local openZip = require('zip')
local fs = require('./sync-fs')

-- To test, run the Makefile in the current directory. It will zip the modules
-- folder and combine that with the luvit binary in your path.

-- Once this is done, run this script with `./combined test.lua`

local fd = fs.open(process.execPath, "r", tonumber("644", 8))
p{fd=fd}

local function test(zip)
  p{zip=zip}
  p{logo=zip.readfile("logo.txt")}
  p{test=zip.readfile("test.txt")}
  p{init=zip.readfile("zip/init.lua")}
end

test(openZip(fd, fs))

-- coroutine.wrap(function ()
--   test(openZip(fd, require('./async-fs')))
-- end)()
