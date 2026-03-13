# lex-github

GitHub integration for [LegionIO](https://github.com/LegionIO/LegionIO). Provides runners for interacting with the GitHub REST API including repositories, issues, pull requests, users, organizations, gists, and search.

## Installation

```bash
gem install lex-github
```

## Standalone Usage

```ruby
require 'legion/extensions/github'

client = Legion::Extensions::Github::Client.new(token: 'ghp_your_token')

# Repositories
client.list_repos(username: 'octocat')
client.get_repo(owner: 'octocat', repo: 'Hello-World')
client.create_repo(name: 'my-new-repo', private: true)

# Issues
client.list_issues(owner: 'octocat', repo: 'Hello-World')
client.create_issue(owner: 'octocat', repo: 'Hello-World', title: 'Bug report')

# Pull Requests
client.list_pull_requests(owner: 'octocat', repo: 'Hello-World')
client.create_pull_request(owner: 'octocat', repo: 'Hello-World', title: 'Fix', head: 'fix-branch', base: 'main')
client.merge_pull_request(owner: 'octocat', repo: 'Hello-World', pull_number: 42)

# Users
client.get_authenticated_user
client.get_user(username: 'octocat')

# Organizations
client.get_org(org: 'github')
client.list_org_repos(org: 'github')

# Gists
client.list_gists
client.create_gist(files: { 'hello.rb' => { content: 'puts "hello"' } })

# Search
client.search_repositories(query: 'ruby language:ruby')
client.search_issues(query: 'bug label:bug')
```

## Functions

### Repositories
- `list_repos` - List repositories for a user
- `get_repo` - Get a single repository
- `create_repo` - Create a new repository
- `update_repo` - Update repository settings
- `delete_repo` - Delete a repository
- `list_branches` - List branches
- `list_tags` - List tags

### Issues
- `list_issues` - List issues for a repository
- `get_issue` - Get a single issue
- `create_issue` - Create a new issue
- `update_issue` - Update an issue
- `list_issue_comments` - List comments on an issue
- `create_issue_comment` - Create a comment on an issue

### Pull Requests
- `list_pull_requests` - List pull requests
- `get_pull_request` - Get a single pull request
- `create_pull_request` - Create a pull request
- `update_pull_request` - Update a pull request
- `merge_pull_request` - Merge a pull request
- `list_pull_request_commits` - List commits on a PR
- `list_pull_request_files` - List files changed in a PR

### Users
- `get_authenticated_user` - Get the authenticated user
- `get_user` - Get a user by username
- `list_followers` - List followers
- `list_following` - List following

### Organizations
- `list_user_orgs` - List organizations for a user
- `get_org` - Get an organization
- `list_org_repos` - List repos in an organization
- `list_org_members` - List organization members

### Gists
- `list_gists` - List gists
- `get_gist` - Get a single gist
- `create_gist` - Create a gist
- `update_gist` - Update a gist
- `delete_gist` - Delete a gist

### Search
- `search_repositories` - Search repositories
- `search_issues` - Search issues and PRs
- `search_users` - Search users
- `search_code` - Search code

## Requirements

- Ruby >= 3.4
- [LegionIO](https://github.com/LegionIO/LegionIO) framework (optional for standalone usage)
- GitHub personal access token or app token

## License

MIT
