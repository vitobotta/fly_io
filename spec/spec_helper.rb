# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  minimum_coverage line: 90, branch: 80
end

require "fly_io"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: false)

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
