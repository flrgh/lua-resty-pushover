--- OpenResty Pushover API client
local _M = {
  _VERSION = "0.1.0",
}

local http = require "resty.http"
local cjson = require "cjson.safe"

local insert = table.insert
local concat = table.concat
local type = type
local tostring = tostring
local pairs = pairs
local ipairs = ipairs
local fmt = string.format

local BASE_URL = "https://api.pushover.net/1"

local MESSAGE_HEADERS = {
  ["content-type"] = "application/json",
  ["user-agent"]   = "lua-resty-pushover v" .. _M._VERSION .. " (https://github.com/flrgh/lua-resty-pushover)",
}

--- The pushover client object
---
---@class resty.pushover.client
---
---@field token    string
---@field user_key string
---@field base_uri string
---@field httpc    resty.http.httpc
local client = {}
client.__index = client

---@alias resty.pushover.api.message.sound
---| '"pushover"' # default
---| '"bike"'
---| '"bugle"'
---| '"cashregister"'
---| '"classical"'
---| '"cosmic"'
---| '"falling"'
---| '"gamelan"'
---| '"incoming"'
---| '"intermission"'
---| '"magic"'
---| '"mechanical"'
---| '"pianobar"'
---| '"siren"'
---| '"spacealarm"'
---| '"tugboat"'
---| '"alien"'
---| '"climb"'
---| '"persistent"'
---| '"echo"'
---| '"updown"'
---| '"vibrate"'
---| '"none"'

local const_mt = {
  __newindex = function()
    error("Attempted to modify table")
  end,
}

local MESSAGE_SOUNDS = setmetatable({
  --- default
  pushover     = "pushover",
  bike         = "bike",
  bugle        = "bugle",
  cashregister = "cashregister",
  classical    = "classical",
  cosmic       = "cosmic",
  falling      = "falling",
  gamelan      = "gamelan",
  incoming     = "incoming",
  intermission = "intermission",
  magic        = "magic",
  mechanical   = "mechanical",
  pianobar     = "pianobar",
  siren        = "siren",
  spacealarm   = "spacealarm",
  tugboat      = "tugboat",
  alien        = "alien",
  climb        = "climb",
  persistent   = "persistent",
  echo         = "echo",
  updown       = "updown",
  vibrate      = "vibrate",
  none         = "none",
}, const_mt)

_M.sound = MESSAGE_SOUNDS

---@alias resty.pushover.api.message.priority
---| '-2'|'"lowest"'    # no notification/alert
---| '-1'|'"low"'       # send as a quiet notification
---| '0' |'"normal"'    # normal priority
---| '1' |'"high"'      # high-priority/bypass quiet hours
---| '2' |'"emergency"' # high-priority/require confirmation

local MESSAGE_PRIORITIES = {
  lowest    = -2,
  low       = -1,
  normal    = 0,
  high      = 1,
  emergency = 2,
}

do
  local values = {}
  for _, v in pairs(MESSAGE_PRIORITIES) do
    insert(values, v)
  end
  for _, v in ipairs(values) do
    MESSAGE_PRIORITIES[v] = v
  end
end

_M.priority = setmetatable(MESSAGE_PRIORITIES, const_mt)

---@class resty.pushover.api.message
---@field token       string
---@field user        string
---@field message     string                              # your message
---@field attachment? any                                 # not yet implemented
---@field device?     string|string[]                     # your user's device name to send the message directly to that device, rather than all of the user's devices
---@field title?      string                              # your message's title, otherwise your app's name is used
---@field url?        string                              # a supplementary URL to show with your message
---@field url_title?  string                              # a title for your supplementary URL, otherwise just the URL is shown
---@field priority?   resty.pushover.api.message.priority # message priority
---@field sound?      string                              # the name of one of the sounds supported by device clients to override the user's default sound choice
---@field timestamp?  number                              # a Unix timestamp of your message's date and time to display to the user, rather than the time your message is received by our API
---@field html        boolean                             # use html for message formatting
---@field monospace   boolean                             # use monospace for message formatting
---@field retry?      number                              # specifies how often (in seconds) the Pushover servers will send the same notification to the user
---@field expire?     number                              # specifies how many seconds your notification will continue to be retried for
---@field callback?   string                              # a publicly-accessible URL that our servers will send a request to when the user has acknowledged your notification.

---@class resty.pushover.api.message_response
---@field status   number   # 1 => success; anything else is an error
---@field request  string   # request id
---@field user?    string
---@field errors?  string[] # validation errors for 4xx responses
---@field receipt? string   # receipt id (only for emergency priority messages)

---@param dev string|string[]
---@return string?
local function format_message_device(dev)
  if not dev then
    return nil
  end

  if type(dev) == "table" then
    return concat(dev, ",")
  end

  return tostring(dev)
end

local validate_types
do
  local fields = {
    { "message",   "string"  },
    { "url",       "string"  },
    { "title",     "string"  },
    { "url_title", "string"  },
    { "callback",  "string"  },
    { "sound",     "string"  },
    { "retry",     "number"  },
    { "timestamp", "number"  },
    { "html",      "boolean" },
    { "monospace", "boolean" },
  }

  local e_type = "invalid `message.%s` type (expected: %s, got: %s)"
  local e_empty = "`message.%s` cannot be empty"

  ---@param m resty.pushover.api.message
  ---@return boolean ok
  ---@return string? error
  validate_types = function(m)
    for _, field in ipairs(fields) do
      local name, ftype = field[1], field[2]

      local value = m[name]
      if value ~= nil then
        local vtype = type(value)

        if vtype ~= ftype then
          return nil, e_type:format(name, ftype, vtype)
        end

        if vtype == "string" and value == "" then
          return nil, e_empty:format(name)
        end
      end
    end

    return true
  end

