# kong-plugin-qos-classifier
`kong-plugin-qos-classifier` does the following

- Categorizes the requests into various classes based on the req/s threshold defined.
- Sends custom value of a predefined header to the upstream service based on the class identified, based on which the upstream service can implement degraded scenarios and flows.
- Supports terminating the requests after breaching the highest threshold with custom status code.
- Also supports sending custom header to clients when a request is terminated. Eg, sending a `Location` header with a static CDN URL and `302` status code.
- The classification of requests happen locally in a kong node without any dependency on any central datastore, which makes it performant.
- At the same time, an endpoint (like that of `kong-plugin-cluster-stats`) could be configured to dynamically update the calculation based on the current number of kong nodes in the cluster.
- The calculation for identifying the class of requests is based on the `sliding_window` algorithm.

## Installation and Loading the plugin

Follow [standard procedure](https://docs.konghq.com/gateway-oss/2.0.x/plugin-development/distribution/) to install and load the plugin.

This plugin also requires the following `shared_dict`s to be defined in nginx configuration. The following is the kong configuration for the same:

```
nginx_http_lua_shared_dict = qos_shared 12m; lua_shared_dict qos_lock 100k
```

## Enabling the plugin

The plugin can be enabled at `service`, `route` or `global` levels. In case of multiple instances of plugins enabled for a request, evaluation only happens for the highest level. The order of precedence is (starting from the highest level):

- `route`
- `service`
- `global`
 
## Configuring the plugin

The plugin has the following configuraion object:
```
{
  "config": {
    "termination": {
      "status_code": 302,
      "header_name": "Location",
      "header_value": "https://cred.club"
    },
    "upstream_header_name": "X-QOS-CLASS",
    "node_count": {
      "http_timeout_in_ms": 15,
      "update_initial_delay_in_sec": 5,
      "update_url": "http://localhost:8001/cluster-stats",
      "initial": 2,
      "update_frequency_in_sec": 1
    },
    "classes": {
      "class_1": {
        "threshold": 4,
        "header_value": "green"
      },
      "class_2": {
        "threshold": 6,
        "header_value": "red"
      },
      "class_3": {
        "threshold": null,
        "header_value": null
      },
      "class_4": {
        "threshold": null,
        "header_value": null
      }
    }
  }
}
```

The configuration parameters details are given below:

- `upstream_header_name`: HTTP header to be sent to upstream services carying the class of the request.
- `classes.class_1.threshold`: Threshold in req/s for 1st class of requests.
- `classes.class_1.header_value`: Value of the header identified by `upstream_header_name` when the requests is within `classes.class_1.threshold`.
- `node_count.initial`: Initial number of kong nodes.
- `termination.status_code`: HTTP status code to send when the threshold of the highest class is crossed.
- `termination.header_name`: HTTP header to send when the request is terminated.
- `termination.header_value`: Value of the above header to be sent.
- `node_count.update_url`: HTTP endpoint to hit to get updated number of nodes. The response should have `"num_nodes"` json field.
- `node_count.http_timeout_in_ms`: HTTP timeout in ms for the above endpoint.
- `node_count.update_frequency_in_sec`: Interval at which to update the node count.
- `node_count.update_initial_delay_in_sec`: Number of seconds to wait before initiating node update calls. This is to make sure that the cluster stabalises before making these calls, eg in case of a rolling deployment of the cluster. Till this time, the configured `node_count.initial` is used for the calculation.
