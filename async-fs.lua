local uv = require('uv_native')
local await = require('await')

return {
  open = function (path, flags, mode)
    return await(uv.fsOpen, path, flags, mode)
  end,
  fstat = function (fd)
    return await(uv.fsFstat, fd)
  end,
  read = function (fd, length, offset)
    return await(uv.fsRead, fd, offset, length)
  end
}
