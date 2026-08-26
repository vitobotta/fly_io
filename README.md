# fly_io

`fly_io` is a contract-driven Ruby client for Fly.io’s documented platform APIs. It covers every operation in the
Machines REST OpenAPI contract, the documentation-only Network Policies endpoints, Fly’s Prometheus compatibility
endpoint, and Fly’s explicitly unstable control-plane GraphQL boundary.

The Ruby namespace is `FlyIO`. The gem name was unclaimed on RubyGems when checked on 2026-08-26; see
[`contracts/research_metadata.json`](contracts/research_metadata.json). This repository is not published by or
affiliated with Fly.io.

## Installation

Add the gem to your bundle:

```ruby
gem "fly_io", "~> 0.1"
```

Then run `bundle install`. Ruby 3.2 or newer is supported. Development and the primary CI job use Ruby 4.0.6, the
latest stable release verified from ruby-lang.org on the contract retrieval date.

The sole runtime dependency is Faraday 2.x. It provides a maintained, adapter-injectable HTTP foundation; retries,
redaction, contract mapping, and model coercion are implemented in this gem so their behavior remains explicit.

## Quickstart

```ruby
require "fly_io"

client = FlyIO::Client.new(token: ENV.fetch("FLY_API_TOKEN"))

apps = client.apps.list(org_slug: "personal")
machine = client.machines.create(
  app_name: "my-app",
  body: {
    region: "iad",
    config: {
      image: "registry.example.com/my-image:latest",
      guest: {cpu_kind: "shared", cpus: 1, memory_mb: 512}
    }
  }
)

client.machines.start(app_name: "my-app", machine_id: machine.id)
client.machines.wait(app_name: "my-app", machine_id: machine.id, state: "started", timeout: 60)
```

Resource methods return `FlyIO::Response`. `response.body` is coerced to the documented `FlyIO::Models::*` class (or
an array/primitive where the contract says so), while response methods delegate to a model for concise code such as
`machine.id`. Models keep unknown fields and preserve exact wire keys for forward compatibility.

All named endpoint inputs are keyword arguments. JSON request bodies use `body:` because this gives every generated
operation one consistent signature. The generated [complete API reference](docs/API.md) maps each Ruby method to the
official operation ID, method, and path.

## Authentication

The official Machines guide and current examples use `Authorization: Bearer <token>`. The generated reference also
contains contradictory `FlyV1` prose. Consequently, a raw token uses `Bearer` by default and preformatted values are
explicit:

```ruby
FlyIO::Client.new(token: ENV.fetch("FLY_API_TOKEN"))
FlyIO::Client.new(authorization: "FlyV1 #{ENV.fetch("FLY_MACAROON")}")
FlyIO::Client.new(token: ENV.fetch("FLY_MACAROON"), authorization_mode: :fly_v1)
```

A token passed to `token:` must be raw, so `Bearer Bearer ...` cannot be produced accidentally. Authorization values,
tokens, secrets, passwords, credentials, private keys, and certificates are filtered from logs, request metadata, and
exceptions.

## Configuration and transport behavior

```ruby
configuration = FlyIO::Configuration.new(
  token: ENV.fetch("FLY_API_TOKEN"),
  base_url: "https://api.machines.dev",       # or http://_api.internal:4280 on the Fly private network
  graphql_url: "https://api.fly.io/graphql",
  metrics_url: "https://api.fly.io",
  open_timeout: 10,
  read_timeout: 30,
  write_timeout: 30,
  request_timeout: 45,
  proxy: ENV["HTTPS_PROXY"],
  user_agent: "my-service/1.0 fly_io/#{FlyIO::VERSION}",
  max_retries: 2,
  base_retry_interval: 0.25,
  max_retry_interval: 5,
  retry_jitter: 0.25,
  logger: Logger.new($stderr)
)
client = FlyIO::Client.new(configuration)
```

TLS verification is always enabled by the HTTP adapter. The client parses JSON only when the response content type is
JSON, represents 204 as a nil body, preserves 202 responses, and safely returns text, binary, empty, or malformed JSON
bodies. `FlyIO::Response` includes status, headers, parsed body, raw body, safe request metadata, and Fly’s request ID.

GET/HEAD/OPTIONS requests retry bounded transient connection failures and 408, 429, 500, 502, 503, and 504 responses.
`Retry-After` is honored; otherwise delay uses capped exponential backoff with jitter. Unsafe methods are never retried
unless a caller passes `retry_unsafe: true` to that request or deliberately enables it globally. Fly’s limits are
per-action and per-resource, so this gem does not pretend a single client-wide throttle is correct.

Configuration and resource objects are immutable. All request state is local, making a client safe to share between
threads. An object responding to `call(method:, url:, headers:, body:, timeout:)` can be supplied as `adapter:` for
dependency injection; a Faraday adapter symbol is also accepted.

## Errors

All failures inherit `FlyIO::Error`. HTTP failures use `FlyIO::APIError` and its typed subclasses:

- `AuthenticationError` / `AuthorizationError`
- `NotFoundError`
- `ValidationError`
- `RateLimitError`
- `RequestTimeoutError`
- `TransportError`
- `ServerError`
- `GraphQLError`

API errors retain status, safe headers, redacted parsed details, request ID, and redacted request metadata.

## Raw REST and operation-ID access

Use a path template when values are dynamic so every component is escaped independently:

```ruby
client.request(
  method: :get,
  path: "/v1/apps/{app_name}/machines",
  path_params: {app_name: "my-app"},
  query: {state: "started"}
)

client.operation("Machines_start", app_name: "my-app", machine_id: "machine-id")
```

The low-level API validates the method, rejects path traversal and URL-shaped paths, supports repeated query values,
and returns the same response/errors as resource methods. The upstream duplicate `Machines_update_metadata` ID must be
disambiguated with `method:` and `path:`.

## Network Policies

Fly officially documents three Network Policies operations that are missing from its OpenAPI document:

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

The guide does not document response statuses or schemas. Responses therefore remain forward-compatible raw values;
the body input is checked only against fields and constraints the guide actually states.

## Prometheus metrics

Fly documents seven Prometheus-compatible endpoint families at `https://api.fly.io/prometheus/<org>/`. They are a
stable observability/data API, not control-plane operations, but are included so the platform-surface audit is honest:

```ruby
client.metrics.query(org_slug: "personal", query: 'sum(rate(fly_edge_http_responses_count[5m]))')
client.metrics.query_range(org_slug: "personal", query: "up", start: "-1h", end: "now", step: "60s")
client.metrics.series(org_slug: "personal", match: ['{__name__="up"}'])
client.metrics.labels(org_slug: "personal")
client.metrics.label_values(org_slug: "personal", label_name: "app")
client.metrics.tsdb(org_slug: "personal")
client.metrics.federate(org_slug: "personal", match: ["up"])
```

The JSON envelope becomes `FlyIO::Models::PrometheusAPIResponse`; federation remains text. Endpoint semantics are
delegated to the stable Prometheus HTTP API and Fly’s stated VictoriaMetrics compatibility.

## GraphQL: experimental and unstable

Fly explicitly documents `https://api.fly.io/graphql` as an internal flyctl interface with no stability guarantees.
It can change without notice. Prefer REST or flyctl where possible. Nothing in this gem presents GraphQL fields as a
stable public contract.

Raw documents, variables, operation names, response parsing, errors, timeouts, and opt-in retries are first class:

```ruby
graphql = client.graphql
response = graphql.query(
  document: "query App($name: String!) { app(name: $name) { id name } }",
  variables: {name: "my-app"},
  operation_name: "App"
)
```

Schema introspection is double opt-in: construct configuration with `introspection: true`, then call
`graphql.introspect(document: ...)`. The committed flyctl schema is evidence only.

The experimental adapter inventories 29 current flyctl documents, 85 fly-go v0.9.8 documents, and 3 official unstable
examples. Execute one with `graphql.experimental.execute("flyctl.GetApp", variables: ...)`. Arbitrary raw GraphQL
documents remain available when Fly adds fields before this gem releases.

## Contracts, development, and tests

The [surface inventory](docs/SURFACES.md) records every selected/excluded surface, provenance, hashes, revisions,
counts, stability, and gaps. Contract artifacts live under `contracts/`; generated runtime metadata is under
`lib/fly_io/generated/`.

```shell
bundle install
bundle exec rake api:check   # offline snapshot/ref/mapping/generated-drift checks
bundle exec rspec            # offline; WebMock disables all network access
bundle exec rubocop
bundle exec bundle-audit check --update
bundle exec rake build
```

For an isolated `--install-dir` smoke under RubyGems 4, use `--ignore-dependencies` for the target gem and include the
already audited Bundler gem path when requiring it. RubyGems otherwise attempts to rediscover Faraday in a local gem
repository even when it is already installed. CI performs this install plus a packaged-gem require check.

`bundle exec rake api:fetch_check` is the explicit networked upstream-drift check. `script/generate_api` regenerates
operation/model metadata and [docs/API.md](docs/API.md). Generated code is included in coverage because the small
runtime generator boundary is exercised by contract-derived RSpec examples; JSON metadata itself has no executable
lines to exclude.

Live tests require `FLY_IO_LIVE_TESTS=1`, `FLY_API_TOKEN`, and `FLY_IO_TEST_APP`. Destructive live work additionally
requires `FLY_IO_DESTRUCTIVE_LIVE_TESTS=1`; ordinary CI never has network access or credentials.

## Versioning

The gem follows Semantic Versioning for its own stable Ruby API. Machines contract changes are reviewed through the
drift gate. Experimental GraphQL changes may ship in any release and are called out in the changelog because Fly gives
that upstream interface no compatibility guarantee.

## License

MIT. See [LICENSE](LICENSE).
