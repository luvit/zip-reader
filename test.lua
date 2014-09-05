local openZip = require('zip')
local fs = require('./sync-fs')

-- To test, run the Makefile in the current directory. It will zip the modules
-- folder and combine that with the luvit binary in your path.

-- Once this is done, run this script with `./combined test.lua`

local fd = fs.open(process.execPath, "r", tonumber("644", 8))
p{fd=fd}

local function test(zip)
  if zip == nil then
    print("No embedded zip file found")
    return
  end
  local file = zip.readfile("zip.lua")
  if not file then
    file = zip.readfile("zip/init.lua")
  end
  p{zip=file}
end

-- blocking I/O.
test(openZip(fd, fs))

coroutine.wrap(function ()
  -- Pseudo-blocking.  Only blocks the coroutine, but not the process.
  test(openZip(fd, require('./async-fs')))
end)()
