return function()
  local resty_http = require "resty.http"

  local client = {}

  return {
    new = function()
      return client
    end,

    parse_uri = resty_http.parse_uri,

    get_client = function()
      return client
    end,
  }
end

