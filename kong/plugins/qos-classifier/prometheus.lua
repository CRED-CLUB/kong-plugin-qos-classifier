local _M = {}

local kong = kong
local prometheus_exp = require 'kong.plugins.prometheus.exporter'

function _M.get_prometheus_if_available()
    
    local ok 
    local prometheus
    local prometheus_metrics = {}

    -- Import prometheus if it is availaible
    ok, prometheus = pcall(prometheus_exp.get_prometheus,{})

    if not ok then 
        kong.log.warn("Failed to import Prometheus. Make sure you are using Kong > 2.6.0", prometheus)
        prometheus = nil
    else 
        prometheus_metrics.rps = prometheus:gauge("qos_requests_per_second",
                                                    "Incoming requests per second",
                                                    {"class", "route","service"})
        prometheus_metrics.threshold = prometheus:gauge("qos_request_threshold",
                                                    "Threshold for QoS class differentiation",
                                                    {"class", "route","service"})
    end
    return prometheus, prometheus_metrics
end


return _M