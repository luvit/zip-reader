local ffi = require('ffi')
local uv = require('luv')
local await = require('await')
local Zlib = require("zlib_native")

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

-- Scan from the end of a file to find the start position of
-- the EOCD (end of central directory) entry.
local function findEOCD(fd)
  local stat, err = await(uv.fs_fstat, fd)
  if stat == nil then return nil, err end


  -- Theoretically, the comment at the end can be 0x10000 bytes long
  -- though there is no sense reading more than that.
  local maxSize = 391 + 22
  local start = stat.size - maxSize
  local tail = await(uv.fs_read, fd, maxSize, start);
  if tail == nil then return nil, err end
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
  return nil, "Not a zip file"
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

-- Once you know the EOCD position, you can read and parse it.
local function readEOCD(fd, position)
  local eocd = EOCD()
  local size = ffi.sizeof(eocd)
  local data, err = await(uv.fs_read, fd, size, position)
  if data == nil then return nil, err end

  ffi.copy(eocd, data, size)
  if eocd.signature ~= 0x06054b50 then
    return nil, "Invalid EOCD position"
  end
  local comment, err = await(uv.fs_read, fd, eocd.file_comment_length, position + size)
  if comment == nil then return nil, err end

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

local function readCDFH(fd, position, start)
  local cdfh = CDFH()
  local size = ffi.sizeof(cdfh)
  local data, err = await(uv.fs_read, fd, size, position)
  if data == nil then return nil, err end

  ffi.copy(cdfh, data, size)
  if cdfh.signature ~= 0x02014b50 then
    return nil, "Invalid CDFH position"
  end
  local n, m, k = cdfh.file_name_length, cdfh.extra_field_length, cdfh.file_comment_length
  local more, err = await(uv.fs_read, fd, n + m + k, position + size)
  if more == nil then return nil, err end

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

local function readLFH(fd, position)
  local lfh = LFH()
  local size = ffi.sizeof(lfh)
  local data, err = await(uv.fs_read, fd, size, position)
  if data == nil then return nil, err end
  ffi.copy(lfh, data, size)
  if lfh.signature ~= 0x04034b50 then
    return nil, "Invalid LFH position"
  end
  local n, m = lfh.file_name_length, lfh.extra_field_length
  local more, err = await(uv.fs_read, fd, n + m, position + size)
  if more == nil then return nil, err end
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

local function stat(fd, cd, path)
  local entry = cd[path]
  if entry then return entry end
  return nil, "No such entry '" .. path .. "'"
end

local function readdir(fd, cd, path)
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

local function readfile(fd, cd, path)
  local entry = cd[path]
  if entry == nil then return nil, "No such file '" .. path .. "'" end
  local lfh, err = readLFH(fd, entry.local_file_header_position)
  if lfh == nil then return nil, err end
  if entry.crc_32 ~= lfh.crc_32 or
     entry.file_name ~= lfh.file_name or
     entry.compression_method ~= lfh.compression_method or
     entry.compressed_size ~= lfh.compressed_size or
     entry.uncompressed_size ~= lfh.uncompressed_size then
    return nil, "Local file header doesn't match entry in central directory"
  end
  p(lfh)
  local start = entry.local_file_header_position + lfh.header_size
  local compressed, err = await(uv.fs_read, fd, lfh.compressed_size, start)
  if #compressed ~= entry.compressed_size then
    return nil, "compressed size mismatch"
  end

  local uncompresed
  -- Store
  if lfh.compression_method == 0 then
    uncompressed = compressed
  -- Inflate
  elseif lfh.compression_method == 8 then
    local err
    uncompressed, err = Zlib.new('inflate'):write(compressed, 'finish')
    if uncompressed == nil then return nil, err end
  else
    return nil, "Unknown compression method: " .. lfh.compression_method
  end
  if #uncompressed ~= lfh.uncompressed_size then
    return nil, "uncompressed size mismatch"
  end
  return uncompressed
end

local function load(fd)
  local position, err = findEOCD(fd)
  if position == nil then return nil, err end
  local eocd, err = readEOCD(fd, position)
  if eocd == nil then return nil, err end
  local cd = {}
  position = position - eocd.central_dir_size
  local start = position - eocd.central_dir_offset
  for i = 1, eocd.central_dir_disk_records do
    local cdfh, err = assert(readCDFH(fd, position, start))
    if cdfh == nil then return nil, err end
    cd[normalizePath(cdfh.file_name)] = cdfh
    position = position + cdfh.header_size
  end

  return {
    stat = function(path)
      return stat(fd, cd, normalizePath(path))
    end,
    readdir = function (path)
      return readdir(fd, cd, normalizePath(path))
    end,
    readfile = function (path)
      return readfile(fd, cd, normalizePath(path))
    end,
  }
end

return load
