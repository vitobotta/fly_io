# frozen_string_literal: true

RSpec.describe FlyIO::Client do
  let(:client) { described_class.new(token: "client-token", max_retries: 0) }

  it "exposes every stable resource family and safely shares immutable configuration" do
    expect(client.configuration).to be_frozen
    expect(client.apps).to be_a(FlyIO::Resources::Apps)
    expect(client.machines).to be_a(FlyIO::Resources::Machines)
    expect(client.certificates).to be_a(FlyIO::Resources::Certificates)
    expect(client.secrets).to be_a(FlyIO::Resources::Secrets)
    expect(client.volumes).to be_a(FlyIO::Resources::Volumes)
    expect(client.postgres_clusters).to be_a(FlyIO::Resources::PostgresClusters)
    expect(client.tokens).to be_a(FlyIO::Resources::Tokens)
    expect(client.organizations).to be_a(FlyIO::Resources::Organizations)
    expect(client.platform).to be_a(FlyIO::Resources::Platform)
    expect(client.network_policies).to be_a(FlyIO::Resources::NetworkPolicies)
    expect(client.metrics).to be_a(FlyIO::Resources::Metrics)
  end

  it "provides readable generated methods for every high-risk resource area" do
    expected = {
      apps: %i[create destroy create_deploy_token list_ip_assignments],
      machines: %i[create update destroy start stop restart cordon wait events execute lease signal memory metadata
                   processes],
      secrets: %i[list set delete list_keys encrypt_key decrypt_key sign_key verify_key generate_key],
      volumes: %i[create update destroy extend list_snapshots create_snapshot],
      certificates: %i[request_acme upload_custom check remove_acme remove_custom],
      postgres_clusters: %i[create attachments_create backups_create databases_create extensions_enable users_create
                            users_credentials users_rotate_password],
      tokens: %i[authenticate authorize current request_kms request_oidc],
      organizations: %i[list_machines list_volumes],
      platform: %i[placements regions]
    }

    expected.each do |resource, methods|
      expect(client.public_send(resource).public_methods).to include(*methods)
    end
  end

  it "includes a selected network when destroying an app" do
    request = stub_request(
      :delete,
      "https://api.machines.dev/v1/apps/demo?network=customer%20%2F%20%C3%BC"
    ).to_return(status: 202)

    response = client.apps.destroy(app_name: "demo", network: "customer / ü")

    expect(request).to have_been_requested.once
    expect(response.status).to eq(202)
  end

  it "does not add a network query when none is selected" do
    request = stub_request(:delete, "https://api.machines.dev/v1/apps/demo").to_return(status: 202)

    client.apps.destroy(app_name: "demo")

    expect(request).to have_been_requested.once
  end

  it "validates a selected network before deleting an app" do
    expect { client.apps.destroy(app_name: "demo", network: 123) }
      .to raise_error(FlyIO::ArgumentError, /network must be string/)
    expect(WebMock).not_to have_requested(:delete, /api\.machines\.dev/)
  end

  it "executes the one-to-one operation ID escape hatch and handles the upstream duplicate explicitly" do
    stub_request(:get, "https://api.machines.dev/v1/apps/demo").to_return(
      status: 200, headers: {"Content-Type" => "application/json"}, body: '{"name":"demo"}'
    )

    response = client.operation("Apps_show", app_name: "demo")
    expect(response).to be_a(FlyIO::Response)
    expect(response.body).to be_a(FlyIO::Models::App)
    expect(response.name).to eq("demo")

    expect { client.operation("Machines_update_metadata", app_name: "a", machine_id: "m", body: {}) }
      .to raise_error(FlyIO::ArgumentError, /ambiguous/)
  end

  it "supports a safe low-level request with path parameters and consistent responses" do
    request = stub_request(:get, "https://api.machines.dev/v1/apps/name%20%2F%C3%BC/machines?state=started")
              .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: "[]")

    response = client.request(
      method: :get,
      path: "/v1/apps/{app_name}/machines",
      path_params: {app_name: "name /ü"},
      query: {state: "started"}
    )
    expect(request).to have_been_requested.once
    expect(response.body).to eq([])
  end

  it "rejects mixed Configuration and keyword construction" do
    configuration = FlyIO::Configuration.new(token: "x")
    expect { described_class.new(configuration, token: "x") }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(Object.new) }.to raise_error(FlyIO::ConfigurationError)
  end

  it "is safe for concurrent callers because per-request state is local" do
    stub_request(:get, %r{https://api\.machines\.dev/v1/apps/app-\d+}).to_return(
      status: 200, headers: {"Content-Type" => "application/json"}, body: "{}"
    )
    threads = 10.times.map do |index|
      Thread.new { client.apps.get(app_name: "app-#{index}").status }
    end
    expect(threads.map(&:value)).to eq(Array.new(10, 200))
  end
end
