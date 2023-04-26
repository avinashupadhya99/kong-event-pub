local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")
local json = require("cjson")

local function validate_json_with_placeholders(str)
  if str == 'default' then
    return true
  end

  local success, json_table = pcall(json.decode, str)
  if not success then
    return false
  end

  -- Iterate over the table to check for placeholders
  local function check_placeholders(tbl)
    for k, v in pairs(tbl) do
      if type(v) == "table" then
        check_placeholders(v)
      elseif type(v) == "string" then
        local match = string.match(v, '%{%{%s*(.-)%s*%}%}')
        if match then
          -- Check that the placeholder is properly enclosed in double braces
          if string.find(v, '%{%s*%{%s*.-[^%s}]%s*%}%s*%}') then
            return false
          end
        end
      end
    end
    return true
  end
  
  return true
  --return check_placeholders(json_table)
end

local function validate_placeholders(str)
  local count = 0
  for i = 1, #str do
    local char = str:sub(i,i)
    if char == '{' then
      count = count + 1
    elseif char == '}' then
      count = count - 1
      if count < 0 then
        return false
      end
    end
  end
  return count == 0
end

local function validate_logging_spec(plugin)
  if not validate_placeholders(plugin.config.topic) then
    return false, "Invalid topic configuration. Ensure placeholders are closed properly"
  end

  if not validate_placeholders(plugin.config.eventkey) then
    return false, "Invalid event key configuration, Ensure placeholders are closed properly"
  end

  if not validate_json_with_placeholders(plugin.config.eventval) then
    return false, "Invalid event value template. It should be valid JSON and all placeholders must be properly enclosed in {{ double braces }}"
  end

  return true
end        

return {
  name = plugin_name,
  fields = { 
    {
      config = {
        type = "record",
        fields = { 
          { bootstrap_servers = { type = "string", required = true, default = "|", len_max = 120}}, 
          { port = { type = "number", required = false, default = 9092, between = {0, 65534}}},
          { ssl = { type = "boolean", required = false, default = true}},
          { sasl_mechanism = { type = "string", required = true, default = "PLAIN", len_max = 10, one_of = {"SCRAM-SHA-256", "SCRAM-SHA-512", "PLAIN"}}},
          { port = { type = "number", required = false, default = 9092, between = {0, 65534}}},
          { filter_request_http_methods = { type = "array", required = false, default = {"POST", "PUT", "DELETE", "PATCH"}, elements = {type = "string", one_of = {"GET", "PATCH", "POST", "PUT", "DELETE",}}}},
          { filter_response_status_codes = { type = "array", required = false, default = {200,201}, elements= {type = "number",}}},
          { topic = { type = "string", required = false, default = "{{request.path}}"}},
          { eventkey = { type = "string", required = false, default = "{{request.correlation_id}}"}},
          { eventval = { type = "string", required = false, default = "default"}},
          { format = { type = "string", required = false, default = "CloudEventsKafkaProtocolBinding"}},
          { sasl_user = { type = "string", required = true, default = "|", len_max = 120, encrypted = true, referenceable = true}},
          { sasl_password = { type = "string", required = true, default = "|", len_max = 120, encrypted = true, referenceable = true}},
          { request_timeout = { type = "number", required = false, default = 2000}},
          { required_acks = { type = "number", required = false, default = 1, one_of = {1,2,3}}},
          { max_retry = { type = "number", required = false, default = 3, one_of = {1,2,3}}},
          { retry_backoff = { type = "number", required = false, default = 100}},
          { api_version = { type = "number", required = false, default = 0}},
        }
      }
    }
  },
  entity_checks = {
    {
      custom_entity_check = {
        field_sources = { "config" },
        fn = validate_logging_spec,
      }
    },
  },
}
