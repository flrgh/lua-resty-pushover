--- OpenResty Pushover API client
local _M = {
  _VERSION = "0.1.0",
}

local http = require "resty.http"
local cjson = require "cjson.safe"

local insert   = table.insert
local concat   = table.concat
local type     = type
local tostring = tostring
local pairs    = pairs
local ipairs   = ipairs
local fmt      = string.format
local decode   = cjson.decode
local encode   = cjson.encode

local BASE_URL = "https://api.pushover.net/1"

local MESSAGE_HEADERS = {
  ["content-type"] = "application/json",
  ["user-agent"]   = "lua-resty-pushover v" .. _M._VERSION .. " (https://github.com/flrgh/lua-resty-pushover)",
}

local const_mt = {
  __newindex = function()
    error("Attempted to modify table")
  end,
}

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
local message_fields = {
  { "message",   "string",  true  },
  { "url",       "string",  false },
  { "title",     "string",  false },
  { "url_title", "string",  false },
  { "callback",  "string",  false },
  { "sound",     "string",  false },
  { "retry",     "number",  false },
  { "timestamp", "number",  false },
  { "html",      "boolean", false },
  { "monospace", "boolean", false },
}
local client_fields = {
  { "token",    "string", true  },
  { "user_key", "string", true  },
  { "base_url", "string", false },
}

do
  local tpl = function(s)
    return function(...)
      return s:format(...)
    end
  end
  local e_type = tpl "invalid `%s.%s` type (expected: %s, got: %s)"
  local e_empty = tpl "`%s.%s` cannot be empty"
  local e_equired = tpl "`%s.%s` is required"

  local errors
  local function add_error(s)
    errors = errors or { n = 0 }
    local n = errors.n + 1
    errors[n] = s
    errors.n = n
  end

  ---@param ns string
  ---@param fields table[]
  ---@param t table
  ---@return boolean valid
  ---@return string? err
  validate_types = function(ns, fields, t)
    if t == nil or type(t) ~= "table" then
      return nil, "`" .. ns .. "` table is required"
    end

    errors = nil

    for _, field in ipairs(fields) do
      local name, ftype, required = field[1], field[2], field[3]

      local value = t[name]
      local ok = true

      if required and value == nil then
        ok = false
        add_error(e_equired(ns, name))
      end

      if ok and value ~= nil then
        local vtype = type(value)

        if vtype ~= ftype then
          ok = false
          add_error(e_type(ns, name, ftype, vtype))
        end

        if ok and vtype == "string" and value == "" then
          add_error(e_empty(ns, name))
        end
      end
    end

    if errors then
      return nil, concat(errors, "\n"), errors
    end

    return true
  end

end

---@param msg string|resty.pushover.api.message
---@return resty.pushover.api.message? message
---@return string? err
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

  local ok, err = validate_types("message", message_fields, msg)
  if not ok then
    return nil, err
  end

  if msg.html and msg.monospace then
    return nil, "`message.html` and `message.monospace` are mutually exclusive"
  end


  if msg.url_title and not msg.url then
    return nil, "`message.url` is required for `message.url_title`"
  end

  if msg.device then
    local dtype = type(msg.device)
    if dtype ~= "string" and dtype ~= "table" then
      return nil, "invalid `message.device` type: " .. dtype
    end
  end

  if msg.priority and not MESSAGE_PRIORITIES[msg.priority] then
    return nil, "invalid `message.priority`: " .. tostring(msg.priority)
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

  ---@type string
  local ctype = res.headers["content-type"]
  if type(ctype) == "table" then
    ctype = ctype[1]
  end

  if ctype and ctype:lower():find("application/json", 1, true) then
    body, err = decode(body)
    if body == nil then
      return body, errf("failed decoding json response body", err)
    end
  end

  return body
end

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

--- Send a notification.
---
---@param  message                              resty.pushover.api.message
---@return boolean                              ok
---@return resty.pushover.api.message_response? response
---@return string?                              error
function client:notify(message)
  local msg, err = validate_message(message)
  if not msg then
    return nil, err
  end

  msg.token = self.token
  msg.user = self.user_key

  local req_body
  req_body, err = encode(msg)
  if not req_body then
    return nil, errf("failed encoding request body", err)
  end

  local res
  res, err = self.httpc:request({
    method  = "POST",
    path    = self.base_uri .. "/messages.json",
    body    = req_body,
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

  elseif type(res.status) ~= "number" then
    err = "invalid API response"

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
---```lua
---  local po = require "resty.pushover"
---  local client, err = po.new({
---    token = "[...]",
---    user_key = "[...]"
---  })
---
---  if err then
---    error("failed creating pushover client: " .. err)
---  end
---```
---
---@param  opts                   resty.pushover.client.opts
---@return resty.pushover.client? client
---@return string?                error
function _M.new(opts)
  local ok, err = validate_types("opts", client_fields, opts)
  if not ok then
    return nil, err
  end

  local base_url = opts.base_url or BASE_URL
  local parsed
  parsed, err = http:parse_uri(base_url)
  if not parsed then
    return nil, "invalid `opts.base_url` " .. (err or "")
  end

  local httpc
  httpc, err = http.new()
  if not httpc then
    return nil, err
  end

  ok, err = httpc:connect({
    scheme          = parsed[1],
    host            = parsed[2],
    port            = parsed[3],
    ssl_server_name = parsed[1] == "https" and parsed[2],
  })

  if not ok then
    return nil, err
  end

  return setmetatable(
    {
      base_uri = parsed[4]:gsub("/+$", ""), -- remove trailing slash
      token    = opts.token,
      user_key = opts.user_key,
      httpc    = httpc,
    },
    client
  )
end


---@class pushover.notify_opts : resty.pushover.client.opts, resty.pushover.api.message

--- Single shot convenience method.
---
---@param opts pushover.notify_opts
---@return boolean                              ok
---@return resty.pushover.api.message_response? response
---@return string?                              error
function _M.notify(opts)
  local po, err = _M.new(opts)
  if not po then
    return nil, err
  end

  return po:notify(opts)
end

---@diagnostic disable-next-line
if _G._TEST then -- luacheck: ignore
  _M._validate_types = validate_types
  _M._validate_message = validate_message
  _M._set_resty_http = function(mock)
    local save = http
    http = mock
    return save
  end
end

return _M
