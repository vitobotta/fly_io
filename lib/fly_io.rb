# frozen_string_literal: true

require_relative "fly_io/version"
require_relative "fly_io/errors"
require_relative "fly_io/redactor"
require_relative "fly_io/configuration"
require_relative "fly_io/model"
require_relative "fly_io/schema_registry"
require_relative "fly_io/schema_validator"
require_relative "fly_io/response"
require_relative "fly_io/operation_registry"
require_relative "fly_io/transport"
require_relative "fly_io/resources/base"
require_relative "fly_io/resources"
require_relative "fly_io/client"
require_relative "fly_io/graphql_client"

module FlyIO
  UNSET = Object.new.freeze

  SchemaRegistry.install_model_constants!
  Resources.install!
end
