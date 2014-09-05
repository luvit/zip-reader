local uv = require('uv_native')

return {
  open = uv.fsOpen,
  fstat = uv.fsFstat,
  read = function (fd, length, offset)
    return uv.fsRead(fd, offset, length)
  end
}
