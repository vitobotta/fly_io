# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ["--cache-root", "tmp/rubocop_cache", "--no-server"]
end

namespace :api do
  desc "Verify generated API coverage and committed contract outputs"
  task :check do
    sh RbConfig.ruby, "script/check_api_coverage"
  end

  desc "Fetch the upstream OpenAPI and fail if it differs from the snapshot"
  task :fetch_check do
    sh RbConfig.ruby, "script/fetch_openapi"
  end

  desc "Regenerate API metadata and documentation"
  task :generate do
    sh RbConfig.ruby, "script/generate_api"
  end
end

desc "Run offline quality checks"
task default: ["api:check", :spec, :rubocop]
