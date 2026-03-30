# lex-github: GitHub Integration for LegionIO

**Repository Level 3 Documentation**
- **Parent (Level 2)**: `/Users/miverso2/rubymine/legion/extensions/CLAUDE.md`
- **Parent (Level 1)**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Legion Extension that connects LegionIO to GitHub. Provides runners for interacting with the GitHub REST API covering repositories, issues, pull requests, users, organizations, gists, search, labels, comments, commits, branches, file contents, GitHub App authentication, OAuth delegated auth, and webhook handling.

**GitHub**: https://github.com/LegionIO/lex-github
**License**: MIT
**Version**: 0.3.0

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
│   └── Contents          # Commit multiple files via Git Data API
├── App/
│   └── Runners/
│       ├── Auth          # JWT generation, installation token exchange, list/get installations
│       ├── Webhooks      # HMAC signature verification, event parsing
│       ├── Manifest      # GitHub App manifest flow (generate, exchange code, manifest URL)
│       └── Installations # Full installation management (list repos, suspend, delete)
├── OAuth/
│   └── Runners/
│       └── Auth          # PKCE + Authorization Code, device code, refresh, revoke
├── Helpers/
│   ├── Client            # 8-source scope-aware credential resolution chain + Faraday builder
│   ├── Cache             # Two-tier read-through/write-through API response caching
│   ├── TokenCache        # Token lifecycle management (store, fetch, expiry, rate limits)
│   └── ScopeRegistry     # Credential-to-scope authorization cache (org/repo level)
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
| `faraday` | HTTP client for GitHub REST API |
| `jwt` (~> 2.7) | RS256 JWT generation for GitHub App authentication |
| `base64` (>= 0.1) | PKCE code challenge computation |
| `legion-cache` | Two-tier caching (global Redis + local in-memory) |
| `legion-crypt` | Vault secret resolution for credentials |
| `legion-settings` | Settings-based credential resolution |

## Key Files

| File | Purpose |
|------|---------|
| `lib/legion/extensions/github.rb` | Extension entry point, requires all modules |
| `lib/legion/extensions/github/client.rb` | Standalone client class (includes all runners) |
| `lib/legion/extensions/github/helpers/client.rb` | Credential resolution chain + Faraday builder |
| `lib/legion/extensions/github/helpers/cache.rb` | Two-tier API response caching |
| `lib/legion/extensions/github/helpers/token_cache.rb` | Token lifecycle + rate limit tracking |
| `lib/legion/extensions/github/helpers/scope_registry.rb` | Credential-to-scope authorization cache |
| `lib/legion/extensions/github/app/runners/auth.rb` | JWT generation, installation tokens |
| `lib/legion/extensions/github/app/runners/webhooks.rb` | Webhook signature verification, event parsing |
| `lib/legion/extensions/github/app/runners/manifest.rb` | GitHub App manifest registration flow |
| `lib/legion/extensions/github/app/runners/installations.rb` | Installation management |
| `lib/legion/extensions/github/oauth/runners/auth.rb` | OAuth PKCE, device code, token refresh/revoke |

## Testing

131 specs across 23 spec files (growing with each new runner).

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

---

**Maintained By**: Matthew Iverson (@Esity)
