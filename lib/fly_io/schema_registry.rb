# frozen_string_literal: true

require "json"

module FlyIO
  module SchemaRegistry
    module_function

    def schemas
      @schemas ||= JSON.parse(File.read(File.expand_path("generated/schemas.json", __dir__), encoding: "UTF-8")).freeze
    end

    def install_model_constants!
      schemas.each do |name, schema|
        constant_name = schema.fetch("x-ruby-class")
        next if Models.const_defined?(constant_name, false)

        schema_name = name
        klass = Class.new(Model)
        klass.const_set(:SCHEMA_NAME, schema_name.freeze)
        Models.const_set(constant_name, klass)
      end
    end

    def build(name, attributes)
      install_model_constants!
      Models.const_get(schemas.fetch(name).fetch("x-ruby-class"), false).new(attributes)
    end

    def coerce(schema, value)
      return value if value.nil? || !schema || !schema.is_a?(Hash)

      schema = resolve(schema)
      if (reference = schema["$resolved_ref"]) && value.is_a?(Hash)
        return build(reference, value)
      end

      schema = flatten_all_of(schema)

      case schema["type"]
      when "array"
        value.is_a?(Array) ? value.map { |item| coerce(schema["items"], item) } : value
      when "object"
        coerce_object(schema, value)
      else
        value
      end
    end

    def coerce_property(schema_name, property, value)
      schema = schemas[schema_name]
      coerce(schema&.dig("properties", property), value)
    end

    def resolve(schema)
      reference = schema["$ref"]
      return schema unless reference

      name = if reference.start_with?("#/components/schemas/")
               reference.delete_prefix("#/components/schemas/")
             elsif reference.start_with?("#/additional/schemas/")
               reference.delete_prefix("#/additional/schemas/")
             else
               raise FlyIO::ArgumentError, "unsupported schema reference: #{reference}"
             end
      schemas.fetch(name).merge("$resolved_ref" => name)
    end

    def flatten_all_of(schema)
      return schema unless schema["allOf"]

      schema["allOf"].reduce(schema.except("allOf")) do |result, member|
        resolved = flatten_all_of(resolve(member).except("$resolved_ref"))
        result.merge(resolved) do |key, left, right|
          key == "properties" ? left.merge(right) : right
        end
      end
    end

    def coerce_object(schema, value)
      return value unless value.is_a?(Hash)

      properties = schema.fetch("properties", {})
      value.each_with_object({}) do |(key, child), result|
        result[key.to_s] = coerce(properties[key.to_s] || schema["additionalProperties"], child)
      end
    end
  end
end
