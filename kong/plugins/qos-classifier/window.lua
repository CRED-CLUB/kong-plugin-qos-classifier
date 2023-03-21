local config = require 'kong.plugins.qos-classifier.config'
local async_counter_lib = require 'kong.plugins.qos-classifier.counter'
local math = require 'math'

local kong = kong
local ngx_now = ngx.now

local function cache_key(scope, time) return scope .. ":" .. time end

local _M = {}
local mt = {__index = _M}

function _M.init()
  if ngx.get_phase() ~= 'init' and ngx.get_phase() ~= 'init_worker' and
    ngx.get_phase() ~= 'timer' then
    error('init can only be called from ' ..
            'init_by_lua_block, init_worker_by_lua_block or timer', 2)
  end
  local self = setmetatable({}, mt)

  if ngx.get_phase() == 'init_worker' then self:init_worker(1) end

  return self
end

function _M:init_worker(sync_interval)
  if ngx.get_phase() ~= 'init_worker' then
    error('init_worker can only be called in ' .. 'init_worker_by_lua_block', 2)
  end

  if self._counter then
    ngx.log(ngx.WARN, 'init_worker() has been called twice. ' ..
              'Please do not explicitly call init_worker. ' ..
              'Instead, call init() in the init_worker_by_lua_block')
    return
  end

  local c, err = async_counter_lib.new(config.QOS_SHARED_DICT, sync_interval)
  if err ~= nil then kong.log.err("error in init counter: ", err) end

  self._counter = c

  return self
end

function _M:get_usage(plugin_conf, curr_time, scope)
  local rounded_off_time = math.floor(curr_time)

  -- it may take upto 1s for counters to sync, hence
  local key = cache_key(scope, rounded_off_time - 2)

  local value, err = self._counter:get(key)
  if not value or value == 0 then return 0 end

  if plugin_conf.strategy and plugin_conf.strategy == "blanket" then
    return value
  end

  return ((curr_time - rounded_off_time) * value)
end

function _M:incr(curr_time, scope)
  local rounded_off_time = math.floor(curr_time)

  local key = cache_key(scope, rounded_off_time)

  local ok = self._counter:incr(key, 1)
end

return _M
