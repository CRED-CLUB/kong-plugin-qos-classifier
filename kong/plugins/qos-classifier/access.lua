local _M = {}

local kong = kong
local set_header = kong.service.request.set_header

local window = require 'kong.plugins.qos-classifier.window'
-- Prometheus is imported and used if availaible in the current version
local prometheus_importer = require 'kong.plugins.qos-classifier.prometheus'
local prometheus, prometheus_metrics =
  prometheus_importer.get_prometheus_if_available()

-- computes the class of the request and returns the appropriate header
-- value along with a boolean field to indicate if the request should
-- be throttled, once all limits are breached
local function get_class(class_conf, value, num_nodes)
  -- since tables are unordered in lua, iterate by ordered list of classes
  local class_index = {"class_1", "class_2", "class_3", "class_4"}
  for _, class_name in pairs(class_index) do
    local class_attrs = class_conf[class_name]
    if class_attrs.threshold and class_attrs.header_value then
      if value <= (class_attrs.threshold / num_nodes) then
        return class_attrs.header_value, false, class_attrs.threshold
      end
    end
  end
  return "", true, -1
end

local function get_scope(plugin_conf)
  -- fetch information about service and router from the router 
  local service = kong.router.get_service()
  local route = kong.router.get_route()

  local service_id = service.name or service.id
  local route_id = route.name or route.id

  local scope = (plugin_conf.service_id or plugin_conf.route_id) or 'global'

  return scope, service_id, route_id
end

function _M.execute(plugin_conf, num_nodes)
  -- find the scope at which the plugin is enabled
  -- if service id or route id is nil, then the plugin is applied globally
  local scope, service_id, route_id = get_scope(plugin_conf)
  local curr_time = ngx.now()

  -- get the weighted request count in the window
  local req_count = window:get_usage(curr_time, scope)

  -- get the value of the header as defined for this class of request
  -- also check if the request breaches all limits and should be throttled
  local header_value, should_terminate, class_threshold = get_class(
                                                            plugin_conf.classes,
                                                            req_count, num_nodes)

  -- Set prometheus metrics 
  if prometheus then
    prometheus_metrics.total_requests:inc(1,
                                          {header_value, route_id, service_id})
    prometheus_metrics.threshold:set(class_threshold,
                                     {header_value, route_id, service_id})
  end

  -- Check rate_limiting state 
  if should_terminate then
    if plugin_conf.termination.header_name and
      plugin_conf.termination.header_value then
      -- set termination header with value
      kong.response.set_header(plugin_conf.termination.header_name,
                               plugin_conf.termination.header_value)
    end
    -- exit with termination status code
    kong.response.exit(plugin_conf.termination.status_code)
  end

  -- increment the counter
  window:incr(curr_time, scope)
  -- the request is still under defined limits
  -- set the appropriate class in the header to be passed to the upstream
  set_header(plugin_conf.upstream_header_name, header_value)
end

return _M
