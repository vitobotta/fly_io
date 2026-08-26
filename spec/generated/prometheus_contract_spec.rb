# frozen_string_literal: true

require_relative "../support/contract_examples"

RSpec.describe "generated Prometheus compatibility contract" do
  let(:client) { FlyIO::Client.new(token: "metrics-token", max_retries: 0) }

  operations = FlyIO::OperationRegistry.operations.select { |operation| operation.surface == "prometheus_metrics" }

  it "represents every endpoint family listed in Fly's official metrics guide" do
    expect(operations.map(&:operation_id)).to contain_exactly(
      "Prometheus_query", "Prometheus_query_range", "Prometheus_series", "Prometheus_labels",
      "Prometheus_label_values", "Prometheus_tsdb", "Prometheus_federate"
    )
  end

  operations.each do |operation|
    describe operation.operation_id do
      let(:arguments) { ContractExamples.arguments_for(operation) }
      let(:path) { ContractExamples.expected_path(operation, arguments) }
      let(:query) { ContractExamples.expected_query(operation, arguments) }
      let(:url) { "https://api.fly.io#{path}#{"?#{query}" unless query.empty?}" }

      it "sends the exact documented path and standard parameters and parses its response" do
        response_contract = operation.responses.fetch("200")
        content_type, payload = ContractExamples.success_payload(response_contract)
        request = stub_request(:get, url).with(
          headers: {"Authorization" => "Bearer metrics-token", "Accept" => "application/json"}
        ).to_return(status: 200, headers: {"Content-Type" => content_type}, body: payload)

        response = client.metrics.public_send(operation.ruby_method, **arguments)
        expect(request).to have_been_requested.once
        expect(response.status).to eq(200)
        if content_type == "application/json"
          expect(response.body).to be_a(FlyIO::Models::PrometheusAPIResponse)
        else
          expect(response.body).to be_a(String)
        end
      end

      it "rejects each missing required parameter before a request" do
        operation.parameters.select { |parameter| parameter["required"] }.each do |parameter|
          invalid = arguments.reject { |name, _| name == parameter.fetch("ruby_name").to_sym }
          expect { client.metrics.public_send(operation.ruby_method, **invalid) }.to raise_error(FlyIO::ArgumentError)
        end
        expect(WebMock).not_to have_requested(:any, /api\.fly\.io/)
      end
    end
  end
end
