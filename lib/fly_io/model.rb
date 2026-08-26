# frozen_string_literal: true

module FlyIO
  module Models; end

  class Model
    attr_reader :attributes, :schema_name

    def initialize(attributes = nil, schema_name: if self.class.const_defined?(:SCHEMA_NAME,
                                                                               false)
                                                    self.class::SCHEMA_NAME
                                                  end,
                   **keyword_attributes)
      if attributes && !keyword_attributes.empty?
        raise FlyIO::ArgumentError, "provide model attributes as a Hash or keywords, not both"
      end

      attributes ||= keyword_attributes
      raise FlyIO::ArgumentError, "model attributes must be a Hash" unless attributes.is_a?(Hash)

      @schema_name = schema_name
      @attributes = attributes.each_with_object({}) do |(key, value), result|
        result[key.to_s] = SchemaRegistry.coerce_property(schema_name, key.to_s, value)
      end.freeze
      freeze
    end

    def [](key)
      attributes[key.to_s]
    end

    def key?(key)
      attributes.key?(key.to_s)
    end

    def to_h
      attributes.transform_values { |value| serialize(value) }
    end

    def method_missing(name, *arguments)
      return self[name] if arguments.empty? && key?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      key?(name) || super
    end

    def ==(other)
      other.is_a?(Model) && other.schema_name == schema_name && other.attributes == attributes
    end

    private

    def serialize(value)
      case value
      when Model then value.to_h
      when Array then value.map { |item| serialize(item) }
      when Hash then value.transform_values { |item| serialize(item) }
      else value
      end
    end
  end
end
