# frozen_string_literal: true

require_relative "../support/contract_examples"

RSpec.describe "generated Machines OpenAPI contract" do
  let(:configuration) { FlyIO::Configuration.new(token: "test-token", max_retries: 0) }
  let(:client) { FlyIO::Client.new(configuration) }

  spec_document = JSON.parse(File.read(File.expand_path("../../contracts/machines/openapi.json", __dir__)))
  machine_operations = FlyIO::OperationRegistry.operations.select { |operation| operation.surface == "machines_rest" }

  it "pins a valid OpenAPI 3 document with every local reference resolved" do
    expect(spec_document.fetch("openapi")).to start_with("3.")
    schemas = spec_document.dig("components", "schemas")
    references = JSON.generate(spec_document).scan(%r{#/components/schemas/[^"\\]+})
    expect(references).not_to be_empty
    expect(references.map { |reference| reference.delete_prefix("#/components/schemas/") } - schemas.keys).to be_empty
  end

  it "maps every method/path pair exactly once and represents every used resource family" do
    expected = spec_document.fetch("paths").flat_map do |path, item|
      item.keys.grep(/\A(?:get|put|post|delete|patch|options|head|trace)\z/).map { |method| [method, path] }
    end
    actual = machine_operations.map { |operation| [operation.http_method, operation.path] }
    expect(actual).to match_array(expected)
    expect(actual.uniq.length).to eq(actual.length)
    openapi_resources = FlyIO::Client::RESOURCE_NAMES - %w[network_policies metrics]
    expect(machine_operations.map(&:ruby_resource).uniq).to include(*openapi_resources)
  end

  it "maps all 173 schemas to collision-free typed Ruby model classes" do
    expected = spec_document.dig("components", "schemas").keys
    classes = expected.map { |name| FlyIO::SchemaRegistry.schemas.fetch(name).fetch("x-ruby-class") }
    expect(classes.uniq.length).to eq(173)
    expect(classes).to all(satisfy { |name| FlyIO::Models.const_get(name) < FlyIO::Model })
  end

  machine_operations.each do |operation|
    describe "#{operation.operation_id} (#{operation.http_method.upcase} #{operation.path})" do
      let(:arguments) { ContractExamples.arguments_for(operation) }
      let(:path) { ContractExamples.expected_path(operation, arguments) }
      let(:query) { ContractExamples.expected_query(operation, arguments) }
      let(:url) { "https://api.machines.dev#{path}#{"?#{query}" unless query.empty?}" }
      let(:resource) { client.public_send(operation.ruby_resource) }

      operation.responses.select { |status, _| status.start_with?("2") }.each do |status, response_contract|
        it "sends the exact contract request and parses documented success #{status}" do
          content_type, payload = ContractExamples.success_payload(response_contract)
          response_headers = content_type ? {"Content-Type" => content_type, "Fly-Request-Id" => "request-123"} : {}
          request_stub = stub_request(operation.http_method.to_sym, url)
                         .with(headers: {"Authorization" => "Bearer test-token", "Accept" => "application/json"})
                         .to_return(status: status.to_i, headers: response_headers, body: payload)

          response = resource.public_send(operation.ruby_method, **arguments)

          expect(request_stub).to have_been_requested.once
          expect(response.status).to eq(status.to_i)
          expect(response.request_id).to eq("request-123") if content_type
          if operation.request_body
            expect(a_request(operation.http_method.to_sym, url).with do |request|
              request.headers["Content-Type"] == "application/json" && JSON.parse(request.body) == arguments.fetch(:body)
            end).to have_been_made.once
          end
          operation.parameters.select { |parameter| parameter["in"] == "header" }.each do |parameter|
            expected = arguments.fetch(parameter.fetch("ruby_name").to_sym).to_s
            expect(a_request(operation.http_method.to_sym, url).with(headers: {parameter.fetch("name") => expected}))
              .to have_been_made.once
          end
          expect(response.body).to be_nil if status == "204"
        end
      end

      error_responses = operation.responses.reject { |status, _| status.start_with?("2") }
      unless error_responses.empty?
        it "maps every documented error status to a safe typed exception" do
          error_responses.each_key do |status|
            stub_request(operation.http_method.to_sym, url).to_return(
              status: status.to_i,
              headers: {"Content-Type" => "application/json", "Fly-Request-Id" => "error-request"},
              body: JSON.generate("error" => "contract failure")
            )

            expected_class = {
              "400" => FlyIO::ValidationError, "401" => FlyIO::AuthenticationError,
              "404" => FlyIO::NotFoundError, "408" => FlyIO::RequestTimeoutError,
              "409" => FlyIO::ValidationError, "410" => FlyIO::NotFoundError,
              "412" => FlyIO::ValidationError, "422" => FlyIO::ValidationError,
              "429" => FlyIO::RateLimitError
            }.fetch(status, status.to_i >= 500 ? FlyIO::ServerError : FlyIO::APIError)
            expect { resource.public_send(operation.ruby_method, **arguments) }
              .to raise_error(expected_class) do |error|
                expect(error.status).to eq(status.to_i)
                expect(error.request_id).to eq("error-request")
                expect(error.details).to eq("error" => "contract failure")
                expect(error.message).not_to include("test-token")
              end
          end
        end
      end

      if operation.request_body&.fetch("required", false)
        it "rejects a missing required body before making a request" do
          arguments.delete(:body)
          expect do
            resource.public_send(operation.ruby_method, **arguments)
          end.to raise_error(FlyIO::ArgumentError, /body/)
          expect(WebMock).not_to have_requested(:any, /api\.machines\.dev/)
        end
      end

      required = operation.parameters.find { |parameter| parameter["required"] }
      if required
        it "rejects a missing required argument before making a request" do
          arguments.delete(required.fetch("ruby_name").to_sym)
          expect { resource.public_send(operation.ruby_method, **arguments) }.to raise_error(FlyIO::ArgumentError)
          expect(WebMock).not_to have_requested(:any, /api\.machines\.dev/)
        end
      elsif operation.request_body&.fetch("required", false)
        it "rejects a missing required body before making a request" do
          arguments.delete(:body)
          expect { resource.public_send(operation.ruby_method, **arguments) }.to raise_error(FlyIO::ArgumentError)
          expect(WebMock).not_to have_requested(:any, /api\.machines\.dev/)
        end
      end
    end
  end
end
