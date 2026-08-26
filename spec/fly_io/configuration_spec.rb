# frozen_string_literal: true

RSpec.describe FlyIO::Configuration do
  it "uses the public endpoints, documented Bearer scheme, and bounded defaults" do
    configuration = described_class.new(token: "raw-token")

    expect(configuration.base_url).to eq("https://api.machines.dev")
    expect(configuration.graphql_url).to eq("https://api.fly.io/graphql")
    expect(configuration.authorization_value).to eq("Bearer raw-token")
    expect(configuration.max_retries).to eq(2)
    expect(configuration).to be_frozen
  end

  it "accepts an explicitly preformatted authorization value without adding a scheme" do
    configuration = described_class.new(authorization: "FlyV1 already-formatted")
    expect(configuration.authorization_value).to eq("FlyV1 already-formatted")
  end

  it "supports an explicit FlyV1 raw-token mode for compatibility" do
    expect(described_class.new(token: "raw", authorization_mode: :fly_v1).authorization_value).to eq("FlyV1 raw")
  end

  it "rejects missing, duplicate, or accidentally preformatted raw-token input" do
    expect { described_class.new }.to raise_error(FlyIO::ConfigurationError, /token is required/)
    expect { described_class.new(token: "x", authorization: "Bearer x") }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(token: "Bearer x") }.to raise_error(FlyIO::ConfigurationError, /must be raw/)
    expect { described_class.new(authorization: "no-scheme") }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(token: "x", authorization_mode: :unknown) }.to raise_error(FlyIO::ConfigurationError)
  end

  it "validates URLs, timeouts, and retry bounds" do
    expect { described_class.new(token: "x", base_url: "ftp://example.test") }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(token: "x", base_url: "https://u:p@example.test") }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(token: "x", base_url: "::not a uri") }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(token: "x", read_timeout: 0) }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(token: "x", max_retries: -1) }.to raise_error(FlyIO::ConfigurationError)
    expect { described_class.new(token: "x", retry_jitter: -1) }.to raise_error(FlyIO::ConfigurationError)
    expect do
      described_class.new(token: "x", base_retry_interval: 2, max_retry_interval: 1)
    end.to raise_error(FlyIO::ConfigurationError)
  end

  it "derives a new immutable configuration without losing authorization" do
    original = described_class.new(token: "x")
    derived = original.with(base_url: "http://_api.internal:4280/", read_timeout: 5)

    expect(derived.base_url).to eq("http://_api.internal:4280")
    expect(derived.read_timeout).to eq(5.0)
    expect(derived.authorization_value).to eq("Bearer x")
    expect(original.base_url).to eq("https://api.machines.dev")
  end
end