end

---@param msg string|resty.pushover.api.message
---@return resty.pushover.api.message? message
---@return string? error
local function validate_message(msg)
  if not msg then
    return nil, "message required"
  end

  local mtype = type(msg)

  if mtype == "string" then
    msg = { message = msg }

  elseif mtype ~= "table" then
    return nil, "invalid message type: " .. mtype
  end

  if not msg.message then
    return nil, "empty message"
  end

  local ok, err = validate_types(msg)
  if not ok then
    return nil, err
  end

  if msg.html and msg.monospace then
    return nil, "`html` and `monospace` are mutually exclusive"
  end


  if msg.url_title and not msg.url then
    return nil, "`url` is required for `url_title`"
  end

  if msg.device then
    local dtype = type(msg.device)
    if dtype ~= "string" and dtype ~= "table" then
      return nil, "invalid `device` type: " .. dtype
    end
  end

  if msg.priority and not MESSAGE_PRIORITIES[msg.priority] then
    return nil, "invalid `priority`: " .. tostring(msg.priority)
  end

  if msg.retry or msg.expire or msg.callback then
    if msg.priority ~= MESSAGE_PRIORITIES.emergency then
      return nil, "`retry`/`expire`/`callback` only allowed for emergency messages"
    end
  end

  if msg.sound and not MESSAGE_SOUNDS[msg.sound] then
    return nil, "invalid `message.sound`: " .. tostring(msg.sound)
  end


  return {
    message   = msg.message,
    title     = msg.title,
    url       = msg.url,
    url_title = msg.url_title,
    priority  = MESSAGE_PRIORITIES[msg.priority],
    device    = format_message_device(msg.device),
    sound     = msg.sound,
    timestamp = msg.timestamp,
    html      = msg.html and 1,
    monospace = msg.monospace and 1,
    retry     = msg.retry,
    expire    = msg.expire,
    callback  = msg.callback,
    user      = nil,
    token     = nil,
  }
end

---@param msg string
---@param err   string|nil
local function errf(msg, err)
  if err then
    return fmt("%s: %s", msg, err)
  end
  return msg
end

---@param self resty.pushover.client
---@param ep string
---@return string
local function client_path(self, ep)
  return self.base_uri .. "/" .. ep:gsub("^/+", "")
end

---@param  res                                  resty.http.response
---@return resty.pushover.api.message_response? body
---@return string?                              error
local function read_body(res)
  if not res.has_body then
    return nil, "no response body"
  end

  local body, err = res:read_body()

  if not body then
    return nil, errf("failed reading response body", err)
  elseif body == "" then
    return nil, "empty response body"
  end

  local ctype = res.headers["content-type"]
  if type(ctype) == "table" then
    ctype = ctype[1]
  end

  if ctype and ctype:lower():find("application/json") then
    body, err = cjson.decode(body)
    if body == nil then
      return body, errf("failed decoding json response body", err)
    end
  end

  return body
end

--- Send a notification.
---
---@param  message                              resty.pushover.api.message
---@return boolean                              ok
---@return string?                              error
---@return resty.pushover.api.message_response? response
function client:notify(message)
  local msg, err = validate_message(message)
  if not msg then
    return nil, err
  end

  msg.token = self.token
  msg.user = self.user_key

  local res
  res, err = self.httpc:request({
    method  = "POST",
    path    = client_path(self, "messages.json"),
    body    = cjson.encode(msg),
    headers = MESSAGE_HEADERS,
  })

  if not res then
    return nil, errf("failed sending request", err)
  end

  local body, body_err = read_body(res)

  local ok = false
  err = "unknown"

  if res.status == 200 then
    if type(body) == "table" and body.status == 1 then
      ok = true
      err = nil
    else
      err = errf("invalid API response", body_err)
    end

  elseif res.status == 429 then
    err = "rate-limited"

  elseif res.status >= 400 and res.status < 500 then
    err = "invalid request"

  elseif res.status >= 500 then
    err = "internal server error"
  end

  return ok, err, body
end

---@class resty.pushover.client.opts
---@field token     string
---@field user_key  string
---@field base_url? string

--- Instantiate a new Pushover client
---
---@param  opts                   resty.pushover.client.opts
---@return resty.pushover.client? client
---@return string?                error
function _M.new(opts)
  local token = opts.token
  if type(token) ~= "string" then
    return nil, "`opts.token` is required and must be a string"
  end

  local user_key = opts.user_key
  if type(user_key) ~= "string" then
    return nil, "`opts.user_key` is required and must be a string"
  end

  local base_url = opts.base_url or BASE_URL
  local parsed, err = http:parse_uri(base_url)
  if not parsed then
    return nil, "invalid `base_url` " .. (err or "")
  end

  local httpc
  httpc, err = http.new()
  if not httpc then
    return nil, err
  end

  local ok
  ok, err = httpc:connect({
    scheme = parsed[1],
    host   = parsed[2],
    port   = parsed[3],
    ssl_verify = false,
  })

  if not ok then
    return nil, err
  end

  return setmetatable(
    {
      base_uri = parsed[4]:gsub("/+$", ""),
      token    = token,
      user_key = user_key,
      httpc    = httpc,
    },
    client
  )
end

return _M
