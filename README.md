# fly_io

[![Gem Version](https://img.shields.io/gem/v/fly_io.svg)](https://rubygems.org/gems/fly_io)
[![CI](https://github.com/vitobotta/fly_io/actions/workflows/ci.yml/badge.svg)](https://github.com/vitobotta/fly_io/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A typed Ruby client for the Fly.io platform APIs. It covers every operation in Fly's documented Machines REST contract
(Apps, Machines, Volumes, Secrets, TLS Certificates, Tokens, Organizations, Platform, Postgres Clusters), the
documentation-only Network Policies endpoints, Fly's Prometheus-compatible metrics API, and Fly's explicitly unstable
GraphQL control plane behind a separate, clearly marked client.

That is 108 operations, typed models for all 173 contract schemas, one runtime dependency (Faraday 2), and no Rails
coupling. Ruby 3.2 or newer.

`fly_io` is not published by, endorsed by, or affiliated with Fly.io.

**Contents:** [Why](#why-use-this-gem) · [Coverage](#coverage) · [Install](#installation) ·
[Authentication](#authentication) · [Quickstart](#quickstart) · [Responses](#responses-and-models) ·
[Errors](#errors) · [Configuration](#configuration) · [Recipes](#recipes) · [Testing](#testing-your-integration) ·
[GraphQL](#graphql-experimental) · [Troubleshooting](#troubleshooting) · [Development](#development)

## Why use this gem

- **Typed results, not hashes.** `machine.id`, `app.name`, `cluster.status` — every contract schema becomes a
  `FlyIO::Models::*` object, and unknown fields are preserved so new upstream fields never break your code.
- **The whole documented control plane.** Not just Machines: 108 operations across 11 resources, each mapped to its
  official operation ID. The full method/path table is in [`docs/API.md`](docs/API.md).
- **Failures you can act on.** Typed errors carry the HTTP status, parsed `details`, and Fly's `request_id`, so retry
  policies and support tickets do not need string parsing.
- **Safe defaults.** Bounded retries with jitter, idempotent methods only, and secrets filtered from logs, request
  metadata, and exceptions.
- **Easy to integrate.** Immutable and thread-safe, keyword-only arguments, and HTTP either via Faraday or a plain
  callable you supply.

## Coverage

| Resource | What it exposes | Operations |
|---|---|---:|
| `client.apps` | App lifecycle, IP assignments, deploy tokens, custom network on delete | 8 |
| `client.machines` | Machines, start/stop/restart/suspend, exec, leases, metadata, memory, versions, `wait` | 29 |
| `client.volumes` | Volumes, extend, snapshots | 8 |
| `client.secrets` | App secrets, plus secret keys (encrypt, decrypt, sign, verify) | 14 |
| `client.certificates` | TLS certificates, ACME and custom | 8 |
| `client.postgres_clusters` | Managed Postgres: clusters, users, databases, extensions, backups, fork, restore | 22 |
| `client.tokens` | Authenticate, authorize, current token, KMS, OIDC | 5 |
| `client.organizations` | Org-wide machine and volume listings | 2 |
| `client.platform` | Regions and placements | 2 |
| `client.network_policies` | Upsert, list, delete (documentation-derived) | 3 |
| `client.metrics` | Prometheus query, range, series, labels, label values, TSDB, federate | 7 |

Every surface, exclusion, contract hash, and upstream revision is recorded in [`docs/SURFACES.md`](docs/SURFACES.md)
and the machine-readable [`contracts/public_surface_inventory.json`](contracts/public_surface_inventory.json).

### What this gem is not

- **Not a deployment tool.** It does not build images, push to `registry.fly.io`, or orchestrate `fly deploy`. Use
  `flyctl` for deploys, this gem for control-plane work from Ruby.
- **Not a wrapper for undocumented APIs.** flyctl's internal `api.fly.io/api/v1` endpoints, the Extensions partner
  OAuth/webhooks surface, `registry.fly.io`, and Tigris are audited and deliberately excluded.
- **Not a stability promise for GraphQL.** That interface is marked experimental and may change in any release.

## Installation

```ruby
gem "fly_io", "~> 0.1"
```

Then `bundle install`. Ruby 3.2+ is supported; CI runs 3.2, 3.3, 3.4, and 4.0.6. The only runtime dependency is
Faraday (`>= 2.9`, `< 3`), which keeps the gem adapter-injectable; retries, redaction, contract mapping, and model
coercion are implemented here so their behavior stays explicit.

## Authentication

Create a token with `fly tokens create org` (or in the Fly dashboard) and export it:

```shell
export FLY_API_TOKEN="$(fly tokens create org)"
```

```ruby
# Raw token: the gem adds the Bearer scheme; pass the token itself, never a preformatted value.
client = FlyIO::Client.new(token: ENV.fetch("FLY_API_TOKEN"))

# Raw macaroon with the scheme Fly uses for flyctl-issued tokens.
client = FlyIO::Client.new(token: ENV.fetch("FLY_MACAROON"), authorization_mode: :fly_v1)

# Preformatted value, used verbatim.
client = FlyIO::Client.new(authorization: "FlyV1 #{ENV.fetch("FLY_MACAROON")}")
```

`Bearer` is the default because Fly's Machines guide and its curl examples use it; the generated reference contains
contradictory `FlyV1` prose. A value passed to `token:` must be raw — `Bearer Bearer ...` cannot be produced by
accident, and passing both `token:` and `authorization:` raises. Authorization values, tokens, secrets, passwords,
private keys, and certificates are redacted from logs, request metadata, and exception messages.

## Quickstart

```ruby
require "fly_io"

client = FlyIO::Client.new(token: ENV.fetch("FLY_API_TOKEN"))

# List apps in an org ("personal" is the default org slug); the body is a ListAppsResponse.
client.apps.list(org_slug: "personal").body.apps.each { |app| puts app.name }

# Create a machine, then block until it reports a state.
response = client.machines.create(
  app_name: "my-app",
  body: {
    region: "iad",
    config: {
      image: "registry.example.com/my-image:latest",
      guest: {cpu_kind: "shared", cpus: 1, memory_mb: 512}
    }
  }
)
machine = response.body

client.machines.wait(app_name: "my-app", machine_id: machine.id, state: "started", timeout: 60)
client.machines.restart(app_name: "my-app", machine_id: machine.id, timeout: 30)
client.machines.stop(app_name: "my-app", machine_id: machine.id, body: {signal: "SIGTERM", timeout: "30s"})
client.machines.destroy(app_name: "my-app", machine_id: machine.id)
```

```ruby
# Secrets: single value, or a bulk update.
client.secrets.set(app_name: "my-app", secret_name: "DATABASE_URL", body: {value: "postgres://..."})
client.secrets.update(app_name: "my-app", body: {values: {"RAILS_ENV" => "production"}})
client.secrets.list(app_name: "my-app")

# Volumes.
volume = client.volumes.create(app_name: "my-app", body: {name: "data", region: "iad", size_gb: 10}).body
client.volumes.extend(app_name: "my-app", volume_id: volume.id, body: {size_gb: 20})

# Destroy an app. Pass the custom private network too if it has one, or omit `network:` for the default network.
client.apps.destroy(app_name: "my-app")
client.apps.destroy(app_name: "my-app", network: "customer-network")
```

Two rules cover the entire API: every documented input is a keyword argument, and every JSON request body is passed as
`body:`. Unknown keywords and contract-invalid values raise `FlyIO::ArgumentError` before a request is made — never a
half-built HTTP call. Each call also accepts `headers:`, `retry_unsafe:`, and `request_timeout:` overrides.

## Responses and models

Resource methods return `FlyIO::Response`; `body` is coerced to the documented model class (or an array/primitive where
the contract says so), and the response delegates to the body for concise code:

```ruby
response = client.machines.get(app_name: "my-app", machine_id: "machine-id")

response.status       # => 200
response.success?     # => true (2xx)
response.accepted?    # => false (202)
response.no_content?  # => false (204)
response.request_id   # => Fly's request id
response.body         # => FlyIO::Models::Machine
response.state        # => same as response.body.state
```

JSON is parsed only when the content type is JSON; 204 becomes a `nil` body, 202 is preserved, and text, binary, empty,
or malformed JSON bodies are returned as raw values instead of raising.

## Errors

All failures inherit `FlyIO::Error`; HTTP failures are `FlyIO::APIError` subclasses:

| Status | Class |
|---|---|
| 400, 409, 412, 422 | `FlyIO::ValidationError` |
| 401 | `FlyIO::AuthenticationError` |
| 403 | `FlyIO::AuthorizationError` |
| 404, 410 | `FlyIO::NotFoundError` |
| 408 | `FlyIO::RequestTimeoutError` |
| 429 | `FlyIO::RateLimitError` |
| 5xx | `FlyIO::ServerError` |
| other 4xx | `FlyIO::APIError` |
| connection/DNS/TLS failure | `FlyIO::TransportError` |
| GraphQL error payload | `FlyIO::GraphQLError` (`graphql_errors`) |

API errors retain `status`, safe `headers`, redacted `details`, `request_id`, and redacted request metadata:

```ruby
begin
  client.machines.get(app_name: "my-app", machine_id: "missing")
rescue FlyIO::NotFoundError => e
  logger.warn("machine not found (request_id=#{e.request_id})")
rescue FlyIO::RateLimitError => e
  logger.warn("rate limited, retry-after=#{e.headers["retry-after"]} (request_id=#{e.request_id})")
rescue FlyIO::APIError => e
  logger.error("#{e.class} status=#{e.status} details=#{e.details.inspect} request_id=#{e.request_id}")
end
```

Include `request_id` in Fly support requests — it is the fastest way for Fly to trace a failed call.

## Configuration

Pass keyword options straight to the client, or build a reusable `FlyIO::Configuration`:

```ruby
client = FlyIO::Client.new(
  token: ENV.fetch("FLY_API_TOKEN"),
  base_url: "https://api.machines.dev",
  read_timeout: 30,
  max_retries: 2,
  logger: Logger.new($stderr)
)
```

| Option | Default | Purpose |
|---|---|---|
| `token:` | — | Raw API token; required unless `authorization:` is given |
| `authorization:` | — | Preformatted `Authorization` value, used verbatim |
| `authorization_mode:` | `:bearer` | `:bearer` or `:fly_v1` scheme for a raw token |
| `base_url:` | `https://api.machines.dev` | Machines/Network Policies base; or `http://_api.internal:4280` inside Fly |
| `graphql_url:` | `https://api.fly.io/graphql` | Experimental GraphQL endpoint |
| `metrics_url:` | `https://api.fly.io` | Prometheus metrics base |
| `open_timeout:` | `10` | Connection timeout, seconds |
| `read_timeout:` | `30` | Read timeout, seconds |
| `write_timeout:` | `30` | Write timeout, seconds |
| `request_timeout:` | `nil` | Overall per-request deadline when set |
| `proxy:` | `nil` | Proxy URL, e.g. `ENV["HTTPS_PROXY"]` |
| `user_agent:` | `fly_io/<version>` | Override to include your service name |
| `max_retries:` | `2` | Retry attempts for retryable failures |
| `base_retry_interval:` | `0.25` | Initial backoff, seconds |
| `max_retry_interval:` | `5.0` | Backoff ceiling, seconds |
| `retry_jitter:` | `0.25` | Random jitter fraction added to each delay |
| `retry_unsafe:` | `false` | Allow retries for POST/PUT/PATCH/DELETE globally |
| `logger:` | `nil` | Logger for request/retry events (values redacted) |
| `adapter:` | `nil` | Faraday adapter symbol, or a callable for tests |
| `introspection:` | `false` | First opt-in for GraphQL schema introspection |

`sleeper:` and `random:` are injectable too, which makes backoff deterministic in tests. Configuration and resource
objects are frozen; a client is safe to share between threads because all request state is local.

### Retries and timeouts

GET, HEAD, and OPTIONS retry bounded transient connection failures plus 408, 429, 500, 502, 503, and 504 responses.
`Retry-After` is honored when present; otherwise the delay is capped exponential backoff with jitter. Unsafe methods are
never retried unless you pass `retry_unsafe: true` to that call or enable it in configuration. `request_timeout:` is an
overall deadline, while `open_timeout:`, `read_timeout:`, and `write_timeout:` bound the individual phases.

## Recipes

### From inside a Fly machine

Traffic to the public endpoint leaves the machine; the private endpoint keeps API calls on Fly's private network:

```ruby
client = FlyIO::Client.new(token: ENV.fetch("FLY_API_TOKEN"), base_url: "http://_api.internal:4280")
```

### Org-wide inventory

```ruby
client.organizations.list_machines(org_slug: "personal")
client.organizations.list_volumes(org_slug: "personal")
client.platform.regions
```

### Metrics

```ruby
response = client.metrics.query(
  org_slug: "personal",
  query: "sum(rate(fly_edge_http_responses_count[5m]))"
)
response.body # => FlyIO::Models::PrometheusAPIResponse

client.metrics.query_range(org_slug: "personal", query: "up", start: "-1h", end: "now", step: "60s")
client.metrics.federate(org_slug: "personal", match: ["up"]) # => raw text
```

### Raw REST with path templates

Escape dynamic path segments correctly by using a template rather than string interpolation:

```ruby
client.request(
  method: :get,
  path: "/v1/apps/{app_name}/machines",
  path_params: {app_name: "my-app"},
  query: {state: "started"}
)

client.operation("Machines_start", app_name: "my-app", machine_id: "machine-id")
```

The low-level API validates the method, rejects path traversal and URL-shaped paths, supports repeated query values, and
returns the same responses and errors as resource methods. Fly reuses the operation ID `Machines_update_metadata` for
both PUT and PATCH, so disambiguate it with `method:`:

```ruby
client.operation("Machines_update_metadata", method: :patch, app_name: "my-app", machine_id: "machine-id",
                 key: "status", body: {value: "ready"})
```

### Network Policies

Fly documents three Network Policies operations outside its OpenAPI document. Upstream documents no schemas or
statuses, so responses stay raw and only documented input fields are checked:

```ruby
client.network_policies.upsert(
  app_name: "my-app",
  body: {
    name: "web-egress",
    selector: {metadata: {role: "web"}},
    rules: [{action: "allow", direction: "egress", ports: [{protocol: "tcp", port: 443}]}]
  }
)
client.network_policies.list(app_name: "my-app")
client.network_policies.delete(app_name: "my-app", policy_id: "policy-id")
```

### Managed Postgres

```ruby
client.postgres_clusters.list(org_slug: "personal")
client.postgres_clusters.show(postgres_cluster_id: "cluster-id")
client.postgres_clusters.users_credentials(postgres_cluster_id: "cluster-id", username: "app")
```

## Testing your integration

The gem's own suite runs offline with WebMock; the same approach works in your app:

```ruby
require "webmock/rspec"

stub_request(:get, "https://api.machines.dev/v1/apps?org_slug=personal")
  .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: '{"apps": []}')
```

For end-to-end tests without stubbing, inject an adapter — any object responding to
`call(method:, url:, headers:, body:, timeout:)`:

```ruby
class RecordingAdapter
  def initialize
    @calls = []
  end

  def call(method:, url:, headers:, body:, timeout:)
    @calls << {method: method, url: url, headers: headers, body: body, timeout: timeout}
    Struct.new(:status, :headers, :body).new(200, {"content-type" => "application/json"}, "{}")
  end
end

client = FlyIO::Client.new(token: "test-token", adapter: RecordingAdapter.new)
```

## GraphQL: experimental

`https://api.fly.io/graphql` is flyctl's internal interface and Fly gives it no stability guarantees. Prefer REST or
`flyctl` where possible; nothing here presents GraphQL fields as a stable contract.

```ruby
response = client.graphql.query(
  document: "query App($name: String!) { app(name: $name) { id name } }",
  variables: {name: "my-app"},
  operation_name: "App"
)
```

Introspection is double opt-in: construct the configuration with `introspection: true`, then call
`graphql.introspect(document: ...)`. The experimental adapter inventories 29 flyctl documents, 85 fly-go v0.9.8
documents, and 3 official unstable examples; run one with `graphql.experimental.execute("flyctl.GetApp", variables: ...)`.
Raw documents remain available whenever Fly adds fields before this gem releases.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `FlyIO::ConfigurationError: token must be raw` | You passed `"Bearer ..."` to `token:`; pass the bare token, or use `authorization:` |
| 401 on every call | Token missing, expired, or from a different org; check `ENV["FLY_API_TOKEN"]` |
| 403 on org-scoped calls | Token lacks access to that org slug; create it for the right org with `fly tokens create org` |
| `unknown keywords: [...]` | Argument names follow the contract; check the signature in [`docs/API.md`](docs/API.md) |
| Network policy response is a raw value | Expected: Fly publishes no response schema for those three operations |
| `Machines_update_metadata` raises about ambiguity | Pass `method:` (PUT vs PATCH) |
| `FlyIO::RequestTimeoutError` after retries | Increase `request_timeout:`/`read_timeout:`, or retry the operation yourself |
| GraphQL fields disappeared | Upstream internal interface changed; pin behavior to REST |

## Development

```shell
bundle install
bundle exec rake            # api:check + rspec + rubocop, all offline
bundle exec rake api:check  # contract snapshot, mapping, generated-drift checks
bundle exec rake api:fetch_check  # networked: fail if upstream OpenAPI drifted
bundle exec rake api:generate     # regenerate metadata and docs/API.md
bundle exec bundle-audit check --update
bundle exec rake build
```

Live tests require `FLY_IO_LIVE_TESTS=1`, `FLY_API_TOKEN`, and `FLY_IO_TEST_APP`; destructive live work additionally
requires `FLY_IO_DESTRUCTIVE_LIVE_TESTS=1`. CI never has credentials or network access. For an isolated `--install-dir`
smoke under RubyGems 4, install the target gem with `--ignore-dependencies` and put the already-audited Bundler gem path
on `GEM_PATH`. See [CONTRIBUTING.md](CONTRIBUTING.md) before changing the API surface.

## Versioning

Semantic Versioning for the gem's own stable Ruby API. Machines contract changes go through the drift gate; experimental
GraphQL changes may land in any release and are called out in the [changelog](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
