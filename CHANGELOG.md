# Changelog

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
