# frozen_string_literal: true

module FlyIO
  module Resources
    class Base
      attr_reader :client

      def initialize(client)
        @client = client
        freeze
      end

      def operation(operation_id, method: nil, path: nil, **arguments)
        invoke(OperationRegistry.fetch(operation_id, method: method, path: path), arguments)
      end

      private

      def invoke(operation, arguments)
        arguments = arguments.dup
        body = arguments.delete(:body) { FlyIO::UNSET }
        extra_headers = arguments.delete(:headers) || {}
        retry_unsafe = arguments.delete(:retry_unsafe)
        request_timeout = arguments.delete(:request_timeout)
        path_params = {}
        query = {}
        operation_headers = {}

        operation.parameters.each do |parameter|
          ruby_name = parameter.fetch("ruby_name").to_sym
          present = arguments.key?(ruby_name)
          value = arguments.delete(ruby_name)
          if parameter["required"] && (!present || value.nil?)
            raise FlyIO::ArgumentError, "#{operation.ruby_method}: #{ruby_name} is required"
          end
          next unless present

          SchemaValidator.validate!(parameter["schema"], value, location: ruby_name.to_s)
          target = {"path" => path_params, "query" => query, "header" => operation_headers}.fetch(parameter.fetch("in"))
          target[parameter.fetch("name")] = value
        end

        unless arguments.empty?
          raise FlyIO::ArgumentError, "#{operation.ruby_method}: unknown keywords: #{arguments.keys.join(', ')}"
        end
        if operation.request_body&.fetch("required", false) && body.equal?(FlyIO::UNSET)
          raise FlyIO::ArgumentError, "#{operation.ruby_method}: body is required"
        end

        unless body.equal?(FlyIO::UNSET)
          SchemaValidator.validate!(operation.request_body&.dig("schema"), body, location: "body")
        end

        client.transport_for(operation).request(
          method: operation.http_method,
          path: operation.path,
          path_params: path_params,
          query: query,
          headers: operation_headers.merge(extra_headers),
          body: body,
          retry_unsafe: retry_unsafe,
          timeout: request_timeout,
          operation: operation
        )
      end
    end
  end
end
