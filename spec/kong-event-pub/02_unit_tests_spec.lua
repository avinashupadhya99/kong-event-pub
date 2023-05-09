local PLUGIN_NAME = "kong-event-pub"
local plugin = require("kong.plugins."..PLUGIN_NAME..".handler")

local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()


  it("does not accept unclosed placeholders in topic name pattern", function()

    local ok, err = validate({
      bootstrap_servers = "localhost",
      topic = "{{request.path",
      sasl_user = "foo",
      sasl_password = "bar",
      })
    assert.is_falsy(ok)
  end)

  it("accepts properly closed topic name patterns and fully formed, valid JSON templates with placeholders in eventval", function()

    local ok, err = validate({
      bootstrap_servers = "localhost",
      topic = "{{request.path}}",
      sasl_user = "foo",
      sasl_password = "bar",
      eventval = '{"request": "{{ request }}", "response": "{{ response }}", "status": "{{ response.status }}"}'
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("does not accept invalid JSON in eventval", function()
    local ok, err = validate({
      bootstrap_servers = "localhost",
      topic = "{{request.path}}",
      sasl_user = "foo",
      sasl_password = "bar",
      eventval = '{"request": {{ request }}, "response": {{ response }}, "status": {{ response.status.malformedJSON'
      })

    assert.is_same({
      ["@entity"] = {
        [1] = "Invalid event value template. It should be valid JSON and all placeholders must be properly enclosed in {{ double braces }}"
      }
    }, err)
    assert.is_falsy(ok)
  end)


end)
