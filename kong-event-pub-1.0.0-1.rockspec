package = "kong-event-pub"

version = "1.0.0-1"

supported_platforms = {"linux"}

source = {
  url = "git@github.com:Platformatory/kong-event-pub.git",
  tag = "1.0.0"
}

description = {
  summary = "Turn Kong API logs into an event solurce",
  license = "MIT",
  maintainer = "Pavan Keshavamurthy <pavan@platformatory.com>"
}

dependencies = {
  "lua-resty-kafka >= 0.20-0",
  "uuid >= 0.3-1",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.kong-event-pub.handler"] = "kong/plugins/kong-event-pub/handler.lua",
    ["kong.plugins.kong-event-pub.schema"] = "kong/plugins/kong-event-pub/schema.lua",
  }
}
