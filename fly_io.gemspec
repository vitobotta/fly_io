# frozen_string_literal: true

require_relative "lib/fly_io/version"

Gem::Specification.new do |spec|
  spec.name = "fly_io"
  spec.version = FlyIO::VERSION
  spec.authors = ["Vito Botta"]
  spec.email = ["vito@botta.me"]

  spec.summary = "A contract-driven Ruby client for Fly.io control-plane APIs"
  spec.description = <<~DESCRIPTION
    A typed, generated-contract Ruby client for the complete Fly Machines REST
    API, plus a clearly isolated experimental client for Fly's unstable GraphQL
    control-plane interface.
  DESCRIPTION
  spec.homepage = "https://github.com/vitobotta/fly_io"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}/blob/main/docs/API.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob("{lib,docs,contracts,script}/**/*", File::FNM_DOTMATCH) +
               %w[README.md CHANGELOG.md LICENSE CONTRIBUTING.md Rakefile]
  spec.bindir = "exe"
  spec.executables = []
  spec.require_paths = ["lib"]

  # Faraday supplies a maintained, adapter-injectable HTTP foundation without
  # coupling the gem to Rails or a global HTTP stack.
  spec.add_dependency "faraday", ">= 2.9", "< 3"

  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.80"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "webmock", "~> 3.25"
end
