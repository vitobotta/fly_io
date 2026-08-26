# frozen_string_literal: true

module FlyIO
  class Client
    RESOURCE_NAMES = %w[apps certificates machines secrets volumes organizations platform postgres_clusters tokens
                        network_policies metrics].freeze

    attr_reader :configuration, :transport

    def initialize(configuration = nil, **options)
      if configuration && !options.empty?
        raise ConfigurationError, "provide a Configuration or keyword options, not both"
      end

      @configuration = configuration || Configuration.new(**options)
      unless @configuration.is_a?(Configuration)
        raise ConfigurationError,
              "configuration must be a FlyIO::Configuration"
      end

      @transport = Transport.new(@configuration)
      @metrics_transport = Transport.new(@configuration.with(base_url: @configuration.metrics_url))
      @resources = RESOURCE_NAMES.to_h do |name|
        [name, Resources.class_for(name).new(self)]
      end.freeze
      freeze
    end

    RESOURCE_NAMES.each do |name|
      define_method(name) { @resources.fetch(name) }
    end

    def graphql
      GraphQLClient.new(configuration)
    end

    def transport_for(operation)
      operation.surface == "prometheus_metrics" ? @metrics_transport : transport
    end

    def request(method:, path:, path_params: {}, query: {}, headers: {}, body: FlyIO::UNSET,
                content_type: "application/json", accept: "application/json", retry_unsafe: nil, timeout: nil)
      transport.request(method: method, path: path, path_params: path_params, query: query, headers: headers,
                        body: body, content_type: content_type, accept: accept, retry_unsafe: retry_unsafe, timeout: timeout)
    end

    def operation(operation_id, method: nil, path: nil, **arguments)
      operation = OperationRegistry.fetch(operation_id, method: method, path: path)
      @resources.fetch(operation.ruby_resource).operation(operation_id, method: method, path: path, **arguments)
    end
  end
end
