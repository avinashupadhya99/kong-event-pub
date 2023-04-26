local json = require "cjson"
local http = require "resty.http"
local client = require "resty.kafka.client"
local producer = require "resty.kafka.producer"
local socket = require("socket")
local uuid = require("resty.jit-uuid")
local timestamp = require("kong.tools.timestamp")
local KongEventPub = {}

local function template_compile_json(str, data)
  -- convert JSON string to a Lua table
  local template_table = json.decode(str)

  -- recursively replace placeholders
  local function replace_placeholders(tbl)
    for k, v in pairs(tbl) do
      if type(v) == "table" then
        replace_placeholders(v)
      elseif type(v) == "string" and string.match(v, '{{%s*(.-)%s*}}') then
        local placeholder = string.match(v, '{{%s*(.-)%s*}}')
        local parts = {}
        local value = data
        local has_placeholder = false
        for part in string.gmatch(placeholder, "[^%.]+") do
          table.insert(parts, part)
        end

        for _, part in ipairs(parts) do
          if type(value) == "table" then
            value = value[part]
            if not value then
              tbl[k] = "undefined"
              has_placeholder = true
              break
            end
          else
            tbl[k] = "undefined"
            has_placeholder = true
            break
          end
        end

        if not has_placeholder then
          tbl[k] = value
        end
      end
    end
  end

  replace_placeholders(template_table)

  -- convert modified table back into a JSON string
  return json.encode(template_table)
end



local function template_compile(str, data)
  -- search for placeholders enclosed in double curly braces
  return (string.gsub(str, '{{%s*(.-)%s*}}', function(match)
    local value = data
    for key in string.gmatch(match, '([^%.]+)') do
      value = value[key:gsub('[%[%]]', '')]
      kong.log.inspect(value)
      if not value then
        return ''
      end
    end
    return value
  end))
end

local function kong_get_current_context(context)
  local context = context or {}
  context['request'] = {}
  context['request']['correlation_id'] = kong.ctx.plugin.correlation_id
  context['request']['headers'] = kong.request.get_headers()
  context['request']['query'] = {}
  for k, v in pairs(kong.request.get_query()) do
    context['request']['query'][k] = v
  end
  context['request']['path'] = kong.request.get_path()
  context['request']['method'] = kong.request.get_method()
  context['request']['body'] = kong.ctx.plugin.request_body
  context['request']['time'] = kong.ctx.plugin.request_access_time
  context['client'] = {}
  context['client']['ip'] = kong.client.get_ip() 
  context['client']['consumer'] = kong.client.get_consumer()
  context['response'] = {}
  context['response']['headers'] = kong.response.get_headers()
  context['response']['body'] = kong.ctx.plugin.response_body
  context['response']['status'] = kong.response.get_status()
  context['consumer'] = kong.client.get_consumer()
  context['route'] = kong.router.get_route()
  context['service'] = {}
  context['service']['info'] = kong.router.get_service()
  context['service']['response'] = {}
  context['service']['response']['headers'] = kong.service.response.get_headers()
  context['service']['response']['status'] = kong.service.response.get_status()
  context['service']['response']['body'] = kong.service.response.get_body()
  return context
end

local function has_template_variables(str)
  local start_pos, end_pos = str:find("{{.-}}")
  return start_pos ~= nil and end_pos ~= nil
end

local function timedKafkaLog(premature, config, key, val, topic)
  if premature then
    return
  end
  
   
  local broker_list = {
    {
      host = config.bootstrap_servers,
      port = config.port,
      sasl_config = {
        mechanism = config.sasl_mechanism, 
        user = config.sasl_user, 
        password = config.sasl_password,
      },
    },
  }

  local client_config = {
    ssl = config.ssl,
    refresh_interval = 300,
    }
  --local cli = client:new(broker_list, client_config)
  local p = producer:new(broker_list, client_config)
  local offset, err = p:send(topic, key, val)
  if not offset then
    kong.log.err("Kafka even publisher producer error: ", err)
    return
  end
  kong.log("send success, offset: ", tonumber(offset))
