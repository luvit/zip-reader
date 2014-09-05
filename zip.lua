local ffi = require('ffi')
local Zlib = require('zlib_native')

local function tobin(bin)
  local str = '<'
  for i=1,#bin do
    str = str .. bit.tohex(string.byte(bin, i),2) .. " "
  end
  str = str .. '>'
  return str
end

-- Given a path like /foo/bar and foo//bar/ return foo/bar.bar
-- This removes leading and trailing slashes as well as multiple internal slashes.
local function normalizePath(path)
  local parts = {}
  for part in string.gmatch(path, "([^/]+)") do
    table.insert(parts, part)
  end
  return table.concat(parts, "/")
end

ffi.cdef[[
  struct zip_EOCD {
    uint32_t signature;
    uint16_t disk_number;
    uint16_t central_dir_disk_number;
    uint16_t central_dir_disk_records;
    uint16_t central_dir_total_records;
    uint32_t central_dir_size;
    uint32_t central_dir_offset;
    uint16_t file_comment_length;
  } __attribute__ ((packed));
]]
local EOCD = ffi.typeof("struct zip_EOCD")

ffi.cdef[[
  struct zip_CDFH {
    uint32_t signature;
    uint16_t version;
    uint16_t version_needed;
    uint16_t flags;
    uint16_t compression_method;
    uint16_t last_mod_file_time;
    uint16_t last_mod_file_date;
    uint32_t crc_32;
    uint32_t compressed_size;
    uint32_t uncompressed_size;
    uint16_t file_name_length;
    uint16_t extra_field_length;
    uint16_t file_comment_length;
    uint16_t disk_number;
    uint16_t internal_file_attributes;
    uint32_t external_file_attributes;
    uint32_t local_file_header_offset;
  } __attribute__ ((packed));
]]
local CDFH = ffi.typeof("struct zip_CDFH")

ffi.cdef[[
  struct zip_LFH {
    uint32_t signature;
    uint16_t version_needed;
    uint16_t flags;
    uint16_t compression_method;
    uint16_t last_mod_file_time;
    uint16_t last_mod_file_date;
    uint32_t crc_32;
    uint32_t compressed_size;
    uint32_t uncompressed_size;
    uint16_t file_name_length;
    uint16_t extra_field_length;
  } __attribute ((packed));
]]
local LFH = ffi.typeof("struct zip_LFH")




