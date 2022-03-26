local _M = {}

local kong = kong
local ngx_now = ngx.now
local qos_shm = ngx.shared.qos_shared
local json = require "cjson"
local httpc = require "resty.http"
local resty_lock = require "resty.lock"
local config = require 'kong.plugins.qos-classifier.config'

local NODE_COUNT_LAST_UPDATED_AT = "NODE_COUNT_LAST_UPDATED_AT"
local LAST_NODE_COUNT = "LAST_NODE_COUNT"
local NODE_INIT_TIME = "NODE_INIT_TIME"
local NODE_UPDATE_LOCK = "NODE_UPDATE_LOCK"

local function isempty(s) return s == nil or s == '' end

local function handle_response(response_code, response_body)
  if response_code ~= 200 then
    kong.log.err("received non 200 response code: ", response_code)
    return 0, false
  end

  local r, err = json.decode(response_body)
  if err then
    kong.log.err("unable to parse response body: ", err)
    return 0, false
  end

  return r.num_nodes, true
end

local function http_request(url, timeout)
  local client = httpc.new()
  client:set_timeout(timeout)
  kong.log.notice("making http request")
  local res, err = client:request_uri(url, {
    method = "GET",
    headers = {["Content-Type"] = "application/json"}
  })
  if not res then
    kong.log.err("http request failed ", err)
    return 0, false
  end
  return handle_response(res.status, res.body)
end

local function fetch(url, timeout) return http_request(url, timeout) end

local function local_fetch()
  local curr_node_count, _ = qos_shm:get(LAST_NODE_COUNT)

  -- if due to some reason, fetch from shm fails,
  -- return nil
  if curr_node_count == nil then
    kong.log.err("error in getting current node count")
    return nil
  end

  return curr_node_count
end

local function wait_for_initial_delay(curr_time, initial_delay)
  local init_time, _ = qos_shm:get(NODE_INIT_TIME)
  if init_time == nil then
    local ok, err, _ = qos_shm:set(NODE_INIT_TIME, curr_time)
    if err then kong.log.err("error in setting node init time: ", err) end
    init_time = curr_time
  end

  if curr_time > init_time + initial_delay then return false end

  return true
end

-- tries to fetch the current count of kong nodes in the clusters
-- and returns the number of nodes
function _M.try_fetch(initial_count, url, timeout, frequency, initial_delay)
  local now = ngx_now()

  -- return the configured count of nodes if the URL is not set
  -- or the initial delay period has not expired
  if isempty(url) or wait_for_initial_delay(now, initial_delay) then
    return initial_count
  end

  -- get the time when the node count was last updated and compare 
  -- if the current time is past the defined frequency in secs
  local last_updated_at, _ = qos_shm:get(NODE_COUNT_LAST_UPDATED_AT)

  if last_updated_at and now <= last_updated_at + frequency then
    -- if the current time is still below the frequency
    -- fetch the count from shm to return
    return local_fetch() or initial_count
  end

  -- prepare lock opts
  -- set exptime as http timeout + 10ms
  -- set timeout i.e as 0, ie 0 wait to acquire lock
  local opts = {}
  opts["exptime"] = (timeout + 10) / 1000
  opts["timeout"] = 0

  local lock, err = resty_lock:new(config.QOS_SHARED_LOCK, opts)
  if not lock then
    kong.log.err("failed to create lock: ", err)
    return local_fetch() or initial_count
  end

  -- try acquire lock
  local elapsed, err = lock:lock(NODE_UPDATE_LOCK)
  if err then return local_fetch() or initial_count end

  -- check again if any other thread has uodated the node count
  last_updated_at, _ = qos_shm:get(NODE_COUNT_LAST_UPDATED_AT)
  if last_updated_at and now <= last_updated_at + frequency then
    local ok, err = lock:unlock()
    if not ok then kong.log.err("failed to unlock: ", err) end
    return local_fetch() or initial_count
  end

  -- fetch the node count
  local num_nodes, _ = fetch(url, timeout)

  -- if the number of nodes fetched is 0, then
  -- an error had occured, return the last node count
  if not num_nodes or num_nodes == 0 then
    local ok, err = lock:unlock()
    if not ok then kong.log.err("failed to unlock: ", err) end
    return local_fetch() or initial_count
  end

  -- node count just got updated, update the key in shm
  local ok, err, _ = qos_shm:set(NODE_COUNT_LAST_UPDATED_AT, now)
  if err then
    kong.log.err("error in setting node count last updated at: ", err)
  end

  -- also update the current count of nodes
  local ok, err, _ = qos_shm:set(LAST_NODE_COUNT, num_nodes)
  if err then kong.log.err("error in setting last node count: ", err) end

  local ok, err = lock:unlock()
  if not ok then kong.log.err("failed to unlock: ", err) end

  return num_nodes
end

return _M