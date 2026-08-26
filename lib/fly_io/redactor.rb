# frozen_string_literal: true

module FlyIO
  module Redactor
    FILTERED = "[FILTERED]"
    SENSITIVE_KEYS = /authorization|token|secret|password|credential|private.?key|certificate/i
    AUTHORIZATION_VALUE = %r{\b(?:Bearer|FlyV1)\s+[A-Za-z0-9._~+/=:-]+}i

    module_function

    def redact(value)
      value.to_s.gsub(AUTHORIZATION_VALUE) { |match| "#{match.split.first} #{FILTERED}" }
    end

    def redact_object(value, key = nil)
      return FILTERED if key&.match?(SENSITIVE_KEYS)

      case value
      when Model
        redact_object(value.to_h, key)
      when Hash
        value.each_with_object({}) do |(child_key, child), result|
          result[child_key] = redact_object(child, child_key.to_s)
        end
      when Array
        value.map { |child| redact_object(child) }
      when String
        redact(value)
      else
        value
      end
    end
  end
end
