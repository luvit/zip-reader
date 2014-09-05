local loadZip = require('zip')
local await = require('await')
local uv = require('luv')

local function tobin(bin)
  local str = '<'
  for i=1,#bin do
    str = str .. bit.tohex(string.byte(bin, i),2) .. " "
  end
  str = str .. '>'
  return str
end

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
