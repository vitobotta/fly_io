# Fly.io public API surface inventory

Retrieved 2026-08-26. The machine-readable source is
[`contracts/public_surface_inventory.json`](../contracts/public_surface_inventory.json).

## Supported surfaces

| Surface | Base URL | Stability | Authoritative contract/evidence | Count | Ruby coverage |
|---|---|---|---|---:|---|
| Machines REST | `https://api.machines.dev` | Public documented | OpenAPI 3.0.1, `https://docs.machines.dev/openapi.json`, SHA-256 `9e6a180c40a38bf20b72a8577a8cd93866f47882627b608af753cc4c22f7758f` | 68 paths / 98 operations / 173 schemas | 98 generated resource methods and operation-ID adapter; 173 typed models |
| Network Policies REST | `https://api.machines.dev` | Public documented; no formal stability label | Official docs revision `1e8cac5f0fd7a82e66e3b01ece3a10a8ecb2b7e3`, source SHA-256 `fa64b69db56beb1da2de60e3ff91820b628a1238a120d103c2f3bae16e2fcc1f` | 3 operations | `client.network_policies`; responses raw because upstream documents none |
| Control-plane GraphQL | `https://api.fly.io/graphql` | **Internal/experimental; explicitly no stability guarantee** | flyctl revision `1f906765dee8e973f6d1dd8fff65b58212e7b425`; evidence schema SHA-256 `2f1a1d0f2f8940277e5e14002c78cb4f6404b3ea1ce9d0999d4d3b65c52f9480` | 39 query + 141 mutation schema root fields; 29 flyctl + 85 fly-go + 3 official observed documents | Raw first-class `GraphQLClient`; 117-operation experimental generated adapter; opt-in introspection |
| Prometheus metrics | `https://api.fly.io/prometheus/{org_slug}/` | Stable standard data API with qualified compatibility; not control-plane | Official docs revision `1e8cac5f0fd7a82e66e3b01ece3a10a8ecb2b7e3`, source SHA-256 `e22d7b34406b16c2ea75eed6cd92c51ec07d166963155623557295ef24f67e9f`; Prometheus/VictoriaMetrics contracts | 7 endpoint families | `client.metrics` typed response envelope and federation text |

Machines families are Apps (8), TLS Certificates (8), Machines (29), Secrets (14), Volumes (8), Organizations (2),
Platform (2), Postgres Clusters (22), and Tokens (5). Network Policies adds its own family outside OpenAPI.

## Authentication decision

The official Machines guide specifies `Bearer`; the generated reference says `FlyV1` in prose but uses `Bearer` in
its curl example. flyctl selects schemes by token kind. The gem therefore maps raw tokens to `Bearer` and accepts an
explicit preformatted authorization value or explicit `:fly_v1` mode. It never guesses from token contents.

## Audited exclusions

| Surface | Decision and reason |
|---|---|
| Extensions partner OAuth/webhooks | Partner-gated, prose-only integration requiring Fly-issued credentials; not a general account control-plane API. The audit records 4 prose operations but the gem does not imply public availability. |
| flyctl UIEX REST (`https://api.fly.io/api/v1`) | 52 current internal call sites, with no official public documentation or schema. Excluded rather than presenting observed implementation details as stable. |
| Tigris S3 | Adjacent beta data plane governed by the external S3 contract and separate credentials. |
| `registry.fly.io` | Adjacent image data plane accessed through Docker/OCI tooling and its external distribution contract. |

## Known upstream gaps and follow-up checks

- `Machines_update_metadata` is duplicated for PUT and PATCH. Coverage identity is method + path + operation ID.
- OpenAPI has no security scheme and omits several used tags from its top-level declaration.
- Network Policies is absent from OpenAPI; its guide gives no response status/schema and shows a trailing slash only
  for list. The committed documentation snapshot makes this ambiguity reviewable.
- Fly’s GraphQL schema is manually copied into flyctl from a private repository. It is evidence, never a stable
  contract. Refresh all three GraphQL inventories when flyctl or fly-go revisions change.
- Fly describes Prometheus support as “most common” compatible endpoints; `api:check` asserts the seven listed
  families, while semantics stay delegated to Prometheus/VictoriaMetrics.

Run `bundle exec rake api:check` offline for all committed contracts and `bundle exec rake api:fetch_check` to compare
the Machines snapshot with the live OpenAPI URL.

## Authoritative starting links

- [Machines API overview](https://fly.io/docs/machines/api/)
- [Machines OpenAPI JSON](https://docs.machines.dev/openapi.json)
- [Generated Machines reference](https://docs.machines.dev/)
- [Connection, authentication, statuses, and rate limits](https://fly.io/docs/machines/api/working-with-machines-api)
- [Apps resource](https://fly.io/docs/machines/api/apps-resource)
- [Machines resource](https://fly.io/docs/machines/api/machines-resource)
- [Volumes resource](https://fly.io/docs/machines/api/volumes-resource)
- [Certificates resource](https://fly.io/docs/machines/api/certificates-resource)
- [Tokens resource](https://fly.io/docs/machines/api/tokens-resource)
- [REST and GraphQL stability guidance](https://fly.io/docs/machines/guides-examples/managing-machines-with-the-api)
- [Network Policies](https://fly.io/docs/machines/guides-examples/network-policies)
- [Prometheus metrics](https://fly.io/docs/monitoring/metrics)
