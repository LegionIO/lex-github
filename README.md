# lex-github

GitHub integration for [LegionIO](https://github.com/LegionIO/LegionIO). Provides runners for interacting with the GitHub REST API including repositories, issues, pull requests, labels, comments, commits, users, organizations, gists, search, Actions workflows, checks, releases, deployments, webhooks, and full GitHub App + OAuth authentication.

## Installation

```bash
gem install lex-github
```

## Authentication

### Personal Access Token (PAT)

```ruby
client = Legion::Extensions::Github::Client.new(token: 'ghp_your_token')
```

### GitHub App (JWT + Installation Token)

```ruby
# Set in Legion::Settings
# github.app.app_id: '12345'
# github.app.private_key_path: '/path/to/private-key.pem'
# github.app.installation_id: '67890'

client = Legion::Extensions::Github::Client.new
# Credentials resolved automatically from settings
```

Or via Vault:
```
vault write secret/github/app/app_id value='12345'
vault write secret/github/app/private_key value='-----BEGIN RSA PRIVATE KEY-----...'
vault write secret/github/app/installation_id value='67890'
```

### OAuth Delegated (browser-based login)

```bash
# CLI login
legion lex exec github auth login
```

```ruby
# Programmatic
client = Legion::Extensions::Github::CLI::Auth.new
result = client.login(client_id: 'Iv1.abc', client_secret: 'secret')
# Opens browser → PKCE flow → stores token in Vault
```

### Credential Resolution Chain

lex-github resolves credentials automatically in priority order:

1. Vault OAuth delegated token
2. Settings OAuth access token
3. Vault GitHub App installation token (auto-generates on miss)
4. Settings GitHub App installation token
5. Vault PAT
6. Settings PAT (`github.token`)
7. `gh` CLI token (`gh auth token`)
8. `GITHUB_TOKEN` environment variable

Rate-limited credentials are skipped automatically. Scope-denied credentials (`403`) are skipped for the specific owner/repo and retried with the next source.

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

# GitHub Actions
client.list_workflows(owner: 'octocat', repo: 'Hello-World')
client.trigger_workflow(owner: 'octocat', repo: 'Hello-World', workflow_id: 'ci.yml', ref: 'main')
client.get_workflow_run(owner: 'octocat', repo: 'Hello-World', run_id: 12345)

# Check Runs (CI status)
client.create_check_run(owner: 'octocat', repo: 'Hello-World', name: 'CI', head_sha: 'abc123')
client.update_check_run(owner: 'octocat', repo: 'Hello-World', check_run_id: 1,
                        status: 'completed', conclusion: 'success')

# Releases
client.list_releases(owner: 'octocat', repo: 'Hello-World')
client.create_release(owner: 'octocat', repo: 'Hello-World', tag_name: 'v1.0.0')

# Deployments
client.create_deployment(owner: 'octocat', repo: 'Hello-World', ref: 'main', environment: 'production')
client.create_deployment_status(owner: 'octocat', repo: 'Hello-World', deployment_id: 1, state: 'success')

# Webhooks
client.list_webhooks(owner: 'octocat', repo: 'Hello-World')
client.create_webhook(owner: 'octocat', repo: 'Hello-World',
                      config: { url: 'https://example.com/webhook', content_type: 'json' })

# GitHub App
client.generate_jwt(app_id: '12345', private_key: File.read('private-key.pem'))
client.create_installation_token(jwt: jwt_token, installation_id: '67890')
client.list_installations(jwt: jwt_token)

# Webhook verification
client.verify_signature(payload: request.body.read, signature: request.env['HTTP_X_HUB_SIGNATURE_256'],
                        secret: 'webhook_secret')
```

## Functions

### Repositories
- `list_repos`, `get_repo`, `create_repo`, `update_repo`, `delete_repo`, `list_branches`, `list_tags`

### Issues
- `list_issues`, `get_issue`, `create_issue`, `update_issue`, `list_issue_comments`, `create_issue_comment`

### Pull Requests
- `list_pull_requests`, `get_pull_request`, `create_pull_request`, `update_pull_request`, `merge_pull_request`
- `list_pull_request_commits`, `list_pull_request_files`, `list_pull_request_reviews`, `create_review`

### Labels
- `list_labels`, `get_label`, `create_label`, `update_label`, `delete_label`
- `add_labels_to_issue`, `remove_label_from_issue`

### Comments
- `list_comments`, `get_comment`, `create_comment`, `update_comment`, `delete_comment`

### Users
- `get_authenticated_user`, `get_user`, `list_followers`, `list_following`

### Organizations
- `list_user_orgs`, `get_org`, `list_org_repos`, `list_org_members`

### Gists
- `list_gists`, `get_gist`, `create_gist`, `update_gist`, `delete_gist`

### Search
- `search_repositories`, `search_issues`, `search_users`, `search_code`

### Commits
- `list_commits`, `get_commit`, `compare_commits`

### Branches
- `create_branch`

### Contents
- `commit_files`

### GitHub Actions
- `list_workflows`, `get_workflow`, `list_workflow_runs`, `get_workflow_run`, `trigger_workflow`
- `cancel_workflow_run`, `rerun_workflow`, `rerun_failed_jobs`
- `list_workflow_run_jobs`, `download_workflow_run_logs`, `list_workflow_run_artifacts`

### Checks
- `create_check_run`, `update_check_run`, `get_check_run`
- `list_check_runs_for_ref`, `list_check_suites_for_ref`, `get_check_suite`
- `rerequest_check_suite`, `list_check_run_annotations`

### Releases
- `list_releases`, `get_release`, `get_latest_release`, `get_release_by_tag`
- `create_release`, `update_release`, `delete_release`
- `list_release_assets`, `delete_release_asset`

### Deployments
- `list_deployments`, `get_deployment`, `create_deployment`, `delete_deployment`
- `list_deployment_statuses`, `create_deployment_status`, `get_deployment_status`

### Repository Webhooks
- `list_webhooks`, `get_webhook`, `create_webhook`, `update_webhook`, `delete_webhook`
- `ping_webhook`, `test_webhook`, `list_webhook_deliveries`

### GitHub App Auth
- `generate_jwt`, `create_installation_token`, `list_installations`, `get_installation`
- `generate_manifest`, `exchange_manifest_code`, `manifest_url`
- `verify_signature`, `parse_event`, `receive_event`

### OAuth
- `generate_pkce`, `authorize_url`, `exchange_code`, `refresh_token`
- `request_device_code`, `poll_device_code`, `revoke_token`

## Error Handling

```ruby
begin
  client.get_repo(owner: 'org', repo: 'private-repo')
rescue Legion::Extensions::Github::RateLimitError => e
  puts "Rate limited, resets at: #{e.reset_at}"
rescue Legion::Extensions::Github::ScopeDeniedError => e
  puts "No credential authorized for #{e.owner}/#{e.repo}"
rescue Legion::Extensions::Github::AuthorizationError => e
  puts "All credentials exhausted: #{e.attempted_sources}"
end
```

## Requirements

- Ruby >= 3.4
- [LegionIO](https://github.com/LegionIO/LegionIO) framework (optional for standalone client usage)
- `faraday` >= 2.0
- `jwt` ~> 2.7 (for GitHub App authentication)
- `base64` >= 0.1 (for OAuth PKCE)

## License

MIT
