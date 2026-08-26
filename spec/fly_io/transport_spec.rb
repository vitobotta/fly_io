# frozen_string_literal: true

require "logger"
require "stringio"

RSpec.describe FlyIO::Transport do
  def configuration(**overrides)
    FlyIO::Configuration.new(token: "transport-token", max_retries: 0, **overrides)
  end

  def transport(**overrides)
    described_class.new(configuration(**overrides))
  end

  it "escapes supplied path components and encodes scalar, repeated, boolean, numeric, nil, and Unicode query values" do
    request = stub_request(
      :get,
      "https://api.machines.dev/v1/apps/name%20%2F%C3%BC/machines?flag=true&ids=one&ids=two&number=3&text=a+%C3%BC"
    ).to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: "{}")

    response = transport.request(
      method: :get,
      path: "/v1/apps/{app}/machines",
      path_params: {app: "name /ü"},
      query: {flag: true, ids: %w[one two], number: 3, omitted: nil, text: "a ü"}
    )

    expect(request).to have_been_requested.once
    expect(response.body).to eq({})
    expect(response.request).not_to include("Authorization")
  end

  it "joins configured base-path prefixes without double slashes or dropping the prefix" do
    request = stub_request(:get, "https://example.test/prefix/v1/apps")
              .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: "[]")

    response = transport(base_url: "https://example.test/prefix/").request(method: :get, path: "/v1/apps")
    expect(request).to have_been_requested.once
    expect(response.body).to eq([])
  end

  it "validates methods, paths, path parameters, traversal, and query shape before a request" do
    subject = transport
    expect { subject.request(method: :connect, path: "/v1") }.to raise_error(FlyIO::ArgumentError, /method/)
    expect { subject.request(method: :get, path: "v1") }.to raise_error(FlyIO::ArgumentError, /start/)
    expect { subject.request(method: :get, path: "//evil.test/x") }.to raise_error(FlyIO::ArgumentError)
    expect { subject.request(method: :get, path: "/v1?secret=x") }.to raise_error(FlyIO::ArgumentError)
    expect { subject.request(method: :get, path: "/v1/{id}") }.to raise_error(FlyIO::ArgumentError, /missing/)
    expect do
      subject.request(method: :get, path: "/v1", path_params: {id: "x"})
    end.to raise_error(FlyIO::ArgumentError, /unknown/)
    expect do
      subject.request(method: :get, path: "/v1/{id}",
                      path_params: {id: ".."})
    end.to raise_error(FlyIO::ArgumentError, /traversal/)
    expect { subject.request(method: :get, path: "/v1", query: []) }.to raise_error(FlyIO::ArgumentError, /Hash/)
    expect(WebMock).not_to have_requested(:any, /api\.machines\.dev/)
  end

  it "serializes model bodies and parses JSON, malformed JSON, text, binary, and empty responses safely" do
    subject = transport
    stub_request(:post, "https://api.machines.dev/json").with(body: '{"id":"app"}')
                                                        .to_return(
                                                          status: 201,
                                                          headers: {"Content-Type" => "application/json"},
                                                          body: '{"ok":true}'
                                                        )
    stub_request(:get, "https://api.machines.dev/malformed")
      .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: "{bad")
    stub_request(:get, "https://api.machines.dev/text")
      .to_return(status: 200, headers: {"Content-Type" => "text/plain"}, body: "hello")
    stub_request(:get, "https://api.machines.dev/binary")
      .to_return(status: 200, headers: {"Content-Type" => "application/octet-stream"}, body: "\x00data".b)
    stub_request(:delete, "https://api.machines.dev/empty").to_return(status: 204, body: "ignored")

    expect(subject.request(method: :post, path: "/json",
                           body: FlyIO::Models::App.new("id" => "app")).body).to eq("ok" => true)
    expect(subject.request(method: :get, path: "/malformed").body).to eq("{bad")
    expect(subject.request(method: :get, path: "/text", accept: "text/plain").body).to eq("hello")
    expect(subject.request(method: :get, path: "/binary", accept: "application/octet-stream").body).to eq("\x00data".b)
    expect(subject.request(method: :delete, path: "/empty")).to be_no_content
  end

  it "returns accepted responses and exposes safe request/correlation metadata" do
    stub_request(:post, "https://api.machines.dev/job").to_return(
      status: 202, headers: {"X-Request-Id" => "correlation"}, body: ""
    )
    response = transport.request(method: :post, path: "/job", body: {name: "job"})
    expect(response).to be_accepted
    expect(response).to be_success
    expect(response.request_id).to eq("correlation")
    expect(response.raw_body).to eq("")
  end

  it "maps authentication, authorization, not-found, validation, rate-limit, timeout, and server statuses" do
    mappings = {
      400 => FlyIO::ValidationError, 401 => FlyIO::AuthenticationError, 403 => FlyIO::AuthorizationError,
      404 => FlyIO::NotFoundError,
      408 => FlyIO::RequestTimeoutError, 409 => FlyIO::ValidationError, 410 => FlyIO::NotFoundError,
      412 => FlyIO::ValidationError, 422 => FlyIO::ValidationError, 429 => FlyIO::RateLimitError,
      500 => FlyIO::ServerError, 418 => FlyIO::APIError
    }
    subject = transport
    mappings.each do |status, error_class|
      stub_request(:get, "https://api.machines.dev/status/#{status}").to_return(
        status: status, headers: {"Content-Type" => "application/json"}, body: '{"message":"failure"}'
      )
      expect { subject.request(method: :get, path: "/status/#{status}") }.to raise_error(error_class)
    end
  end

  it "retries safe requests with bounded exponential jitter and honors Retry-After" do
    sleeps = []
    random = instance_double(Random, rand: 0.5)
    subject = transport(max_retries: 2, base_retry_interval: 1, max_retry_interval: 10, retry_jitter: 0.2,
                        sleeper: ->(delay) { sleeps << delay }, random: random)
    request = stub_request(:get, "https://api.machines.dev/retry")
              .to_return({status: 503, headers: {"Retry-After" => "2"}}, {status: 500}, {status: 200, body: "ok"})

    expect(subject.request(method: :get, path: "/retry").body).to eq("ok")
    expect(request).to have_been_requested.times(3)
    expect(sleeps).to eq([2.0, 2.2])
  end

  it "does not retry unsafe methods unless explicitly enabled" do
    sleeps = []
    subject = transport(max_retries: 1, sleeper: ->(delay) { sleeps << delay }, retry_jitter: 0)
    unsafe = stub_request(:post, "https://api.machines.dev/unsafe").to_return(status: 503)
    opted_in = stub_request(:post, "https://api.machines.dev/opted-in")
               .to_return({status: 503}, {status: 200, body: "done"})

    expect { subject.request(method: :post, path: "/unsafe") }.to raise_error(FlyIO::ServerError)
    expect(unsafe).to have_been_requested.once
    expect(subject.request(method: :post, path: "/opted-in", retry_unsafe: true).body).to eq("done")
    expect(opted_in).to have_been_requested.twice
    expect(sleeps.length).to eq(1)
  end

  it "retries safe timeouts and wraps exhausted timeout and connection failures" do
    subject = transport(max_retries: 1, sleeper: ->(_delay) {}, retry_jitter: 0)
    recovered = stub_request(:get, "https://api.machines.dev/timeout-once")
                .to_raise(Faraday::TimeoutError.new("timed out")).then.to_return(status: 200)
    stub_request(:get, "https://api.machines.dev/timeout").to_raise(Faraday::TimeoutError.new("timed out"))
    stub_request(:get, "https://api.machines.dev/connect").to_raise(Faraday::ConnectionFailed.new("no route"))

    expect(subject.request(method: :get, path: "/timeout-once").status).to eq(200)
    expect(recovered).to have_been_requested.twice
    expect { subject.request(method: :get, path: "/timeout") }.to raise_error(FlyIO::RequestTimeoutError)
    expect { subject.request(method: :get, path: "/connect") }.to raise_error(FlyIO::TransportError, /ConnectionFailed/)
  end

  it "supports dependency injection without global HTTP monkey-patching" do
    raw_response = Struct.new(:status, :headers, :body).new(200, {"content-type" => "application/json"}, '{"ok":true}')
    adapter = instance_double("Adapter")
    allow(adapter).to receive(:call).and_return(raw_response)
    subject = described_class.new(configuration(adapter: adapter))

    expect(subject.request(method: :get, path: "/injected").body).to eq("ok" => true)
    expect(adapter).to have_received(:call).with(hash_including(method: :get, url: "https://api.machines.dev/injected"))
    expect(WebMock).not_to have_requested(:any, /api\.machines\.dev/)
  end

  it "redacts authorization, secrets, credentials, and server messages from logs and exceptions" do
    output = StringIO.new
    logger = Logger.new(output)
    subject = transport(logger: logger)
    stub_request(:post, "https://api.machines.dev/safe").to_return(status: 200, body: "ok")
    stub_request(:post, "https://api.machines.dev/fail").to_return(
      status: 400, headers: {"Content-Type" => "application/json"},
      body: '{"token":"server-token","password":"server-password"}'
    )

    subject.request(method: :post, path: "/safe", body: {secret: "client-secret"})
    expect { subject.request(method: :post, path: "/fail", body: {credential: "client-credential"}) }
      .to raise_error(FlyIO::APIError) do |error|
        expect(error.message).not_to match(/transport-token|server-token|server-password|client-credential/)
        expect(error.details).to eq("token" => "[FILTERED]", "password" => "[FILTERED]")
      end
    expect(output.string).not_to match(/transport-token|client-secret/)
    expect(output.string).to include("[FILTERED]")
  end
end