end

function KongEventPub:iso_8601_timestamp()
    local now = ngx.now()                               -- 1632237644.324
    local ms = math.floor((now % 1) * 1000)             -- 323 or 324 (rounding)
    local epochSeconds = math.floor(now)
    return os.date("!%Y-%m-%dT%T", epochSeconds) .. "." .. ms .. "Z"  -- 2021-09-21T15:20:44.323Z
end

local function list_toset(t)

  local set = {}
  for _, l in ipairs(t) do set[l] = true end
    return set
end

local function sanitize_topic_name(str)
  -- Remove any characters that are not a letter, number, dot, underscore, or hyphen
  local sanitized = str:gsub('[^%w%.%_%-]', '')
  
  -- Replace any consecutive dots, underscores, or hyphens with a single one
  sanitized = sanitized:gsub('%.+', '.'):gsub('_+', '_'):gsub('%-+', '-')
  
  -- Remove any dots, underscores, or hyphens at the beginning or end of the string
  sanitized = sanitized:gsub('^[%._%-]+', ''):gsub('[%._%-]+$', '')
  
  -- Make sure the resulting string only contains valid characters
  sanitized = sanitized:gsub('[^%a%d%.%_%-]', '')
  
  return sanitized
end


function KongEventPub:init_worker(config)
  uuid.seed()
end  

function KongEventPub:access(config)
  kong.service.request.enable_buffering()
  kong.ctx.plugin.request_access_time = timestamp.get_utc()
  kong.ctx.plugin.request_body =  kong.request.get_body()
  kong.log.inspect(kong.request.get_body())
  kong.ctx.plugin.correlation_id = uuid()
end    


function KongEventPub:body_filter(config)
  kong.ctx.plugin.response_body = kong.response.get_raw_body()

end

function KongEventPub:log(config)  
  local filter_response_codes = list_toset(config.filter_response_status_codes) 
  local filter_request_methods = list_toset(config.filter_request_http_methods)
  local response_code = kong.response.get_status()
  local context = kong_get_current_context()

  local destination_topic
  if has_template_variables(config.topic) then 
    local compile_destination, err = template_compile(config.topic, context)
    if err then
      kong.log.err("Could not determine destination topic", err)
      return
    end
    destination_topic = compile_destination
  else
    destination_topic = config.destination_topic
  end

  destination_topic = sanitize_topic_name(destination_topic)
  kong.log.inspect("Destination topic: ", destination_topic)

  local event_key
  if has_template_variables(config.eventkey) then
    local compile_key, err = template_compile(config.eventkey, context)
    if err then
      kong.log.err("Could not determine event key", err)
      return
    end
    event_key = compile_key
  else
    event_key = config.eventkey
  end    
  kong.log.inspect("Event Key: ", event_key)
 
  local event_val
  if config.eventval ~= "default" then
    local compile_value, err = template_compile_json(config.eventval, context)
    if err then
      kong.log.err("Could not compile message value", err)
      return
    end
    event_val = compile_value
  else
    event_val = json.encode(context)
  end    


  if filter_request_methods[context.request.method] == nil then
    kong.log.info("Skipping publishing event with request correlation ID: "..context.request.correlelation_id.." since the HTTP method is not in the whitelist")
    return
  end  

  if filter_response_codes[context.response.status] == nil then
    kong.log.info("Skipping publishing event with request correlation ID: "..context.request.correlation_id.." since the response code not in the white list")
    return
  end  
  
  
  local ok, err = ngx.timer.at(0, timedKafkaLog, config, event_key, event_val, destination_topic) 
  if not ok then
    ngx.log(ngx.ERR, "timer no create:", err)
    return
  end
end


KongEventPub.PRIORITY  = 1000
KongEventPub.VERSION = "0.1.1"
return KongEventPub
