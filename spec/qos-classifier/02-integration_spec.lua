local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "qos-classifier"
local TERMINATE_HOST = "terminate.host"
local GREEN_HOST = "green.host"
local ORANGE_HOST = "orange.host"
local RED_HOST = "red.host"

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
  }
}

local function set_classes_with_thresholds(green, orange, red)
  classes = {
    class_1 = {
      threshold = green,
      header_value = "Green"
    },
    class_2 = {
      threshold = orange,
      header_value = "Orange"
    },
    class_3 = {
      threshold = red,
      header_value = "Red"
    }
  }
  return classes
end

local function make_requests_to_upstream(host, start_time)
  local client
  while true do
    client = helpers.proxy_client()
    assert(client:get("/get", {
      headers = { Host = host },
    }))
    
    -- Make requests to upstream in every 10 ms to avoid
    -- getting blocked by nginx for making infinite requests
    ngx.sleep(0.01)

    -- QoS Classifier Plugin returns header on the basis
    -- of requests received in the previous second. Previous
    -- second is a absolute window which starts as soon as
    -- kong node starts. i.e. Start time of kong node is T=0.
    -- Therefore, 1.2 seconds is used as a window to ensure
    -- that the upstream is hit in the complete window.
    if(ngx.now() - start_time > 1.2) then break end
  end
end

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (integration) [#" .. strategy .. "]", function()
    local bp, db
  
    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })
      local service = bp.services:insert()

      local route1 = bp.routes:insert {
        hosts   = { TERMINATE_HOST },
        service = service,
      }

      local route2 = bp.routes:insert {
        hosts   = { RED_HOST },
        service = service,
      }

      local route3 = bp.routes:insert {
        hosts   = { ORANGE_HOST },
        service = service,
      }

      local route4 = bp.routes:insert {
        hosts   = { GREEN_HOST },
        service = service,
      }

      -- Enable Plugin on to check termination
      config.classes = set_classes_with_thresholds(1,2,3)
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        route = route1,
        config = config 
      })

      -- Enable Plugin on to check header_value = Red
      config.classes = set_classes_with_thresholds(1,2,1000)
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        route = route2,
        config = config 
      })

      -- Enable Plugin on to check header_value = Orange
      config.classes = set_classes_with_thresholds(1,1000,1001)
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        route = route3,
        config = config 
      })

      -- Enable Plugin on to check header_value = Green
      config.classes = set_classes_with_thresholds(1000,1001,1002)
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        route = route4,
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

    it("Check for termination", function()
      local now = ngx.now()
      make_requests_to_upstream(TERMINATE_HOST, now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = TERMINATE_HOST },
      })
      assert.res_status(302, res)
    end)

    it("Check Red Header", function()
      local now = ngx.now()
      make_requests_to_upstream(RED_HOST, now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = RED_HOST },
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.are.same("Red", json.headers["x-qos-class"])
    end)

    it("Check Orange Header", function()
      local now = ngx.now()
      make_requests_to_upstream(ORANGE_HOST, now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = ORANGE_HOST },
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.are.same("Orange", json.headers["x-qos-class"])
  end)

    it("Check Green Header", function()
      local now = ngx.now()
      make_requests_to_upstream(GREEN_HOST, now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = GREEN_HOST },
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.are.same("Green", json.headers["x-qos-class"])
    end)

end)
end