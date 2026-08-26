# frozen_string_literal: true

require "faraday"
require "json"
require "time"
require "uri"

module FlyIO
  class Transport
    METHODS = %i[get head options post put patch delete].freeze
    SAFE_METHODS = %i[get head options].freeze
    RETRYABLE_STATUSES = [408, 429, 500, 502, 503, 504].freeze
    ERROR_CLASSES = {
      400 => ValidationError,
      401 => AuthenticationError,
      403 => AuthorizationError,
      404 => NotFoundError,
      408 => RequestTimeoutError,
      409 => ValidationError,
      410 => NotFoundError,
      412 => ValidationError,
      422 => ValidationError,
      429 => RateLimitError
    }.freeze

    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
      @connection = build_connection unless configuration.adapter.respond_to?(:call)
      freeze
    end

    def request(method:, path:, path_params: {}, query: {}, headers: {}, body: FlyIO::UNSET,
                content_type: "application/json", accept: "application/json", retry_unsafe: nil, operation: nil,
                timeout: nil)
      verb = validate_method(method)
      expanded_path = build_path(path, path_params)
      url = absolute_url(build_url(expanded_path, query))
      request_headers = default_headers(accept).merge(stringify_keys(headers))
      encoded_body = encode_body(body, content_type, request_headers)
      metadata = safe_request_metadata(verb, expanded_path, query, request_headers, body, operation)
      attempts = 0

      loop do
        begin
          raw_response = perform(verb, url, request_headers, encoded_body, timeout)
        rescue Faraday::TimeoutError
          if attempts < configuration.max_retries && retry_allowed?(verb, retry_unsafe)
            configuration.sleeper.call(retry_delay(attempts, {}))
            attempts += 1
            next
          end
          raise RequestTimeoutError.new("Fly.io API request timed out", request: metadata)
        rescue Faraday::ConnectionFailed, Faraday::SSLError => e
          if attempts < configuration.max_retries && retry_allowed?(verb, retry_unsafe)
            configuration.sleeper.call(retry_delay(attempts, {}))
            attempts += 1
            next
          end
          raise TransportError.new("Fly.io API transport failed: #{e.class}", request: metadata)
        end
        if retry_status?(raw_response.status, verb, retry_unsafe) && attempts < configuration.max_retries
          delay = retry_delay(attempts, raw_response.headers)
          attempts += 1
          configuration.sleeper.call(delay)
          next
        end
        response = build_response(raw_response, metadata, operation)
        raise_api_error(response) unless response.success?

        log(:debug, "Fly.io API #{verb.to_s.upcase} #{expanded_path} -> #{response.status}", metadata)
        return response
      end
    end

    def build_path(template, path_params = {})
      value = String(template)
      raise FlyIO::ArgumentError, "path must start with /" unless value.start_with?("/")
      if value.match?(%r{\A//|[?#\\\x00]})
        raise FlyIO::ArgumentError,
              "path must not contain a URL, query, fragment, backslash, or NUL"
      end

      provided = stringify_keys(path_params)
      result = value.gsub(/\{([^}]+)\}/) do
        name = Regexp.last_match(1)
        raise FlyIO::ArgumentError, "missing required path parameter: #{name}" unless provided.key?(name)

        escape_path_component(provided.fetch(name), name)
      end
      unused = provided.keys - value.scan(/\{([^}]+)\}/).flatten
      raise FlyIO::ArgumentError, "unknown path parameters: #{unused.join(', ')}" unless unused.empty?
      if result.split("/").any? { |segment| [".", ".."].include?(URI.decode_www_form_component(segment)) }
        raise FlyIO::ArgumentError, "path traversal segments are not allowed"
      end

      result
    rescue URI::InvalidURIError, ::ArgumentError
      raise FlyIO::ArgumentError, "path contains invalid encoding"
    end

    private

    def build_connection
      Faraday.new(url: configuration.base_url, proxy: configuration.proxy) do |faraday|
        faraday.options.open_timeout = configuration.open_timeout
        faraday.options.timeout = configuration.request_timeout || configuration.read_timeout
        faraday.options.read_timeout = configuration.read_timeout if faraday.options.respond_to?(:read_timeout=)
        faraday.options.write_timeout = configuration.write_timeout if faraday.options.respond_to?(:write_timeout=)
        faraday.adapter(configuration.adapter || Faraday.default_adapter)
      end
    end

    def validate_method(method)
      value = method.to_s.downcase.to_sym
      raise FlyIO::ArgumentError, "unsupported HTTP method: #{method}" unless METHODS.include?(value)

      value
    end

    def escape_path_component(value, name)
      string = String(value)
      raise FlyIO::ArgumentError, "path parameter #{name} must not be empty" if string.empty?
      raise FlyIO::ArgumentError, "path parameter #{name} contains NUL" if string.include?("\0")

      URI.encode_www_form_component(string).gsub("+", "%20")
    end

    def build_url(path, query)
      pairs = query_pairs(query)
      pairs.empty? ? path : "#{path}?#{URI.encode_www_form(pairs)}"
    end

    def absolute_url(relative_url)
      base = URI.parse(configuration.base_url)
      relative = URI.parse(relative_url)
      base_path = base.path.to_s.sub(%r{/+\z}, "")
      base.path = "#{base_path}/#{relative.path.delete_prefix('/')}"
      base.query = relative.query
      base.to_s
    end

    def query_pairs(query)
      raise FlyIO::ArgumentError, "query must be a Hash" unless query.is_a?(Hash)

      query.each_with_object([]) do |(key, value), pairs|
        next if value.nil?

        values = value.is_a?(Array) ? value : [value]
        values.each { |item| pairs << [key.to_s, query_value(item)] unless item.nil? }
      end
    end

    def query_value(value)
      case value
      when true then "true"
      when false then "false"
      else String(value)
      end
    end

    def default_headers(accept)
      {
        "Accept" => accept,
        "Authorization" => configuration.authorization_value,
        "User-Agent" => configuration.user_agent
      }
    end

    def encode_body(body, content_type, headers)
      return nil if body.equal?(FlyIO::UNSET)

      headers["Content-Type"] ||= content_type
      serializable = serialize(body)
      content_type.to_s.downcase.include?("json") ? JSON.generate(serializable) : serializable
    end

    def serialize(value)
      case value
      when Model then value.to_h
      when Array then value.map { |item| serialize(item) }
      when Hash then value.transform_keys(&:to_s).transform_values { |item| serialize(item) }
      else value
      end
    end

    def perform(method, url, headers, body, timeout)
      if configuration.adapter.respond_to?(:call)
        return configuration.adapter.call(method: method, url: url,
                                          headers: headers, body: body, timeout: timeout)
      end

      @connection.run_request(method, url, body, headers) do |request|
        request.options.timeout = timeout if timeout
      end
    end

    def build_response(raw_response, request, operation)
      status = Integer(raw_response.status)
      headers = stringify_keys(raw_response.headers).transform_keys(&:downcase)
      raw_body = raw_response.body
      content_type = headers.fetch("content-type", "").downcase
      parsed = parse_body(raw_body, content_type, status)
      schema = operation&.response_schema(status, content_type)
      body = schema ? SchemaRegistry.coerce(schema, parsed) : parsed
      Response.new(status: status, headers: headers, body: body, raw_body: raw_body, request: request)
    end

    def parse_body(body, content_type, status)
      return nil if status == 204 || body.nil? || body == ""
      return body unless content_type.include?("json")

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    def raise_api_error(response)
      klass = ERROR_CLASSES[response.status] || (response.status >= 500 ? ServerError : APIError)
      details = Redactor.redact_object(response.body)
      message = error_message(response.status, details, response.request_id)
      raise klass.new(message, status: response.status, headers: safe_headers(response.headers), details: details,
                               request_id: response.request_id, request: response.request)
    end

    def error_message(status, details, request_id)
      server_message = details.is_a?(Hash) && (details["error"] || details["message"])
      ["Fly.io API request failed (HTTP #{status})", server_message,
       ("request_id=#{request_id}" if request_id)].compact.join(": ")
    end

    def retry_status?(status, method, retry_unsafe)
      RETRYABLE_STATUSES.include?(Integer(status)) && retry_allowed?(method, retry_unsafe)
    end

    def retry_allowed?(method, retry_unsafe)
      SAFE_METHODS.include?(method) || retry_unsafe == true || (retry_unsafe.nil? && configuration.retry_unsafe)
    end

    def retry_delay(attempt, headers)
      retry_after = stringify_keys(headers).find { |key, _| key.downcase == "retry-after" }&.last
      parsed = parse_retry_after(retry_after)
      return [parsed, configuration.max_retry_interval].min if parsed

      base = [configuration.base_retry_interval * (2**attempt), configuration.max_retry_interval].min
      [base + (base * configuration.retry_jitter * configuration.random.rand), configuration.max_retry_interval].min
    end

    def parse_retry_after(value)
      return if value.nil?
      return [Float(value), 0].max if value.to_s.match?(/\A\d+(?:\.\d+)?\z/)

      [Time.httpdate(value.to_s) - Time.now, 0].max
    rescue ::ArgumentError
      nil
    end

    def safe_request_metadata(method, path, query, headers, body, operation)
      {
        method: method,
        path: path,
        query: Redactor.redact_object(query),
        headers: safe_headers(headers),
        body: Redactor.redact_object(body.equal?(FlyIO::UNSET) ? nil : serialize(body)),
        operation_id: operation&.operation_id
      }.freeze
    end

    def safe_headers(headers)
      Redactor.redact_object(stringify_keys(headers))
    end

    def stringify_keys(hash)
      hash.to_h.transform_keys(&:to_s)
    end

    def log(level, message, metadata)
      configuration.logger&.public_send(level, "#{message} #{metadata.inspect}")
    end
  end
end
