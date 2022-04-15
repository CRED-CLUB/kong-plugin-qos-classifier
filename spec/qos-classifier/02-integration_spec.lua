local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "qos-classifier"

local config = {
    termination = { 
        status_code = 302,
        header_name= "Location",
        header_value="https://cred.club"
    },
    upstream_header_name = "X-QOS-CLASS",
    node_count = {
        http_timeout_in_ms = 15,
        update_initial_delay_in_sec = 5,
        initial = 1,
        update_frequency_in_sec = 1
    },
    classes = {
        class_1 = {
            threshold = 1,
            header_value = "Green"
        },
        class_2 = {
            threshold = 3,
            header_value = "Orange"
        },
        class_3 = {
            threshold = 6,
            header_value = "Red"
        }
    }
}

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (integration) [#" .. strategy .. "]", function()
    local proxy_client, admin_client
    local bp, db
  
    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })
      local service = bp.services:insert()

      local route1 = bp.routes:insert {
        hosts   = {  "test1.com" },
        service = service,
      }

      -- Enable Plugin on Service Level
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        config = config
      })

      -- Start kong
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "/kong-plugin/spec/fixtures/custom_nginx.template",
        plugins = "bundled, " .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
      assert(db:truncate())
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
      if admin_client then admin_client:close() end
    end)
  
    it("Check header using /get endpoint", function()
      local res = proxy_client:get("/get", {
        headers = { Host = "test1.com" },
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.are.same("Green", json.headers["x-qos-class"])
    end)
end)
end