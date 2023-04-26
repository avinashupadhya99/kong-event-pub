# Overview

This plugin enables turning your Kong API Gateway into an event source. It can be configured to take API logs and relay them to configurable Kafka topics. It also supports authentication to Kafka using SASL/PLAIN (and therefore supports confluent cloud)

# Features

- Fully customizable Event val template
- Dynamic topic patterns
- Dynamic event keying
- Filter which events to publish and which ones to not (based on request method or response code)

# Installation

```
luarocks install kong-event-pub
```

# Configuration

| Parameter | Default  | Required | description |
| --------- | -------- | -------- | ----------- |
| config.bootstrap_servers | | Yes | Kafka Bootstrap |
| config.port | 9092 | Yes | Kafka port |
| config.ssl | true | Yes | Whether SSL/TLS is enabled |
| config.sasl_mechanism | PLAIN | yes | Supports PLAIN, SCRAM-SHA-256, SCRAM-SHA-512 |
| config.sasl_user | | Yes | SASL Username |
| config.sasl_password | | Yes | SASL Password |
| config.eventkey | | Yes | Defaults to request path |
| config.eventval | "default" | No | A valid JSON string with placeholders. By default, publishes request, response, service, route, consumer details |
| config.filter_request_http_methods | POST, PUT, DELETE, PATCH | No | Publish events only when requests match these HTTP methods |
| config.filter_response_status_code | 200, 201 | No | Publish events only when responses match these response codes |
| config.required_acks | 3 | No | Required acks from the broker |


