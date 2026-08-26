# frozen_string_literal: true

module FlyIO
  class Response
    attr_reader :status, :headers, :body, :raw_body, :request, :request_id

    def initialize(status:, headers:, body:, raw_body:, request:)
      @status = Integer(status)
      @headers = headers.freeze
      @body = body
      @raw_body = raw_body
      @request = request.freeze
      @request_id = headers["fly-request-id"] || headers["x-request-id"]
      freeze
    end

    alias data body

    def success?
      (200..299).cover?(status)
    end

    def accepted?
      status == 202
    end

    def no_content?
      status == 204
    end

    def [](key)
      body.respond_to?(:[]) ? body[key] : nil
    end

    def method_missing(name, *arguments)
      return body.public_send(name) if arguments.empty? && body.respond_to?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      body.respond_to?(name, include_private) || super
    end
  end
end
