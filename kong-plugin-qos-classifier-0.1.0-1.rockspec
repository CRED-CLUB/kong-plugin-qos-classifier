package = "kong-plugin-qos-classifier" 
version = "0.1.0-1"
-- The version '0.1.0' is the source code version, the trailing '1' is the version of this rockspec.
-- whenever the source version changes, the rockspec should be reset to 1. The rockspec version is only
-- updated (incremented) when this file changes, but the source remains the same.
supported_platforms = {"linux", "macosx"}

source = {
  url = "http://github.com/Kong/kong-plugin.git",
  tag = "0.1.0"
}

description = {
  summary = "Plugin to classify requests based on the rps received",
  homepage = "http://getkong.org",
  license = "Apache 2.0"
}

dependencies = {
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.qos-classifier.handler"] = "kong/plugins/qos-classifier/handler.lua",
    ["kong.plugins.qos-classifier.schema"] = "kong/plugins/qos-classifier/schema.lua",
    ["kong.plugins.qos-classifier.access"] = "kong/plugins/qos-classifier/access.lua",
    ["kong.plugins.qos-classifier.config"] = "kong/plugins/qos-classifier/config.lua",
    ["kong.plugins.qos-classifier.counter"] = "kong/plugins/qos-classifier/counter.lua",
    ["kong.plugins.qos-classifier.window"] = "kong/plugins/qos-classifier/window.lua",
    ["kong.plugins.qos-classifier.nodes_updater"] = "kong/plugins/qos-classifier/nodes_updater.lua",
    ["kong.plugins.qos-classifier.prometheus"] = "kong/plugins/qos-classifier/prometheus.lua",
  }
}
