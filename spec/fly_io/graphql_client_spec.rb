# frozen_string_literal: true

RSpec.describe FlyIO::GraphQLClient do
  let(:configuration) { FlyIO::Configuration.new(token: "graphql-token", max_retries: 0) }
  let(:client) { described_class.new(configuration) }

  it "sends raw queries, variables, and operation names to the public GraphQL endpoint" do
    request = stub_request(:post, "https://api.fly.io/graphql").with do |incoming|
      body = JSON.parse(incoming.body)
      incoming.headers["Authorization"] == "Bearer graphql-token" &&
        body == {"query" => "query App($name: String!) { app(name: $name) { id } }",
                 "variables" => {"name" => "demo"}, "operationName" => "App"}
    end.to_return(
      status: 200,
      headers: {"Content-Type" => "application/json", "Fly-Request-Id" => "graphql-request"},
      body: '{"data":{"app":{"id":"app-id"}}}'
    )

    response = client.query(
      document: "query App($name: String!) { app(name: $name) { id } }",
      variables: {"name" => "demo"}, operation_name: "App"
    )
    expect(request).to have_been_requested.once
    expect(response.body.dig("data", "app", "id")).to eq("app-id")
    expect(response.request_id).to eq("graphql-request")
  end

  it "extracts and redacts GraphQL errors" do
    stub_request(:post, "https://api.fly.io/graphql").to_return(
      status: 200, headers: {"Content-Type" => "application/json"},
      body: '{"errors":[{"message":"denied","extensions":{"token":"server-secret"}}]}'
    )

    expect { client.execute(document: "query { viewer { id } }") }.to raise_error(FlyIO::GraphQLError) do |error|
      expect(error.graphql_errors).to eq([
                                           {"message" => "denied", "extensions" => {"token" => "[FILTERED]"}}
                                         ])
      expect(error.message).not_to include("server-secret", "graphql-token")
    end
  end

  it "keeps introspection double opt-in" do
    document = "query Introspection { __schema { queryType { name } } }"
    expect { client.query(document: document) }.to raise_error(FlyIO::ArgumentError, /introspection/)
    expect { client.introspect(document: document) }.to raise_error(FlyIO::ArgumentError, /introspection/)

    enabled = described_class.new(configuration.with(introspection: true))
    stub_request(:post, "https://api.fly.io/graphql").to_return(
      status: 200, headers: {"Content-Type" => "application/json"}, body: '{"data":{"__schema":{}}}'
    )
    expect(enabled.introspect(document: document).status).to eq(200)
  end

  it "rejects empty documents before making a request" do
    expect { client.query(document: "  ") }.to raise_error(FlyIO::ArgumentError, /empty/)
    expect(WebMock).not_to have_requested(:any, /graphql/)
  end

  it "exposes every flyctl, fly-go, and official example only through the experimental adapter" do
    operations = client.experimental.operations
    expect(operations.length).to eq(117)
    expect(operations).to all(include("stability" => "experimental"))
    expect(operations.count { |operation| operation["observed_in"] == "flyctl" }).to eq(29)
    expect(operations.count { |operation| operation["observed_in"] == "fly-go" }).to eq(85)
    expect(operations.count { |operation| operation["observed_in"] == "official_documentation" }).to eq(3)
    expect(operations.map { |operation| operation.fetch("name") }.uniq.length).to eq(117)
    operations.each do |operation|
      expect(operation.fetch("document")).to match(/\b(?:query|mutation)\b/)
      if operation["operation_name"]
        expect(operation.fetch("document")).to include(operation.fetch("operation_name"))
      end
    end
  end

  it "executes a named experimental operation and rejects unknown names" do
    operation = client.experimental.operations.find { |entry| entry["name"] == "official.allocate_shared_ipv4" }
    request = stub_request(:post, "https://api.fly.io/graphql").with do |incoming|
      JSON.parse(incoming.body).fetch("query") == operation.fetch("document")
    end.to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: '{"data":{}}')

    expect(client.experimental.execute("official.allocate_shared_ipv4",
                                       variables: {input: {appId: "demo"}}).status).to eq(200)
    expect(request).to have_been_requested.once
    expect { client.experimental.execute("missing") }.to raise_error(FlyIO::ArgumentError, /unknown/)
  end
end
