local typedefs = require "kong.db.schema.typedefs"

local request_class_record = {
  type = "record",
  fields = {{threshold = {type = "number", gt = 0}}, {header_value = {type = "string"}}}
}

local schema = {
  name = "qos-classifier",
  fields = {
    {consumer = typedefs.no_consumer}, {protocols = typedefs.protocols_http}, {
      config = {
        type = "record",
        fields = {
          {upstream_header_name = {type = "string", default = 'X-QOS-CLASS'}},
          {
            classes = {
              type = "record",
              fields = {
                {class_1 = request_class_record},
                {class_2 = request_class_record},
                {class_3 = request_class_record},
                {class_4 = request_class_record}
              }
            }
          }, {
            termination = {
              type = "record",
              fields = {
                {header_name = typedefs.header_name},
                {header_value = {type = "string"}},
                {
                  status_code = {
                    type = "integer",
                    default = 429,
                    between = {100, 599}
                  }
                }
              }
            }
          }, {
            node_count = {
              type = "record",
              fields = {
                {initial = {type = "integer", required = true}},
                {update_url = typedefs.url},
                {
                  http_timeout_in_ms = {
                    type = "integer",
                    required = true,
                    gt = 0,
                    default = 10
                  }
                },
                {
                  update_frequency_in_sec = {
                    type = "integer",
                    required = true,
                    gt = 0,
                    default = 1
                  }
                }, {
                  update_initial_delay_in_sec = {
                    type = "integer",
                    required = true,
                    gt = 0,
                    default = 15
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

return schema
