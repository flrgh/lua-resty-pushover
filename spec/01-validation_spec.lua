local po = require "resty.pushover"

describe("resty.pushover message input validation", function()
  local validate = po._validate_message

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

  it("fails when `attachment` is defined", function()
    assert_fail { message = "test", attachment = "attach" }
  end)
end)
