# frozen_string_literal: true

RSpec.describe "additional documented Fly API surfaces" do
  let(:client) { FlyIO::Client.new(token: "surface-token", max_retries: 0) }

  it "covers all three official documentation-derived Network Policies operations" do
    operations = FlyIO::OperationRegistry.operations.select { |operation| operation.surface == "network_policies_rest" }
    expect(operations.map(&:operation_id)).to contain_exactly(
      "NetworkPolicies_upsert", "NetworkPolicies_list", "NetworkPolicies_delete"
    )

    create = stub_request(:post, "https://api.machines.dev/v1/apps/demo/network_policies").with(
      body: hash_including("name" => "web", "selector" => {"all" => true})
    ).to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: '{"id":"policy-1","future":true}')
    list = stub_request(:get, "https://api.machines.dev/v1/apps/demo/network_policies/")
           .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: "[]")
    delete = stub_request(:delete, "https://api.machines.dev/v1/apps/demo/network_policies/policy-1")
             .to_return(status: 204)

    response = client.network_policies.upsert(
      app_name: "demo",
      body: {name: "web", selector: {all: true}, rules: [{action: "allow", direction: "ingress", ports: []}]}
    )
    expect(response.body).to eq("id" => "policy-1", "future" => true)
    expect(client.network_policies.list(app_name: "demo").body).to eq([])
    expect(client.network_policies.delete(app_name: "demo", policy_id: "policy-1")).to be_no_content
    expect([create, list, delete]).to all(have_been_requested.once)
  end

  it "validates the documented Network Policy body before the network" do
    expect do
      client.network_policies.upsert(app_name: "demo", body: {name: "missing selector and rules"})
    end.to raise_error(FlyIO::ArgumentError, /selector is required/)
    expect(WebMock).not_to have_requested(:any, /network_policies/)
  end

  it "covers all seven documented Prometheus endpoint families using the metrics base URL" do
    operations = FlyIO::OperationRegistry.operations.select { |operation| operation.surface == "prometheus_metrics" }
    expect(operations.length).to eq(7)

    query = stub_request(:get, "https://api.fly.io/prometheus/personal/api/v1/query?query=up")
            .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: '{"status":"success","data":{"result":[]}}')
    labels = stub_request(:get, "https://api.fly.io/prometheus/personal/api/v1/labels?match%5B%5D=up&match%5B%5D=fly_app")
             .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: '{"status":"success","data":{}}')
    federate = stub_request(:get, "https://api.fly.io/prometheus/personal/federate?match%5B%5D=up")
               .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "up 1\n")

    response = client.metrics.query(org_slug: "personal", query: "up")
    expect(response.body).to be_a(FlyIO::Models::PrometheusAPIResponse)
    expect(response.status).to eq(200)
    expect(client.metrics.labels(org_slug: "personal", match: %w[up fly_app]).status).to eq(200)
    expect(client.metrics.federate(org_slug: "personal", match: ["up"]).body).to eq("up 1\n")
    expect([query, labels, federate]).to all(have_been_requested.once)
  end
end
