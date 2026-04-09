# lex-github: GitHub Integration for LegionIO

**Repository Level 3 Documentation**
- **Parent (Level 2)**: `/Users/miverso2/rubymine/legion/extensions/CLAUDE.md`
- **Parent (Level 1)**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Legion Extension that connects LegionIO to GitHub. Provides runners for interacting with the GitHub REST API covering repositories, issues, pull requests, users, organizations, gists, search, labels, comments, commits, branches, file contents, Actions workflows, checks, releases, deployments, repository webhooks, GitHub App authentication, OAuth delegated auth, and credential storage.

**GitHub**: https://github.com/LegionIO/lex-github
**License**: MIT
**Version**: 0.3.3

## Architecture

```
Legion::Extensions::Github
├── Runners/
│   ├── Repositories      # CRUD repos, list branches/tags
│   ├── Issues            # CRUD issues
│   ├── PullRequests      # CRUD PRs, merge, list commits/files/reviews
│   ├── Users             # Get users, list followers/following
│   ├── Organizations     # Get orgs, list repos/members
│   ├── Gists             # CRUD gists
│   ├── Search            # Search repos, issues, users, code
│   ├── Labels            # CRUD labels, add/remove issue labels
│   ├── Comments          # CRUD issue/PR comments
│   ├── Commits           # List, get, compare commits
│   ├── Branches          # Create branches via Git Data API
│   ├── Contents          # Commit multiple files via Git Data API
│   ├── Actions           # Workflows, runs, jobs, artifacts, logs
│   ├── Checks            # Check runs, check suites, annotations
│   ├── Releases          # CRUD releases, release assets
│   ├── Deployments       # CRUD deployments and deployment statuses
│   ├── RepositoryWebhooks # CRUD repo webhooks, ping, test, deliveries
│   └── Auth              # Composite runner: delegates to App, CredentialStore, OAuth auth modules
├── App/
│   ├── Runners/
│   │   ├── Auth          # JWT generation, installation token exchange, list/get installations
│   │   ├── Webhooks      # HMAC signature verification, event parsing
│   │   ├── Manifest      # GitHub App manifest flow (generate, exchange code, manifest URL)
│   │   ├── Installations # Full installation management (list repos, suspend, delete)
│   │   └── CredentialStore # Store app credentials and OAuth tokens in Vault
│   ├── Actors/
│   │   ├── TokenRefresh  # Periodic App installation token refresh
│   │   └── WebhookPoller # Polls GitHub webhook deliveries
│   └── Transport/        # AMQP transport (exchanges/queues/messages)
├── OAuth/
│   ├── Runners/
│   │   └── Auth          # PKCE + Authorization Code, device code, refresh, revoke
│   ├── Actors/
│   │   └── TokenRefresh  # Periodic OAuth delegated token refresh
│   └── Transport/        # AMQP transport (exchanges/queues)
├── Middleware/
│   ├── RateLimit         # Tracks rate-limit headers, skips exhausted credentials
│   ├── ScopeProbe        # Detects scope-denied 403s for specific owner/repo
│   └── CredentialFallback # Triggers fallback to next credential source on auth failure
├── Helpers/
│   ├── Client            # 8-source scope-aware credential resolution chain + Faraday builder
│   ├── Cache             # Two-tier read-through/write-through API response caching
│   ├── TokenCache        # Token lifecycle management (store, fetch, expiry, rate limits)
│   ├── ScopeRegistry     # Credential-to-scope authorization cache (org/repo level)
│   ├── BrowserAuth       # Delegated OAuth orchestrator (PKCE, headless detection, browser launch)
│   └── CallbackServer    # Ephemeral TCP server for OAuth redirect callback
├── CLI/
│   ├── Auth              # `legion lex exec github auth login/status`
│   ├── App               # `legion lex exec github app setup/complete_setup`
│   └── Runner            # CLI dispatch registration
└── Client                # Standalone client class (includes all runners)
```

### Credential Resolution Chain (8 sources, in priority order)

1. `resolve_vault_delegated` — OAuth user token from Vault (`github/oauth/delegated/token`)
2. `resolve_settings_delegated` — OAuth user token from `Legion::Settings[:github][:oauth][:access_token]`
3. `resolve_vault_app` — GitHub App installation token (requires cached token from `TokenCache`)
4. `resolve_settings_app` — App token from settings (requires cached token)
5. `resolve_vault_pat` — PAT from Vault (`github/token`)
6. `resolve_settings_pat` — PAT from `Legion::Settings[:github][:token]`
7. `resolve_gh_cli` — Token from `gh auth token` CLI command (cached 300s)
8. `resolve_env` — `GITHUB_TOKEN` environment variable

Rate-limited credentials are skipped. Scope-denied credentials (for a given owner/repo) are skipped.

## Dependencies

| Gem | Purpose |
|-----|---------|
| `faraday` (>= 2.0) | HTTP client for GitHub REST API |
| `jwt` (>= 2.7) | RS256 JWT generation for GitHub App authentication |
| `base64` (>= 0.1) | PKCE code challenge computation |
| `legion-cache` (>= 1.3.11) | Two-tier caching (global Redis + local in-memory) |
| `legion-crypt` (>= 1.4.9) | Vault secret resolution for credentials |
| `legion-data` (>= 1.4.17) | Data persistence |
| `legion-json` (>= 1.2.1) | JSON serialization |
| `legion-logging` (>= 1.3.2) | Logging |
| `legion-settings` (>= 1.3.14) | Settings-based credential resolution |
| `legion-transport` (>= 1.3.9) | AMQP transport for actors |

## Key Files

| File | Purpose |
|------|---------|
| `lib/legion/extensions/github.rb` | Extension entry point, requires all modules |
| `lib/legion/extensions/github/client.rb` | Standalone client class (includes all runners) |
| `lib/legion/extensions/github/helpers/client.rb` | Credential resolution chain + Faraday builder |
| `lib/legion/extensions/github/helpers/cache.rb` | Two-tier API response caching |
| `lib/legion/extensions/github/helpers/token_cache.rb` | Token lifecycle + rate limit tracking |
| `lib/legion/extensions/github/helpers/scope_registry.rb` | Credential-to-scope authorization cache |
| `lib/legion/extensions/github/helpers/browser_auth.rb` | OAuth PKCE browser launch + headless detection |
| `lib/legion/extensions/github/helpers/callback_server.rb` | Ephemeral TCP server for OAuth redirect |
| `lib/legion/extensions/github/app/runners/auth.rb` | JWT generation, installation tokens |
| `lib/legion/extensions/github/app/runners/webhooks.rb` | Webhook signature verification, event parsing |
| `lib/legion/extensions/github/app/runners/manifest.rb` | GitHub App manifest registration flow |
| `lib/legion/extensions/github/app/runners/installations.rb` | Installation management |
| `lib/legion/extensions/github/app/runners/credential_store.rb` | Store app/OAuth credentials in Vault |
| `lib/legion/extensions/github/oauth/runners/auth.rb` | OAuth PKCE, device code, token refresh/revoke |
| `lib/legion/extensions/github/runners/auth.rb` | Composite auth runner (delegates to app + oauth + credential_store) |
| `lib/lex/github.rb` | Redirect shim for `require 'lex/github'` |

## Testing

234 specs across 38 spec files.

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

---

**Maintained By**: Matthew Iverson (@Esity)
