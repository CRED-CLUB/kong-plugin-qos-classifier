local config = require 'kong.plugins.qos-classifier.config'
local access = require 'kong.plugins.qos-classifier.access'
local BasePlugin = require 'kong.plugins.base_plugin'
local nodes_updater = require 'kong.plugins.qos-classifier.nodes_updater'
local window = require 'kong.plugins.qos-classifier.window'

local QOSClassifierHandler = BasePlugin:extend()

window.init()

QOSClassifierHandler.VERSION = "0.1.0"
QOSClassifierHandler.PRIORITY = 899 -- run this plugin immediately after the rate limiting plugins

function QOSClassifierHandler:new()
  QOSClassifierHandler.super.new(self, "qos-classifier-plugin")
end

function QOSClassifierHandler:init_worker()
  QOSClassifierHandler.super.init_worker(self)

  window:init_worker(config.COUNTER_SYNC_INTERVAL)
end

function QOSClassifierHandler:access(config)
  -- try getting the number of kong nodes in the cluster
  local num_nodes = nodes_updater.try_fetch(config.node_count.initial,
                                            config.node_count.update_url,
                                            config.node_count.http_timeout_in_ms,
                                            config.node_count
                                              .update_frequency_in_sec,
                                            config.node_count
                                              .update_initial_delay_in_sec)

  access.execute(config, num_nodes)
end

function QOSClassifierHandler:response(config)
  if config.send_header_in_response_to_client then
    kong.response.set_header(config.upstream_header_name,
                             kong.ctx.plugin.qos_value)
  end
end

return QOSClassifierHandler
