# frozen_string_literal: true

require "json"

module FlyIO
  # Fly documents this control-plane GraphQL endpoint as internal and unstable.
  # Raw documents are first class; generated flyctl-observed operations live
  # behind #experimental and carry no compatibility guarantee.
  class GraphQLClient
    INTROSPECTION_PATTERN = /\b__(?:schema|type)\b/

    attr_reader :configuration, :transport

    def initialize(configuration = nil, **)
      @configuration = configuration || Configuration.new(**)
      graphql_configuration = @configuration.with(base_url: graphql_origin)
      @transport = Transport.new(graphql_configuration)
      freeze
    end

    def query(document:, variables: {}, operation_name: nil, headers: {}, timeout: nil,
              retry_unsafe: false, introspection: false)
      validate_document!(document, introspection)
      body = {"query" => String(document), "variables" => variables}
      body["operationName"] = operation_name if operation_name
      response = transport.request(method: :post, path: graphql_path, headers: headers, body: body,
                                   retry_unsafe: retry_unsafe, timeout: timeout)
      errors = response.body.is_a?(Hash) ? response.body["errors"] : nil
      if errors&.any?
        raise GraphQLError.new(graphql_errors: errors, status: response.status, headers: response.headers,
                               request_id: response.request_id, request: response.request)
      end

      response
    end

    alias execute query

    def introspect(document:, **)
      query(document: document, introspection: true, **)
    end

    def experimental
      ExperimentalGraphQL.new(self)
    end

    private

    def validate_document!(document, introspection)
      value = String(document)
      raise FlyIO::ArgumentError, "GraphQL document must not be empty" if value.strip.empty?
      return unless value.match?(INTROSPECTION_PATTERN)
      return if introspection && configuration.introspection

      raise FlyIO::ArgumentError,
            "GraphQL introspection requires Configuration(introspection: true) and introspection: true"
    end

    def graphql_path
      require "uri"
      uri = URI(configuration.graphql_url)
      if uri.query
        "#{uri.path}?#{uri.query}"
      else
        (uri.path.empty? ? "/" : uri.path)
      end
    end

    def graphql_origin
      uri = URI(configuration.graphql_url)
      uri.path = ""
      uri.query = nil
      uri.to_s
    end
  end

  class ExperimentalGraphQL
    MANIFEST_PATH = File.expand_path("generated/graphql_operations.json", __dir__)

    attr_reader :client

    def initialize(client)
      @client = client
      freeze
    end

    def operations
      self.class.operations
    end

    def execute(name, variables: {}, **)
      operation = operations.find { |entry| entry.fetch("name") == name.to_s }
      raise FlyIO::ArgumentError, "unknown experimental GraphQL operation: #{name}" unless operation

      client.query(document: operation.fetch("document"), operation_name: operation["operation_name"],
                   variables: variables, **)
    end

    def self.operations
      @operations ||= JSON.parse(File.read(MANIFEST_PATH)).fetch("operations").freeze
    end
  end
end
