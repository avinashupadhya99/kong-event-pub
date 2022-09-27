local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

return {
  name = plugin_name,
  fields = { 
    {
      config = {
        type = "record",
        fields = {
          { ssl = { type = "boolean", required = true, default = true }},
          { bootstrap_servers = { type = "string", required = true, default = "|", len_max = 120 }},
          { port = { type = "number", required = true, default = 9092, between = {0, 65534} }},
          { sasl_mechanism = { type = "string", required = true, default = "PLAIN", len_max = 10 }},
          { sasl_user = { type = "string", required = true, default = "|", len_max = 120 }},
          { sasl_password = { type = "string", required = true, default = "|", len_max = 120 }},
          { encoding = { type = "string", required = true, default = "application/json", one_of = {"application/json", "application/avro"}}},
          { format = { type = "string", required = true, default = "CloudEventsKafkaProtocolBinding" }},
          { eventmaps = { type = "array", required = true, default = {}, elements={
              type = "record",
              fields = {
                { request_path_match = { type = "string", required = true}},
                { position = {type = "number", required = true}},
                { http_method = { type = "string", required = true, one_of = {"GET", "POST", "PUT", "DELETE",}}},
                { response_codes = { type = "array", required = false, default = {200,201}, elements= {type = "number",}}},
                { destination_topic = { type = "string", required = true}},
                { key = { type = "string", required = true, default = "kong.request.route"}},
                { data = { type = "string", required = true, default = "kong.response.body"}},
              }
            }},
          },
          { dead_letter_channel = { type = "string", required = true, default = "dlc" }},

        }
      }
    }
  }
}


