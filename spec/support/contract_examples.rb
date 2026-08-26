# frozen_string_literal: true

require "json"
require "uri"

module ContractExamples
  module_function

  def schemas
    FlyIO::SchemaRegistry.schemas
  end

  def example_for(schema, depth: 0, seen: [])
    return nil unless schema

    if schema["$ref"]
      name = schema["$ref"].split("/").last
      return {} if depth > 4 || seen.count(name) > 1

      return example_for(schemas.fetch(name), depth: depth + 1, seen: seen + [name])
    end
    schema = FlyIO::SchemaRegistry.flatten_all_of(schema)
    return schema["example"] if schema.key?("example")
    return schema["enum"].first if schema["enum"]

    case schema["type"]
    when "object", nil
      properties = schema.fetch("properties", {})
      selected = (Array(schema["required"]) + properties.keys.first(3)).uniq
      selected.to_h { |name| [name, example_for(properties.fetch(name), depth: depth + 1, seen: seen)] }
    when "array"
      [example_for(schema["items"], depth: depth + 1, seen: seen)]
    when "integer" then 1
    when "number" then 1.5
    when "boolean" then true
    when "string" then "example"
    end
  end

  def parameter_value(parameter)
    schema = parameter.fetch("schema")
    return schema.fetch("enum").first if schema["enum"]

    case schema["type"]
    when "integer" then 2
    when "number" then 1.5
    when "boolean" then true
    when "array" then %w[first second]
    else
      parameter["in"] == "path" ? "value /ü" : "value ü"
    end
  end

  def arguments_for(operation)
    operation.parameters.to_h do |parameter|
      [parameter.fetch("ruby_name").to_sym, parameter_value(parameter)]
    end.tap do |arguments|
      if operation.request_body
        arguments[:body] = example_for(operation.request_body.fetch("schema"))
      end
    end
  end

  def expected_path(operation, arguments)
    operation.path.gsub(/\{([^}]+)\}/) do
      name = Regexp.last_match(1)
      URI.encode_www_form_component(arguments.fetch(name.tr("-", "_").downcase.to_sym).to_s).gsub("+", "%20")
    end
  end

  def expected_query(operation, arguments)
    pairs = operation.parameters.filter_map do |parameter|
      next unless parameter["in"] == "query"

      value = arguments.fetch(parameter.fetch("ruby_name").to_sym)
      Array(value).map { |item| [parameter.fetch("name"), item == true ? "true" : item.to_s] }
    end.flatten(1)
    URI.encode_www_form(pairs)
  end

  def success_payload(response)
    content = response.fetch("content", {})
    content_type, definition = content.first
    case content_type
    when "text/plain" then [content_type, "example text"]
    when "application/octet-stream" then [content_type, "binary\x00payload".b]
    when nil then [nil, ""]
    else [content_type, JSON.generate(example_for(definition["schema"]))]
    end
  end
end
