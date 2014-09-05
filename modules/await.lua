
-- Call a luv async function from within a coroutine in a blocking manner.manner
-- eg: local fd = await(uv.fs_open, "path/to/file", "r", tonumber("644", 8))
local function await(fn, ...)
  if type(fn) ~= "function" then
    error "You must pass in the raw function as the first arg to await"
  end
  local co = coroutine.running()
  local args = {...}
  table.insert(args, function (err, ...)
    -- p(err, result)
    if err then return assert(coroutine.resume(co, nil, err)) end
    assert(coroutine.resume(co, ...))
  end)
  fn(unpack(args))
  return coroutine.yield()
end

return await
