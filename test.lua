local po = require "resty.pushover"

local token = os.getenv("PUSHOVER_TOKEN")
local user_key = os.getenv("PUSHOVER_USER_KEY")

local client = assert(po.new({
  token = token,
  user_key = user_key,
}))

local ok, err, res = client:notify({
  title = "access requested",
})
if type(res) == "table" then res = require("cjson").encode(res) end
ngx.print(string.format("ok: %s\nerr: %s\nres: %s\n", ok, err, res))
