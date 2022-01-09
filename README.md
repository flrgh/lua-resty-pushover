# lua-resty-pushover

OpenResty Lua library for pushover.net


## API Reference

### pushover.new

**syntax** *client, err = pushover.new(opts)*

Returns a new Pushover API client object. On error, returns `nil` and an error
string.

Under the hood, this method instantiates an http client and establishes a
connection to the Pushover API.

The `opts` parameter is a table that takes the following fields:

* `token` (string, required)
    Your application's Pushover API token.

* `user_key` (string, required)
    Your Pushover API user key.

* `base_url` (string, optional, default: `https://api.pushover.net/1`)
    This is primarily for testing and does not need to be provided.

See the [application registration docs](https://pushover.net/api#registration) for more info on retrieving your token and user key.

#### Example

```lua
local po = require "resty.pushover"
local client, err = po.new({
  token = "[...]",
  user_key = "[...]"
})

if err then
  error("failed creating pushover client: " .. err)
end
```

### client.notify

**syntax** *ok, err, res = client:notify(message)*

Send a push notification. Returns the following:

* `ok` (boolean|`nil`)
  truth-y on success, false-y on failure

* `err` (string|`nil`)
  an error message (if any)

* `res` (table|string|`nil`)
  the [response](https://pushover.net/api#response) from the Pushover API (if any)


The `message` input parameter can be a table with the following fields:

* `message` (required, string)
  Your message

* `device` (optional, string|table)
  Your user's device name to send the message directly to that device, rather than all of the user's devices. Can be a string (`"device-a"`) or an array-like table of strings (`{"device-a", "device-b"}`).

* `title` (optional, string)
  Your message's title, otherwise your app's name is used.

* `url` (optional, string)
  A [supplementary URL](https://pushover.net/api#urls) to show with your message.

* `url_title` (optional, string)
  A title for your supplementary URL, otherwise just the URL is shown. Only valid if `url` is also provided.

* `priority` (optional, number)
  Message [priority](https://pushover.net/api#priority). For convenience, there is a lookup table of priority constants (`pushover.priority`) that may be used to reference priority by string.

* `sound` (optional, string)
  Message [notification sound](https://pushover.net/api#sounds). For convenience, there is a lookup table of sound constants (`pushover.sound`) that may be used.

* `timestamp` (optional, number)
  A Unix timestamp of your message's date and time to display to the user, rather than the time your message is received by our API ([doc](https://pushover.net/api#timestamp)).

* `html` (optional, boolean)
  Use html for message [styling](https://pushover.net/api#html). This option is mutually-exclusive with `monospace`.

* `monospace` (optional, boolean)
  Use monospace for message [styling](https://pushover.net/api#html). This option is mutually-exclusive with `html`.

* `retry` (optional, number)
  Specifies how often (in seconds) the Pushover servers will send the same notification to the user

* `expire` (optional, number)
  Specifies how many seconds your notification will continue to be retried for

* `callback` (optional, string)
  A publicly-accessible URL that our servers will send a request to when the user has acknowledged your notification.

**NOTE:** The message `attachment` [field](https://pushover.net/api#attachments) is currently not supported.

The `message` parameter can also be a single string, which is equivalent to passing in `{ message = <message> }`.

See the [Pushover Message API docs](https://pushover.net/api) for more information.

#### Example

```lua
local pushover = require "resty.pushover"
local client, err = pushover.new({
  token    = "[...]",
  user_key = "[...]",
})

if not client then
  error("failed creating client: " .. err)
end

-- these are equivalent
client:notify("my message")
client:notify({ message = "my message" })

-- using more of the message fields
client:notify({
  title     = "my message title",
  message   = "my message content",
  url       = "https://example.com/",
  url_title = "an important link",
  sound     = pushover.sound.cosmic,
  priority  = pushover.priority.high,
  monospace = true,
  device    = {"my-phone", "my-other-phone"},
})
```

**NOTE:** This library does _not_ currently implement any kind of rate-limiting. It is up to the caller to implement rate-limiting in compliance with [Pushover's policies](https://pushover.net/api#friendly).
