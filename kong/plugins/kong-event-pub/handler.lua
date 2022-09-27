local BasePlugin = require "kong.plugins.base_plugin"
local inspect = require 'inspect'
local json = require "cjson"
local http = require "resty.http"
local client = require "resty.kafka.client"
local producer = require "resty.kafka.producer"
local socket = require("socket")
local uuid = require("uuid")
local timestamp = require("kong.tools.timestamp")

local KongEventPub = BasePlugin:extend()

function KongEventPub:new()
    KongEventPub.super.new(self, "kafka-event-pub")
end


function KongEventPub:access(config)
    KongEventPub.super.access(self)
    uuid.randomseed(socket.gettime()*10000)
    kong.ctx.plugin.request_access_time = timestamp.get_utc()
    kong.ctx.plugin.request_body =  kong.request.get_body()
    kong.ctx.plugin.correlation_id = uuid()
end    


function KongEventPub:body_filter(config)
    KongEventPub.super.body_filter(self)
    kong.ctx.plugin.response_body = kong.response.get_raw_body()
end    


function KongEventPub:log(config)
    KongEventPub.super.log(self)
    local eventmaps = event_maps_to_set(config.eventmaps)
    local rkey = kong.request.get_path_with_query() ..'__'.. kong.request.get_method()
    local eventmapped = eventmaps[rkey]

    if eventmapped == nil then
      return
    end  
  
    local response_set = list_toset(eventmapped.response_codes) 
    local response_code = kong.response.get_status()

    kong.log.inspect(response_set)
    kong.log.inspect(response_code)

        
    if response_set[response_code] == nil then
      return
    end  
  
    local destination = eventmapped['destination_topic']

    if destination == nil then
      destination = config.dlc
    end  

    local logPayload = {
      specversion = '1.0',
      id = kong.ctx.plugin.correlation_id,
      epoch = kong.ctx.plugin.request_access_time,
      time = iso_8601_timestamp(),
      source = kong.client.get_ip(),
      type = destination,
      request = {
        method = kong.request.get_method(),
        path = kong.request.get_path_with_query(),
        headers = kong.request.get_headers(),
        body = kong.ctx.plugin.request_body,
      },
      response = {
        status = kong.response.get_status(),
        headers = kong.response.get_headers(),
        body = kong.ctx.plugin.response_body,
      },
      consumer = kong.client.get_consumer(),
      route = kong.router.get_route(),
      service = kong.router.get_service(),
    }

    local ok, err = ngx.timer.at(0, timedKafkaLog, config, logPayload, logPayload.type)
    if not ok then
      ngx.log(ngx.ERR, "timer no create:", err)
      return
    end  
end

function timedKafkaLog(premature, config, logPayLoad, destination_topic)

    if premature then
      return
    end

    local client_config = {
      ssl = true,
      refresh_interval = 300,
    }

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
--    support this and other properties 
      refresh_interval = 300,
    }

    local cli = client:new(broker_list, client_config)
--  useful to force metadata refreshes
--  cli:refresh()
--  local brokers, partitions = cli:fetch_metadata("fx")

    local p = producer:new(broker_list, client_config)
    local offset, err = p:send(destination_topic, logPayLoad.request.path, json.encode(logPayLoad))
    if not offset then
      kong.log("send err:", err)
      return
    end
    kong.log("send success, offset: ", tonumber(offset))

end

function iso_8601_timestamp()
    local now = ngx.now()                               -- 1632237644.324
    local ms = math.floor((now % 1) * 1000)             -- 323 or 324 (rounding)
    local epochSeconds = math.floor(now)
    return os.date("!%Y-%m-%dT%T", epochSeconds) .. "." .. ms .. "Z"  -- 2021-09-21T15:20:44.323Z
end

function getTableKeys(tab)
  local keyset = {}
  for k,v in pairs(tab) do
    keyset[#keyset + 1] = k
  end
  return keyset
end

function event_maps_to_set(eventmaps)
  local set = {}
  for _, l in ipairs(eventmaps) do set[l['request_path_match']..'__'..l['http_method']] = l end
    return set
end

function list_toset (t)
  local set = {}
  for _, l in ipairs(t) do set[l] = true end
    return set
end

return KongEventPub
