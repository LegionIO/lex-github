# lex-github: GitHub Integration for LegionIO

**Repository Level 3 Documentation**
- **Parent (Level 2)**: `/Users/miverso2/rubymine/legion/extensions/CLAUDE.md`
- **Parent (Level 1)**: `/Users/miverso2/rubymine/legion/CLAUDE.md`

## Purpose

Legion Extension that connects LegionIO to GitHub. Provides runners for interacting with the GitHub REST API covering repositories, issues, pull requests, users, organizations, gists, search, labels, comments, and commits.

**GitHub**: https://github.com/LegionIO/lex-github
**License**: MIT
**Version**: 0.2.0

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
│   └── Commits           # List, get, compare commits
├── Helpers/
│   └── Client            # Faraday connection builder (GitHub API v3)
└── Client                # Standalone client class (includes all runners)
```

## Dependencies

| Gem | Purpose |
|-----|---------|
| `faraday` | HTTP client for GitHub REST API |

## Key Files

| File | Purpose |
|------|---------|
| `lib/legion/extensions/github.rb` | Extension entry point, requires all runners |
| `lib/legion/extensions/github/client.rb` | Standalone client class |
| `lib/legion/extensions/github/helpers/client.rb` | Faraday connection builder |
| `lib/legion/extensions/github/runners/repositories.rb` | Repo CRUD, branches, tags |
| `lib/legion/extensions/github/runners/issues.rb` | Issue CRUD |
| `lib/legion/extensions/github/runners/pull_requests.rb` | PR CRUD, merge, files, reviews |
| `lib/legion/extensions/github/runners/users.rb` | User lookup, followers/following |
| `lib/legion/extensions/github/runners/organizations.rb` | Org info, repos, members |
| `lib/legion/extensions/github/runners/gists.rb` | Gist CRUD |
| `lib/legion/extensions/github/runners/search.rb` | Search repos/issues/users/code |
| `lib/legion/extensions/github/runners/labels.rb` | Label CRUD, add/remove on issues |
| `lib/legion/extensions/github/runners/comments.rb` | Issue/PR comment CRUD |
| `lib/legion/extensions/github/runners/commits.rb` | List, get, compare commits |

## Testing

47 specs across 13 spec files.

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

---

**Maintained By**: Matthew Iverson (@Esity)