-- Please provide with I/O functions.
-- fsFstat(fd) takes a fd and returns a table with a .size property for file length
-- fs.read(fd, length, offset) reads from a file at offset and for a set number of bytes
--  return a string of all data
return function (fd, fs)

  local cd = {}

  -- Scan from the end of a file to find the start position of
  -- the EOCD (end of central directory) entry.
  local function findEOCD()
    local stat = fs.fstat(fd)

    -- Theoretically, the comment at the end can be 0x10000 bytes long
    -- though there is no sense reading more than that.
    local maxSize = 391 + 22
    local start = stat.size - maxSize
    local tail = fs.read(fd, maxSize, start)
    local position = #tail

    -- Scan backwards looking for the EOCD signature 0x06054b50
    while position > 0 do
      if string.byte(tail, position) == 0x06 and
         string.byte(tail, position - 1) == 0x05 and
         string.byte(tail, position - 2) == 0x4b and
         string.byte(tail, position - 3) == 0x50 then
        return start + position - 4
      end
      position = position - 1
    end
    error "Not a zip file"
  end

  -- Once you know the EOCD position, you can read and parse it.
  local function readEOCD(position)
    local eocd = EOCD()
    local size = ffi.sizeof(eocd)
    local data = fs.read(fd, size, position)

    ffi.copy(eocd, data, size)

    if eocd.signature ~= 0x06054b50 then
      error "Invalid EOCD position"
    end
    local comment = fs.read(fd, eocd.file_comment_length, position + size)

    return {
      disk_number = eocd.disk_number,
      central_dir_disk_number = eocd.central_dir_disk_number,
      central_dir_disk_records = eocd.central_dir_disk_records,
      central_dir_total_records = eocd.central_dir_total_records,
      central_dir_size = eocd.central_dir_size,
      central_dir_offset = eocd.central_dir_offset,
      file_comment = comment,
    }
  end

  local function readCDFH(position, start)
    local cdfh = CDFH()
    local size = ffi.sizeof(cdfh)
    local data = fs.read(fd, size, position)

    ffi.copy(cdfh, data, size)
    if cdfh.signature ~= 0x02014b50 then
      error "Invalid CDFH position"
    end
    local n, m, k = cdfh.file_name_length, cdfh.extra_field_length, cdfh.file_comment_length
    local more = fs.read(fd, n + m + k, position + size)

    return {
      version = cdfh.version,
      version_needed = cdfh.version_needed,
      flags = cdfh.flags,
      compression_method = cdfh.compression_method,
      last_mod_file_time = cdfh.last_mod_file_time,
      last_mod_file_date = cdfh.last_mod_file_date,
      crc_32 = cdfh.crc_32,
      compressed_size = cdfh.compressed_size,
      uncompressed_size = cdfh.uncompressed_size,
      file_name = string.sub(more, 1, n),
      -- extra_field = string.sub(more, n + 1, n + m),
      comment = string.sub(more, n + m + 1),
      disk_number = cdfh.disk_number,
      internal_file_attributes = cdfh.internal_file_attributes,
      external_file_attributes = cdfh.external_file_attributes,
      local_file_header_offset = cdfh.local_file_header_offset,
      local_file_header_position = cdfh.local_file_header_offset + start,
      header_size = size + n + m + k
    }
  end

  local function readLFH(position)
    local lfh = LFH()
    local size = ffi.sizeof(lfh)
    local data = fs.read(fd, size, position)

    ffi.copy(lfh, data, size)
    if lfh.signature ~= 0x04034b50 then
      error "Invalid LFH position"
    end
    local n, m = lfh.file_name_length, lfh.extra_field_length
    local more = fs.read(fd, n + m, position + size)

    return {
      version_needed = lfh.version_needed,
      flags = lfh.flags,
      compression_method = lfh.compression_method,
      last_mod_file_time = lfh.last_mod_file_time,
      last_mod_file_date = lfh.last_mod_file_date,
      crc_32 = lfh.crc_32,
      compressed_size = lfh.compressed_size,
      uncompressed_size = lfh.uncompressed_size,
      file_name = string.sub(more, 1, n),
      -- extra_field = string.sub(more, n + 1, n + m),
      header_size = size + n + m,
    }
  end

  local function stat(path)
    path = normalizePath(path)
    local entry = cd[path]
    if entry then return entry end
    error("No such entry '" .. path .. "'")
  end

  local function readdir(path)
    path = normalizePath(path)
    local entries = {}
    local pattern
    if #path > 0 then
      pattern = "^" .. path .. "/([^/]+)$"
    else
      pattern = "^([^/]+)$"
    end
    for name, entry in pairs(cd) do
      local a, b, match = string.find(name, pattern)
      if match then
        entries[match] = entry
      end
    end
    return entries
  end

  local function readfile(path)
    path = normalizePath(path)
    local entry = cd[path]
    if entry == nil then error("No such file '" .. path .. "'") end
    local lfh = readLFH(entry.local_file_header_position)

    if entry.crc_32 ~= lfh.crc_32 or
       entry.file_name ~= lfh.file_name or
       entry.compression_method ~= lfh.compression_method or
       entry.compressed_size ~= lfh.compressed_size or
       entry.uncompressed_size ~= lfh.uncompressed_size then
      error "Local file header doesn't match entry in central directory"
    end
    p(lfh)
    local start = entry.local_file_header_position + lfh.header_size
    local compressed = fs.read(fd, lfh.compressed_size, start)
    if #compressed ~= entry.compressed_size then
      error "compressed size mismatch"
    end

    local uncompressed
    -- Store
    if lfh.compression_method == 0 then
      uncompressed = compressed
    -- Inflate
    elseif lfh.compression_method == 8 then
      uncompressed = assert(Zlib.new('inflate',-15):write(compressed, 'finish'))
    else
      error("Unknown compression method: " .. lfh.compression_method)
    end
    if #uncompressed ~= lfh.uncompressed_size then
      error "uncompressed size mismatch"
    end
    return uncompressed
  end

  local function load()
    local position = findEOCD()
    local eocd = readEOCD(position)
    position = position - eocd.central_dir_size
    local start = position - eocd.central_dir_offset
    for i = 1, eocd.central_dir_disk_records do
      local cdfh = readCDFH(position, start)
      cd[normalizePath(cdfh.file_name)] = cdfh
      position = position + cdfh.header_size
    end

  end

  load()

  return {
    stat = stat,
    readdir = readdir,
    readfile = readfile,
  }

end
