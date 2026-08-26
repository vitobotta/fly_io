# frozen_string_literal: true

require "uri"

module FlyIO
  class Configuration
    DEFAULT_BASE_URL = "https://api.machines.dev"
    DEFAULT_GRAPHQL_URL = "https://api.fly.io/graphql"

    ATTRIBUTES = %i[
      base_url graphql_url metrics_url authorization_value open_timeout read_timeout write_timeout request_timeout
      proxy user_agent max_retries base_retry_interval max_retry_interval retry_jitter logger adapter
      sleeper random retry_unsafe introspection
    ].freeze

    attr_reader(*ATTRIBUTES)

    def initialize(token: nil, authorization: nil, authorization_mode: :bearer,
                   base_url: DEFAULT_BASE_URL, graphql_url: DEFAULT_GRAPHQL_URL, metrics_url: "https://api.fly.io",
                   open_timeout: 10, read_timeout: 30, write_timeout: 30, request_timeout: nil,
                   proxy: nil, user_agent: "fly_io/#{FlyIO::VERSION}", max_retries: 2,
                   base_retry_interval: 0.25, max_retry_interval: 5.0, retry_jitter: 0.25,
                   logger: nil, adapter: nil, sleeper: ->(seconds) { sleep(seconds) },
                   random: Random.new, retry_unsafe: false, introspection: false)
      @base_url = normalize_url(base_url, "base_url")
      @graphql_url = normalize_url(graphql_url, "graphql_url")
      @metrics_url = normalize_url(metrics_url, "metrics_url")
      @authorization_value = build_authorization(token, authorization, authorization_mode)
      @open_timeout = positive_number(open_timeout, "open_timeout")
      @read_timeout = positive_number(read_timeout, "read_timeout")
      @write_timeout = positive_number(write_timeout, "write_timeout")
      @request_timeout = request_timeout && positive_number(request_timeout, "request_timeout")
      @proxy = proxy
      @user_agent = String(user_agent).dup.freeze
      @max_retries = Integer(max_retries)
      @base_retry_interval = Float(base_retry_interval)
      @max_retry_interval = Float(max_retry_interval)
      @retry_jitter = Float(retry_jitter)
      @logger = logger
      @adapter = adapter
      @sleeper = sleeper
      @random = random
      @retry_unsafe = retry_unsafe
      @introspection = introspection
      validate_retry!
      freeze
    end

    def with(**overrides)
      current = ATTRIBUTES.to_h { |name| [name, public_send(name)] }
      authorization_value = current.delete(:authorization_value)
      current[:authorization] = authorization_value
      self.class.new(**current, **overrides)
    end

    private

    def build_authorization(token, authorization, mode)
      if token && authorization
        raise ConfigurationError, "provide token or authorization, not both"
      end

      if authorization
        value = String(authorization).strip
        raise ConfigurationError, "authorization must include a scheme and value" unless value.match?(/\A\S+\s+\S+/)

        return value.freeze
      end

      raw = String(token || "").strip
      raise ConfigurationError, "token is required" if raw.empty?
      if raw.match?(/\A(?:Bearer|FlyV1)\s+/i)
        raise ConfigurationError,
              "token must be raw; use authorization: for a preformatted value"
      end

      scheme = {bearer: "Bearer", fly_v1: "FlyV1"}.fetch(mode.to_sym) do
        raise ConfigurationError, "authorization_mode must be :bearer or :fly_v1"
      end
      "#{scheme} #{raw}".freeze
    end

    def normalize_url(value, name)
      uri = URI.parse(String(value))
      raise ConfigurationError, "#{name} must be an absolute HTTP(S) URL" unless %w[http
                                                                                    https].include?(uri.scheme) && uri.host
      if uri.userinfo || uri.query || uri.fragment
        raise ConfigurationError,
              "#{name} must not contain credentials, query, or fragment"
      end

      uri.path = uri.path.sub(%r{/+\z}, "")
      uri.to_s.freeze
    rescue URI::InvalidURIError
      raise ConfigurationError, "#{name} must be a valid URL"
    end

    def positive_number(value, name)
      number = Float(value)
      raise ConfigurationError, "#{name} must be positive" unless number.positive?

      number
    end

    def validate_retry!
      raise ConfigurationError, "max_retries must be non-negative" if max_retries.negative?
      raise ConfigurationError, "retry intervals and jitter must be non-negative" if [base_retry_interval,
                                                                                      max_retry_interval, retry_jitter].any?(&:negative?)
      return unless max_retry_interval < base_retry_interval

      raise ConfigurationError,
            "max_retry_interval must be at least base_retry_interval"
    end
  end
end
