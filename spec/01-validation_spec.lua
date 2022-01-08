local po = require "resty.pushover"

describe("resty.pushover input validation", function()
  local validate

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

  describe("messages", function()
    validate = po._validate_message

    it("allows a string", function()
      assert_ok "my message"
    end)

    it("requires non-empty message input", function()
      assert_fail()
      assert_fail { message = "" }
      assert_fail {}
      assert_fail ""
    end)

    it("requires valid lua types", function()
      assert_fail { message = false }
      assert_fail { message = "msg", url       = {} }
      assert_fail { message = "msg", title     = 123 }
      assert_fail { message = "msg", callback  = true }
      assert_fail { message = "msg", sound     = {} }
      assert_fail { message = "msg", retry     = "NaN" }
      assert_fail { message = "msg", timestamp = true }
      assert_fail { message = "msg", html      = -1 }
      assert_fail { message = "msg", monospace = -1 }
    end)

    it("ensures `url` is present when `url_title` is used", function()
      assert_ok   { message = "msg", url_title = "test", url = "test" }
      assert_fail { message = "msg", url_title = "test", url = nil }
    end)

    it("ensures only one of html/monospace is true", function()
      assert_fail { message = "msg", monospace = true,  html = true }
      assert_ok   { message = "msg", monospace = false, html = true }
      assert_ok   { message = "msg", monospace = true,  html = false }
    end)

    it("requires a valid message sound, if provided", function()
      assert_ok   { message = "msg", sound = po.sound.classical }
      assert_fail { message = "msg", sound = "not a sound" }
    end)

    it("rquires a valid message priority, if provided", function()
      assert_ok   { message = "msg", priority = po.priority.emergency }
      assert_fail { message = "msg", priority = 1000 }
    end)

    it("requires emergency priority for retry/expire/callback fields", function()
      local emerg = po.priority.emergency
      assert_ok { message = "test", priority = emerg }
      assert_ok { message = "test", priority = emerg, callback = "test" }
      assert_ok { message = "test", priority = emerg, retry    = 5 }
      assert_ok { message = "test", priority = emerg, expire   = 5 }

      local norm = po.priority.normal
      assert_fail { message = "test", priority = norm, callback  = "test" }
      assert_fail { message = "test", priority = nil,  retry     = 5 }
      assert_fail { message = "test", priority = nil,  expire    = 5 }
    end)
  end)


  describe("client", function()
    validate = po.new

    local http_save
    local http_mock

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
end)

