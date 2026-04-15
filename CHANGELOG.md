# Changelog

## [Unreleased]

## [0.3.7] - 2026-04-15

### Fixed
- `CLI::AppRunner#setup` and `#complete_setup` were posting to `/api/extensions/github/cli/app/*` which is not a valid daemon route; corrected to `/api/extensions/github/runners/app/*`
- `Runners::App` was missing entirely — added `runners/app.rb` as a proper runner module including `CLI::App` so the daemon auto-registers the routes via `build_routes`
- Added `require 'legion/extensions/github/runners/app'` to main `github.rb` load chain
- `AppRunner` now prompts interactively for `name`, `url`, and `webhook_url` when not provided; bumped `read_timeout` to 300s to survive the OAuth callback wait

## [0.3.6] - 2026-04-14

### Added
- `Absorbers::Issues`: normalizes GitHub issue webhook events to fleet work items; filters bot-generated events, already-claimed issues (fleet labels), and ignored actions; stores raw payload in Redis; publishes to assessor queue
- `Absorbers::IssuesActor`: subscription actor with `pattern 'github.issues.*'` that delegates to `Absorbers::Issues`
- `Absorbers::WebhookSetup`: mixin for idempotent webhook registration and fleet label creation (`fleet:received`, `fleet:implementing`, `fleet:pr-open`, `fleet:escalated`) on target repos
- `Absorbers::Helpers`: shared utilities — `bot_generated?`, `has_fleet_label?`, `ignored?`, `work_item_fingerprint`, `generate_work_item_id`, `transport_connected?`

## [0.3.5] - 2026-04-13

### Added
- `mark_pr_ready`: GraphQL `markPullRequestAsReady` mutation to remove draft status from a PR (REST API has no endpoint for this); includes private `graphql_connection` helper
- `get_tree`: fetch recursive repo file tree via Git Trees API (`GET /repos/{owner}/{repo}/git/trees/{sha}`)
- `get_file_content`: fetch a single file's content via Contents API with optional `ref` param
- `list_all_pull_request_files`: paginated variant that collects all pages (100/page) until exhausted; original `list_pull_request_files` preserved for backward compat
- `list_pull_request_review_comments`: fetch inline code review comments (`GET /pulls/{n}/comments`), distinct from issue comments
- `list_pull_request_commits`: simplified variant (per_page: 100, no cache) for fleet validator stale-diff guard

## [0.3.4] - 2026-04-06

### Added
- `resolve_broker_app` to `CREDENTIAL_RESOLVERS` for Broker integration (Phase 8 Wave 3)
- Stable `installation_id` fingerprint for consistent credential caching across GitHub App installations

## [0.3.3] - 2026-03-31

### Fixed
- CLI runner output: `status` and `login` commands now print JSON results to stdout
- CLI runner errors print to stderr via `warn`

## [0.3.2] - 2026-03-31

### Added
- CLI command registration: `legionio lex exec github auth status|login` and `legionio lex exec github app setup|complete_setup`
- `CLI::AuthRunner` and `CLI::AppRunner` wrapper classes for `lex exec` dispatch
- Self-registering CLI manifest at `~/.legionio/cache/cli/lex-github.json` (written on first require)
- Require redirect `lib/lex/github.rb` for `lex exec` compatibility

## [0.3.1] - 2026-03-30

### Changed
- Unpin jwt dependency from `~> 2.7` to `>= 2.7` to resolve conflict with jwt 3.x

## [0.3.0] - 2026-03-30

### Added
- GitHub App authentication (JWT generation, installation tokens via `App::Runners::Auth`)
- OAuth delegated user authentication (Authorization Code + PKCE, device code flow via `OAuth::Runners::Auth`)
- GitHub App manifest flow for streamlined app registration (`App::Runners::Manifest`)
- Webhook signature verification and event parsing (`App::Runners::Webhooks`)
- 8-source credential resolution chain: Vault delegated → Settings delegated → Vault App → Settings App → Vault PAT → Settings PAT → GH CLI → ENV (`Helpers::Client`)
- Rate limit fallback across credential sources with scope-aware skipping (`Helpers::ScopeRegistry`)
- Token lifecycle management with expiry tracking and rate limit recording (`Helpers::TokenCache`)
- Two-tier API response caching (global Redis + local in-memory) with configurable per-resource TTLs (`Helpers::Cache`)
- `jwt` (~> 2.7) and `base64` (>= 0.1) runtime dependencies

## [0.2.5] - 2026-03-30

### Changed
- update to rubocop-legion 0.1.7, resolve all offenses

## [0.2.4] - 2026-03-28

### Added
- `Runners::Branches` — `create_branch` using the Git Data API (GET ref + POST refs)
- `Runners::Contents` — `commit_files` for multi-file commits via the Git Data API (ref, commit, tree, new commit, ref update)
- Specs for both new runners (57 total, up from 47)

## [0.2.3] - 2026-03-22

### Changed
- Add runtime dependencies for all 7 legion sub-gems (legion-cache, legion-crypt, legion-data, legion-json, legion-logging, legion-settings, legion-transport)
- Update spec_helper to require real sub-gem helpers and stub Helpers::Lex with all 7 includes

## [0.2.1] - 2026-03-18

### Changed
- deleted gemfile.lock

## [0.2.0] - 2026-03-15

### Added
- `Runners::Labels` — full label management: `list_labels`, `get_label`, `create_label`, `update_label`, `delete_label`, `add_labels_to_issue`, `remove_label_from_issue`
- `Runners::Comments` — issue comment threads: `list_comments`, `get_comment`, `create_comment`, `update_comment`, `delete_comment`
- `Runners::PullRequests#list_pull_request_reviews` — GET reviews for a pull request
- `Runners::Commits` included in `Client` class (was already implemented but not wired up)
- Specs for all new methods

## [0.1.0] - 2026-03-13

### Added
- Initial release
