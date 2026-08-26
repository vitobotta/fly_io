# frozen_string_literal: true

require "json"

module FlyIO
  module OperationRegistry
    MANIFEST_PATHS = %w[operations.json additional_operations.json prometheus_operations.json].map do |name|
      File.expand_path("generated/#{name}", __dir__)
    end.freeze

    module_function

    def operations
      @operations ||= MANIFEST_PATHS.flat_map do |path|
        JSON.parse(File.read(path)).fetch("operations")
      end.map { |data| Operation.new(data) }.freeze
    end

    def resources
      @resources ||= operations.group_by(&:ruby_resource).transform_values(&:freeze).freeze
    end

    def fetch(identity_or_operation_id, method: nil, path: nil)
      key = identity_or_operation_id.to_s
      matches = operations.select do |operation|
        (operation.identity == key || operation.operation_id == key) &&
          (!method || operation.http_method == method.to_s.downcase) &&
          (!path || operation.path == path)
      end
      raise FlyIO::ArgumentError, "unknown operation: #{key}" if matches.empty?
      if matches.length > 1
        raise FlyIO::ArgumentError, "ambiguous operation ID #{key}; specify method: and path:"
      end

      matches.first
    end

    class Operation
      attr_reader :data

      def initialize(data)
        @data = data.freeze
        freeze
      end

      %w[identity surface stability base_url operation_id path ruby_resource ruby_method summary].each do |name|
        define_method(name) { data[name] }
      end

      def http_method
        data.fetch("method")
      end

      def parameters
        data.fetch("parameters")
      end

      def request_body
        data["request_body"]
      end

      def responses
        data.fetch("responses")
      end

      def response_schema(status, content_type)
        response = responses[status.to_s] || responses["default"]
        return unless response

        content = response.fetch("content", {})
        return if content.empty?

        normalized_type = content_type.to_s.split(";", 2).first.to_s.downcase
        exact = content[normalized_type]
        exact&.fetch("schema", nil) || content.values.first&.fetch("schema", nil)
      end
    end
  end
end
