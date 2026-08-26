# frozen_string_literal: true

module FlyIO
  module SchemaValidator
    module_function

    def validate!(schema, value, location: "value")
      return if schema.nil? || !schema.is_a?(Hash)

      schema = SchemaRegistry.flatten_all_of(SchemaRegistry.resolve(schema))
      raw = value.is_a?(Model) ? value.to_h : value
      validate_type!(schema["type"], raw, location)
      validate_enum!(schema["enum"], raw, location)
      validate_object!(schema, raw, location) if raw.is_a?(Hash)
      validate_array!(schema, raw, location) if raw.is_a?(Array)
      true
    end

    def validate_type!(type, value, location)
      return if type.nil? || value.nil?

      valid = case type
              when "object" then value.is_a?(Hash)
              when "array" then value.is_a?(Array)
              when "string" then value.is_a?(String)
              when "integer" then value.is_a?(Integer)
              when "number" then value.is_a?(Numeric)
              when "boolean" then [true, false].include?(value)
              else true
              end
      raise FlyIO::ArgumentError, "#{location} must be #{type}" unless valid
    end

    def validate_enum!(enum, value, location)
      return unless enum && !value.nil? && !enum.include?(value)

      raise FlyIO::ArgumentError, "#{location} must be one of: #{enum.join(', ')}"
    end

    def validate_object!(schema, value, location)
      normalized = value.transform_keys(&:to_s)
      Array(schema["required"]).each do |name|
        unless normalized.key?(name) && !normalized[name].nil?
          raise FlyIO::ArgumentError, "#{location}.#{name} is required"
        end
      end
      schema.fetch("properties", {}).each do |name, property_schema|
        validate!(property_schema, normalized[name], location: "#{location}.#{name}") if normalized.key?(name)
      end
    end

    def validate_array!(schema, value, location)
      value.each_with_index { |item, index| validate!(schema["items"], item, location: "#{location}[#{index}]") }
    end
  end
end
