# frozen_string_literal: true

module FlyIO
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ArgumentError < Error; end

  class APIError < Error
    attr_reader :status, :headers, :details, :request_id, :request

    def initialize(message = nil, status: nil, headers: {}, details: nil, request_id: nil, request: nil)
      @status = status
      @headers = headers.freeze
      @details = details
      @request_id = request_id
      @request = request
      super(Redactor.redact(message || default_message))
    end

    private

    def default_message
      ["Fly.io API request failed", ("(HTTP #{status})" if status),
       ("request_id=#{request_id}" if request_id)].compact.join(" ")
    end
  end

  class AuthenticationError < APIError; end
  class AuthorizationError < APIError; end
  class NotFoundError < APIError; end
  class ValidationError < APIError; end
  class RateLimitError < APIError; end
  class RequestTimeoutError < APIError; end
  class ServerError < APIError; end
  class TransportError < APIError; end

  class GraphQLError < APIError
    attr_reader :graphql_errors

    def initialize(message = "Fly.io GraphQL request failed", graphql_errors: [], **)
      @graphql_errors = Redactor.redact_object(graphql_errors)
      super(message, details: @graphql_errors, **)
    end
  end
end
