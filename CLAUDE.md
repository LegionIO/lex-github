# lex-github: GitHub Integration for LegionIO

**Repository Level 3 Documentation**
- **Parent (Level 2)**: `/Users/miverso2/rubymine/legion/extensions/CLAUDE.md`
- **Parent (Level 1)**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Legion Extension that connects LegionIO to GitHub. Provides runners for interacting with the GitHub REST API covering repositories, issues, pull requests, users, organizations, gists, and search.

**GitHub**: https://github.com/LegionIO/lex-github
**License**: MIT

## Architecture

```
Legion::Extensions::Github
├── Runners/
│   ├── Repositories      # CRUD repos, list branches/tags
│   ├── Issues            # CRUD issues, comments
│   ├── PullRequests      # CRUD PRs, merge, list commits/files
│   ├── Users             # Get users, list followers/following
│   ├── Organizations     # Get orgs, list repos/members
│   ├── Gists             # CRUD gists
│   └── Search            # Search repos, issues, users, code
├── Helpers/
│   └── Client            # Faraday connection builder (GitHub API v3)
└── Client                # Standalone client class (includes all runners)
```

## Dependencies

| Gem | Purpose |
|-----|---------|
| `faraday` | HTTP client for GitHub REST API |

## Testing

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

---

**Maintained By**: Matthew Iverson (@Esity)
