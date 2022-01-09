local po = require "resty.pushover"

describe("resty.pushover", function()
  describe("new()", function()
    local http_save

    local http
    local httpc

    local opts

    before_each(function()
      http = require("spec.mock_http")()
      http_save = po._set_resty_http(http)
      httpc = http.get_client()
      opts = { token = "t", user_key = "u" }
    end)

    after_each(function()
      po._set_resty_http(http_save)
    end)

    describe("input validation", function()
      local validate = po.new

      local http_mock

      local function assert_ok(msg)
        local ok, err = validate(msg)
        assert.truthy(ok)
        assert.is_nil(err)
        return ok
      end

      local function assert_fail(msg)
        local ok, err = validate(msg)
        assert.falsy(ok)
        assert.not_nil(err)
        assert.equals("string", type(err))
        return err
      end


      before_each(function()
        http_mock = require("spec.mock_http")()
        http_save = po._set_resty_http(http_mock)
        http_mock.get_client().connect = function() return true end
      end)

      after_each(function()
        po._set_resty_http(http_save)
      end)

      it("requires table input", function()
        assert_fail()
        assert_fail(false)
        assert_fail("yes")
        assert_fail(123)
      end)

      it("requires token and user_key as non-empty strings", function()
        assert_fail {}
        assert_fail { token    = "t" }
        assert_fail { user_key = "u" }
        assert_fail { token    = "",  user_key = "u" }
        assert_fail { token    = "t", user_key = "" }
        assert_fail { token    = "t", user_key = true }
        assert_fail { token    = 123, user_key = "u" }
      end)

      it("requires a valid base_url, if provided", function()
        assert_ok   { base_url = nil,   token = "t", user_key = "u" }
        assert_fail { base_url = "<no", token = "t", user_key = "u" }
        assert_fail { base_url = 123,   token = "t", user_key = "u" }
        assert_fail { base_url = {},    token = "t", user_key = "u" }
        assert_fail { base_url = false, token = "t", user_key = "u" }
      end)
    end)

    it("returns nil and an error of http.new() fails", function()
      http.new = function() return nil, ".new()" end
      local ok, err = po.new(opts)
      assert.is_nil(ok)
      assert.equals(".new()", err)
    end)

    it("returns nil and an error if httpc:connect() fails", function()
      httpc.connect = function() return nil, ":connect()" end
      local ok, err = po.new(opts)
      assert.is_nil(ok)
      assert.equals(":connect()", err)
    end)

    it("returns a resty.pushover.client object on success", function()
      httpc.connect = function() return true end
      local client, err = po.new(opts)
      assert.is_nil(err)
      assert.equals("table", type(client))
      assert.equals(opts.token, client.token)
      assert.equals(opts.user_key, client.user_key)
      assert.equals(httpc, client.httpc)
    end)

    it("allows overriding the base_uri/base_url", function()
      httpc.connect = function() return true end
      opts.base_url = "https://test.test:8443/api"
      local client, err = po.new(opts)
      assert.is_nil(err)
      assert.equals("/api", client.base_uri)
    end)
  end)

  describe("notify()", function()
    local http_save

    local client
    local opts = { token = "t", user_key = "u", base_url = "http://test.test/api" }

    local function set_response(res)
      client.httpc.request = function()
        return res
      end
    end

    before_each(function()
      local http = require("spec.mock_http")()
      http_save = po._set_resty_http(http)
      http.get_client().connect = function() return true end
      client = assert(po.new(opts))
    end)

    after_each(function()
      po._set_resty_http(http_save)
    end)

    it("returns nil and an error string for an invalid message", function()
      local cases = {
        false,
        "",
        { message = "" },
        { message = true },
        { message = "msg", priority = 1000 },
      }

      for _, input in ipairs(cases) do
        local ok, err = client:notify(input)
        assert.is_nil(ok)
        assert.equals("string", type(err))
      end
    end)

    it("returns nil and an error string when the request fails", function()
      client.httpc.request = function() return nil, "TEST" end
      local ok, err = client:notify("yes")
      assert.is_nil(ok)
      assert.equals("string", type(err))
      assert.matches("failed sending request", err, 1, true)
      assert.matches("TEST", err, 1, true)
    end)

    it("returns truth-y in the happy case", function()
      set_response({
        status    = 200,
        has_body  = true,
        read_body = function() return  '{ "status": 1 }' end,
        headers   = { ["content-type"] = "application/json" },
      })
      local ok, err, body = client:notify("test")
      assert.truthy(ok)
      assert.is_nil(err)
      assert.same({ status = 1 }, body)
    end)

    it("returns an error if the response content-type isn't json", function()
      set_response({
        status    = 200,
        has_body  = true,
        read_body = function() return  '{ "status": 1 }' end,
        headers   = { ["content-type"] = "none" },
      })
      local ok, err, body = client:notify("test")
      assert.falsy(ok)
      assert.matches("invalid API response", err)
      assert.equals('{ "status": 1 }', body)
    end)

    it("returns an error if the response isn't valid json", function()
      set_response({
        status    = 200,
        has_body  = true,
        read_body = function() return  'invalid json!' end,
        headers   = { ["content-type"] = "application/json" },
      })
      local ok, err, body = client:notify("test")
      assert.falsy(ok)
      assert.matches("invalid API response", err)
      assert.is_nil(body)
    end)

    it("returns an error if the response json isn't a table", function()
      set_response({
        status    = 200,
        has_body  = true,
        read_body = function() return  '"test"' end,
        headers   = { ["content-type"] = "application/json" },
      })
      local ok, err, body = client:notify("test")
      assert.falsy(ok)
      assert.matches("invalid API response", err)
      assert.equals("test", body)
    end)

    it("returns an error when the response json status isn't `1`", function()
      set_response({
        status    = 200,
        has_body  = true,
        read_body = function() return  '{ "status": 0 }' end,
        headers   = { ["content-type"] = "application/json" },
      })
      local ok, err, body = client:notify("test")
      assert.falsy(ok)
      assert.matches("invalid API response", err)
      assert.same({ status = 0 }, body)

      set_response({
        status    = 200,
        has_body  = true,
        read_body = function() return  '{ }' end,
        headers   = { ["content-type"] = "application/json" },
      })
      ok, err, body = client:notify("test")
      assert.falsy(ok)
      assert.matches("invalid API response", err)
      assert.same({}, body)
    end)

    local cases = {
      {
        status = 429,
        err = "rate-limited",
      },
      {
        status =  432,
        err = "invalid request",
      },
      {
        status = 567,
        err = "internal server error",
      },
      {
        status = 301,
        err = "unknown",
      },
      {
        desc = "no status code",
        status = nil,
        err = "invalid API response",
      },
      {
        desc = "invalid status code",
        status = "NOPE",
        err = "invalid API response",
      },
    }

    for _, case in ipairs(cases) do
      local name = string.format(
      "handles http status (%s)",
      case.desc or case.status
      )
      it(name, function()
        set_response({
          status    = case.status,
          has_body  = true,
          read_body = function() return  '{ "status": 1 }' end,
          headers   = { ["content-type"] = "application/json" },
        })
        local ok, err, body = client:notify("test")
        assert.falsy(ok)
        assert.equals(case.err, err)
        assert.same({ status = 1 }, body)
      end)
    end
  end)
end)
