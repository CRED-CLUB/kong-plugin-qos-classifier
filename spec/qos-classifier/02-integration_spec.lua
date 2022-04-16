local helpers = require "spec.helpers"
local cjson = require "cjson"

local PLUGIN_NAME = "qos-classifier"
local MAX_REQUESTS = 25

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

local function make_class(green, orange, red)
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
    ngx.sleep(0.01)
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
        hosts   = {  "test1.com" },
        service = service,
      }

      local route2 = bp.routes:insert {
        hosts   = {  "test2.com" },
        service = service,
      }

      local route3 = bp.routes:insert {
        hosts   = {  "test3.com" },
        service = service,
      }

      local route4 = bp.routes:insert {
        hosts   = {  "test4.com" },
        service = service,
      }

      -- Enable Plugin on to check termination
      config.classes = make_class(1,2,3)
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        route = route1,
        config = config 
      })

      -- Enable Plugin on to check header_value = Red
      config.classes = make_class(1,2,1000)
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        route = route2,
        config = config 
      })

      -- Enable Plugin on to check header_value = Orange
      config.classes = make_class(1,1000,1001)
      assert(bp.plugins:insert{
        name = PLUGIN_NAME,
        route = route3,
        config = config 
      })

      -- Enable Plugin on to check header_value = Green
      config.classes = make_class(1000,1001,1002)
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
      make_requests_to_upstream("test1.com", now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = "test1.com" },
      })
      assert.res_status(302, res)
    end)

    it("Check Red Header", function()
      local now = ngx.now()
      make_requests_to_upstream("test2.com", now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = "test2.com" },
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.are.same("Red", json.headers["x-qos-class"])
    end)

    it("Check Orange Header", function()
      local now = ngx.now()
      make_requests_to_upstream("test3.com", now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = "test3.com" },
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.are.same("Orange", json.headers["x-qos-class"])
  end)

    it("Check Green Header", function()
      local now = ngx.now()
      make_requests_to_upstream("test4.com", now)
      local client = helpers.proxy_client()
      local res = client:get("/get", {
        headers = { Host = "test4.com" },
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.are.same("Green", json.headers["x-qos-class"])
    end)

end)
end