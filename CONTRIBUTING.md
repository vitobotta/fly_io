# Contributing

Use Ruby 4.0.6 for development. Run `bundle install`, then `bundle exec rake` before opening a change.

API changes start from committed evidence, not handwritten endpoint lists:

1. Run `bundle exec rake api:fetch_check` to detect Machines OpenAPI drift.
2. Review upstream changes and update the relevant snapshot plus provenance/hash.
3. Run `bundle exec rake api:generate`.
4. Add readable behavior coverage when semantics or risk changes.
5. Run `bundle exec rake`, `bundle exec bundle-audit check --update`, and the install smoke test.

Do not add undocumented flyctl calls to the stable namespace. GraphQL evidence stays experimental. Never commit tokens,
live response cassettes, credentials, or unredacted debug output.
