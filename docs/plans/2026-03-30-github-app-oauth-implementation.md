# GitHub App + OAuth Delegated Auth Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add GitHub App authentication, OAuth delegated user access, and API response caching to lex-github.

**Architecture:** Three nested sub-module namespaces (`Github::App`, `Github::OAuth`, plus shared `Helpers::Cache` and `Helpers::TokenCache`) within the existing lex-github gem. Credential resolution chain walks 8 sources (delegated -> app -> PAT -> CLI -> env) with rate-limit-aware fallback. All API reads go through a two-tier cache (global Redis + local in-memory) with configurable TTLs.

**Tech Stack:** Ruby 3.4+, Faraday, jwt gem (RS256), base64 gem (PKCE), legion-cache, legion-crypt, legion-transport (>= 1.4.5, boundary-walking fix deployed)

**Design doc:** `docs/plans/2026-03-30-github-app-oauth-design.md`

**Pre-requisite:** LegionIO/legion-transport#8 is resolved (deployed to RubyGems 2026-03-30). All 35 tasks can proceed.

---

### Task 1: Add jwt and base64 dependencies

**Files:**
- Modify: `lex-github.gemspec`
- Modify: `Gemfile` (no changes needed, gemspec drives deps)

**Step 1: Add runtime dependencies to gemspec**

In `lex-github.gemspec`, after the existing `spec.add_dependency 'legion-transport'` line, add:

```ruby
spec.add_dependency 'jwt', '~> 2.7'
spec.add_dependency 'base64', '>= 0.1'
```

**Step 2: Run bundle install**

Run: `bundle install`
Expected: Resolves and installs jwt and base64 gems

**Step 3: Commit**

```bash
git add lex-github.gemspec
git commit -m "add jwt and base64 runtime dependencies"
```

---

### Task 2: App::Runners::Auth — JWT generation and installation tokens

**Files:**
- Create: `lib/legion/extensions/github/app/runners/auth.rb`
- Create: `spec/legion/extensions/github/app/runners/auth_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/app/runners/auth_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Auth do
  let(:runner) { Object.new.extend(described_class) }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }

  before { allow(runner).to receive(:connection).and_return(test_connection) }

  describe '#generate_jwt' do
    it 'generates a valid RS256 JWT with app_id as issuer' do
      result = runner.generate_jwt(app_id: '12345', private_key: private_key.to_pem)
      expect(result[:result]).to be_a(String)

      decoded = JWT.decode(result[:result], private_key.public_key, true, algorithm: 'RS256')
      expect(decoded.first['iss']).to eq('12345')
    end

    it 'sets iat to 60 seconds in the past' do
      result = runner.generate_jwt(app_id: '12345', private_key: private_key.to_pem)
      decoded = JWT.decode(result[:result], private_key.public_key, true, algorithm: 'RS256')
      expect(decoded.first['iat']).to be_within(5).of(Time.now.to_i - 60)
    end

    it 'sets exp to 10 minutes from now' do
      result = runner.generate_jwt(app_id: '12345', private_key: private_key.to_pem)
      decoded = JWT.decode(result[:result], private_key.public_key, true, algorithm: 'RS256')
      expect(decoded.first['exp']).to be_within(5).of(Time.now.to_i + 600)
    end
  end

  describe '#create_installation_token' do
    it 'exchanges a JWT for an installation access token' do
      stubs.post('/app/installations/67890/access_tokens') do
        [201, { 'Content-Type' => 'application/json' },
         { 'token' => 'ghs_test123', 'expires_at' => '2026-03-30T12:00:00Z' }]
      end

      result = runner.create_installation_token(jwt: 'fake-jwt', installation_id: '67890')
      expect(result[:result]['token']).to eq('ghs_test123')
      expect(result[:result]['expires_at']).to eq('2026-03-30T12:00:00Z')
    end
  end

  describe '#list_installations' do
    it 'lists installations for the authenticated app' do
      stubs.get('/app/installations') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 67890, 'account' => { 'login' => 'LegionIO' } }]]
      end

      result = runner.list_installations(jwt: 'fake-jwt')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['id']).to eq(67890)
    end
  end

  describe '#get_installation' do
    it 'returns a single installation' do
      stubs.get('/app/installations/67890') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 67890, 'account' => { 'login' => 'LegionIO' } }]
      end

      result = runner.get_installation(jwt: 'fake-jwt', installation_id: '67890')
      expect(result[:result]['id']).to eq(67890)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/auth_spec.rb`
Expected: FAIL — cannot load file or constant not defined

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/app/runners/auth.rb`:

```ruby
# frozen_string_literal: true

require 'jwt'
require 'openssl'
require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Auth
            include Legion::Extensions::Github::Helpers::Client

            def generate_jwt(app_id:, private_key:, **)
              key = OpenSSL::PKey::RSA.new(private_key)
              now = Time.now.to_i
              payload = { iat: now - 60, exp: now + (10 * 60), iss: app_id.to_s }
              token = JWT.encode(payload, key, 'RS256')
              { result: token }
            end

            def create_installation_token(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.post("/app/installations/#{installation_id}/access_tokens")
              { result: response.body }
            end

            def list_installations(jwt:, per_page: 30, page: 1, **)
              conn = connection(token: jwt, **)
              response = conn.get('/app/installations', per_page: per_page, page: page)
              { result: response.body }
            end

            def get_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.get("/app/installations/#{installation_id}")
              { result: response.body }
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
```

**Step 4: Require the new module in the extension entry point**

In `lib/legion/extensions/github.rb`, add before `require 'legion/extensions/github/client'`:

```ruby
require 'legion/extensions/github/app/runners/auth'
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/auth_spec.rb`
Expected: All 5 examples pass

**Step 6: Run full test suite to check for regressions**

Run: `bundle exec rspec`
Expected: All existing tests still pass + new tests pass

**Step 7: Commit**

```bash
git add lib/legion/extensions/github/app/runners/auth.rb \
        spec/legion/extensions/github/app/runners/auth_spec.rb \
        lib/legion/extensions/github.rb
git commit -m "add App::Runners::Auth for JWT generation and installation tokens"
```

---

### Task 3: App::Runners::Webhooks — signature verification and event parsing

**Files:**
- Create: `lib/legion/extensions/github/app/runners/webhooks.rb`
- Create: `spec/legion/extensions/github/app/runners/webhooks_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/app/runners/webhooks_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Webhooks do
  let(:runner) { Object.new.extend(described_class) }
  let(:webhook_secret) { 'test-webhook-secret' }
  let(:payload) { '{"action":"opened","number":1}' }
  let(:valid_signature) { "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, payload)}" }

  describe '#verify_signature' do
    it 'returns true for a valid signature' do
      result = runner.verify_signature(payload: payload, signature: valid_signature, secret: webhook_secret)
      expect(result[:result]).to be true
    end

    it 'returns false for an invalid signature' do
      result = runner.verify_signature(payload: payload, signature: 'sha256=invalid', secret: webhook_secret)
      expect(result[:result]).to be false
    end

    it 'returns false for a nil signature' do
      result = runner.verify_signature(payload: payload, signature: nil, secret: webhook_secret)
      expect(result[:result]).to be false
    end
  end

  describe '#parse_event' do
    it 'parses a webhook payload with event metadata' do
      result = runner.parse_event(
        payload: payload,
        event_type: 'pull_request',
        delivery_id: 'abc-123'
      )
      expect(result[:result][:event_type]).to eq('pull_request')
      expect(result[:result][:delivery_id]).to eq('abc-123')
      expect(result[:result][:payload]['action']).to eq('opened')
    end
  end

  describe '#receive_event' do
    it 'verifies signature and parses event in one call' do
      result = runner.receive_event(
        payload: payload,
        signature: valid_signature,
        secret: webhook_secret,
        event_type: 'issues',
        delivery_id: 'def-456'
      )
      expect(result[:result][:verified]).to be true
      expect(result[:result][:event_type]).to eq('issues')
      expect(result[:result][:payload]['action']).to eq('opened')
    end

    it 'rejects events with invalid signatures' do
      result = runner.receive_event(
        payload: payload,
        signature: 'sha256=bad',
        secret: webhook_secret,
        event_type: 'issues',
        delivery_id: 'def-456'
      )
      expect(result[:result][:verified]).to be false
      expect(result[:result][:payload]).to be_nil
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/webhooks_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/app/runners/webhooks.rb`:

```ruby
# frozen_string_literal: true

require 'openssl'
require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Webhooks
            include Legion::Extensions::Github::Helpers::Client

            def verify_signature(payload:, signature:, secret:, **)
              return { result: false } if signature.nil? || signature.empty?

              expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"
              { result: Rack::Utils.secure_compare(expected, signature) }
            rescue NameError
              { result: expected == signature }
            end

            def parse_event(payload:, event_type:, delivery_id:, **)
              parsed = payload.is_a?(String) ? Legion::JSON.load(payload) : payload
              { result: { event_type: event_type, delivery_id: delivery_id, payload: parsed } }
            end

            def receive_event(payload:, signature:, secret:, event_type:, delivery_id:, **)
              verified = verify_signature(payload: payload, signature: signature, secret: secret)[:result]
              return { result: { verified: false, event_type: event_type, delivery_id: delivery_id, payload: nil } } unless verified

              parsed = parse_event(payload: payload, event_type: event_type, delivery_id: delivery_id)[:result]
              { result: parsed.merge(verified: true) }
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
```

**Step 4: Require in entry point**

In `lib/legion/extensions/github.rb`, add:

```ruby
require 'legion/extensions/github/app/runners/webhooks'
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/webhooks_spec.rb`
Expected: All 5 examples pass

**Step 6: Full suite**

Run: `bundle exec rspec`
Expected: All pass

**Step 7: Commit**

```bash
git add lib/legion/extensions/github/app/runners/webhooks.rb \
        spec/legion/extensions/github/app/runners/webhooks_spec.rb \
        lib/legion/extensions/github.rb
git commit -m "add App::Runners::Webhooks for signature verification and event parsing"
```

---

### Task 4: App::Runners::Manifest — GitHub App manifest flow

**Files:**
- Create: `lib/legion/extensions/github/app/runners/manifest.rb`
- Create: `spec/legion/extensions/github/app/runners/manifest_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/app/runners/manifest_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Manifest do
  let(:runner) { Object.new.extend(described_class) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(runner).to receive(:connection).and_return(test_connection) }

  describe '#generate_manifest' do
    it 'builds a manifest hash with required fields' do
      result = runner.generate_manifest(
        name: 'LegionIO Bot',
        url: 'https://legionio.dev',
        webhook_url: 'https://legion.example.com/api/hooks/lex/github/app/webhook',
        callback_url: 'https://legion.example.com/api/hooks/lex/github/app/setup/callback'
      )
      manifest = result[:result]
      expect(manifest[:name]).to eq('LegionIO Bot')
      expect(manifest[:url]).to eq('https://legionio.dev')
      expect(manifest[:hook_attributes][:url]).to eq('https://legion.example.com/api/hooks/lex/github/app/webhook')
      expect(manifest[:setup_url]).to include('setup/callback')
      expect(manifest[:default_permissions]).to be_a(Hash)
      expect(manifest[:default_events]).to be_an(Array)
    end
  end

  describe '#exchange_manifest_code' do
    it 'converts a manifest code into app credentials' do
      stubs.post('/app-manifests/test-code/conversions') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 12345, 'client_id' => 'Iv1.abc', 'client_secret' => 'secret',
           'pem' => '-----BEGIN RSA PRIVATE KEY-----...', 'webhook_secret' => 'whsec' }]
      end

      result = runner.exchange_manifest_code(code: 'test-code')
      expect(result[:result]['id']).to eq(12345)
      expect(result[:result]['pem']).to start_with('-----BEGIN')
    end
  end

  describe '#manifest_url' do
    it 'returns the GitHub manifest creation URL' do
      result = runner.generate_manifest(
        name: 'Test', url: 'https://test.com',
        webhook_url: 'https://test.com/webhook',
        callback_url: 'https://test.com/callback'
      )
      url = runner.manifest_url(manifest: result[:result])
      expect(url[:result]).to start_with('https://github.com/settings/apps/new')
    end

    it 'supports org-scoped manifest URL' do
      result = runner.generate_manifest(
        name: 'Test', url: 'https://test.com',
        webhook_url: 'https://test.com/webhook',
        callback_url: 'https://test.com/callback'
      )
      url = runner.manifest_url(manifest: result[:result], org: 'LegionIO')
      expect(url[:result]).to include('/organizations/LegionIO/settings/apps/new')
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/manifest_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/app/runners/manifest.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Manifest
            include Legion::Extensions::Github::Helpers::Client

            DEFAULT_PERMISSIONS = {
              contents: 'write', issues: 'write', pull_requests: 'write',
              metadata: 'read', administration: 'write', members: 'read',
              checks: 'write', statuses: 'write', actions: 'read',
              workflows: 'write', webhooks: 'write', repository_hooks: 'write'
            }.freeze

            DEFAULT_EVENTS = %w[
              push pull_request pull_request_review issues issue_comment
              create delete check_run check_suite status workflow_run
              repository installation
            ].freeze

            def generate_manifest(name:, url:, webhook_url:, callback_url:,
                                  permissions: DEFAULT_PERMISSIONS, events: DEFAULT_EVENTS,
                                  public: true, **)
              manifest = {
                name: name, url: url, public: public,
                hook_attributes: { url: webhook_url, active: true },
                setup_url: callback_url,
                redirect_url: callback_url,
                default_permissions: permissions,
                default_events: events
              }
              { result: manifest }
            end

            def exchange_manifest_code(code:, **)
              conn = connection(**)
              response = conn.post("/app-manifests/#{code}/conversions")
              { result: response.body }
            end

            def manifest_url(manifest:, org: nil, **)
              base = if org
                       "https://github.com/organizations/#{org}/settings/apps/new"
                     else
                       'https://github.com/settings/apps/new'
                     end
              { result: "#{base}?manifest=#{URI.encode_www_form_component(Legion::JSON.dump(manifest))}" }
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
```

**Step 4: Require in entry point**

In `lib/legion/extensions/github.rb`, add:

```ruby
require 'legion/extensions/github/app/runners/manifest'
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/manifest_spec.rb`
Expected: All 4 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/app/runners/manifest.rb \
        spec/legion/extensions/github/app/runners/manifest_spec.rb \
        lib/legion/extensions/github.rb
git commit -m "add App::Runners::Manifest for GitHub App manifest registration flow"
```

---

### Task 5: OAuth::Runners::Auth — delegated OAuth with PKCE and device code

**Files:**
- Create: `lib/legion/extensions/github/oauth/runners/auth.rb`
- Create: `spec/legion/extensions/github/oauth/runners/auth_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/oauth/runners/auth_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::OAuth::Runners::Auth do
  let(:runner) { Object.new.extend(described_class) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:oauth_connection) do
    Faraday.new(url: 'https://github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(runner).to receive(:oauth_connection).and_return(oauth_connection) }

  describe '#generate_pkce' do
    it 'returns a verifier and challenge pair' do
      result = runner.generate_pkce
      expect(result[:result][:verifier]).to be_a(String)
      expect(result[:result][:verifier].length).to be >= 43
      expect(result[:result][:challenge]).to be_a(String)
      expect(result[:result][:challenge_method]).to eq('S256')
    end
  end

  describe '#authorize_url' do
    it 'returns a properly formatted GitHub OAuth URL' do
      url = runner.authorize_url(
        client_id: 'Iv1.abc',
        redirect_uri: 'http://localhost:12345/callback',
        scope: 'repo admin:org',
        state: 'random-state',
        code_challenge: 'challenge123',
        code_challenge_method: 'S256'
      )
      expect(url[:result]).to start_with('https://github.com/login/oauth/authorize?')
      expect(url[:result]).to include('client_id=Iv1.abc')
      expect(url[:result]).to include('scope=repo')
      expect(url[:result]).to include('state=random-state')
    end
  end

  describe '#exchange_code' do
    it 'exchanges an authorization code for tokens' do
      stubs.post('/login/oauth/access_token') do
        [200, { 'Content-Type' => 'application/json' },
         { 'access_token' => 'ghu_test', 'refresh_token' => 'ghr_test',
           'token_type' => 'bearer', 'expires_in' => 28800 }]
      end

      result = runner.exchange_code(
        client_id: 'Iv1.abc', client_secret: 'secret',
        code: 'auth-code', redirect_uri: 'http://localhost/callback',
        code_verifier: 'verifier123'
      )
      expect(result[:result]['access_token']).to eq('ghu_test')
      expect(result[:result]['refresh_token']).to eq('ghr_test')
    end
  end

  describe '#refresh_token' do
    it 'exchanges a refresh token for new tokens' do
      stubs.post('/login/oauth/access_token') do
        [200, { 'Content-Type' => 'application/json' },
         { 'access_token' => 'ghu_new', 'refresh_token' => 'ghr_new',
           'token_type' => 'bearer', 'expires_in' => 28800 }]
      end

      result = runner.refresh_token(
        client_id: 'Iv1.abc', client_secret: 'secret',
        refresh_token: 'ghr_test'
      )
      expect(result[:result]['access_token']).to eq('ghu_new')
    end
  end

  describe '#request_device_code' do
    it 'requests a device code for headless auth' do
      stubs.post('/login/device/code') do
        [200, { 'Content-Type' => 'application/json' },
         { 'device_code' => 'dc_123', 'user_code' => 'ABCD-1234',
           'verification_uri' => 'https://github.com/login/device',
           'expires_in' => 900, 'interval' => 5 }]
      end

      result = runner.request_device_code(client_id: 'Iv1.abc', scope: 'repo')
      expect(result[:result]['user_code']).to eq('ABCD-1234')
    end
  end

  describe '#poll_device_code' do
    it 'returns token when authorization completes' do
      stubs.post('/login/oauth/access_token') do
        [200, { 'Content-Type' => 'application/json' },
         { 'access_token' => 'ghu_device', 'token_type' => 'bearer' }]
      end

      result = runner.poll_device_code(
        client_id: 'Iv1.abc', device_code: 'dc_123',
        interval: 0, timeout: 5
      )
      expect(result[:result]['access_token']).to eq('ghu_device')
    end

    it 'returns timeout error when deadline exceeded' do
      stubs.post('/login/oauth/access_token') do
        [200, { 'Content-Type' => 'application/json' },
         { 'error' => 'authorization_pending' }]
      end

      result = runner.poll_device_code(
        client_id: 'Iv1.abc', device_code: 'dc_123',
        interval: 0, timeout: 0
      )
      expect(result[:error]).to eq('timeout')
    end
  end

  describe '#revoke_token' do
    it 'revokes an access token' do
      stubs.delete('/applications/Iv1.abc/token') do
        [204, {}, '']
      end

      result = runner.revoke_token(client_id: 'Iv1.abc', client_secret: 'secret', access_token: 'ghu_test')
      expect(result[:result]).to be true
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/oauth/runners/auth_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/oauth/runners/auth.rb`:

```ruby
# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'securerandom'
require 'uri'
require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module OAuth
        module Runners
          module Auth
            include Legion::Extensions::Github::Helpers::Client

            def generate_pkce(**)
              verifier = SecureRandom.urlsafe_base64(32)
              challenge = ::Base64.urlsafe_encode64(
                OpenSSL::Digest::SHA256.digest(verifier), padding: false
              )
              { result: { verifier: verifier, challenge: challenge, challenge_method: 'S256' } }
            end

            def authorize_url(client_id:, redirect_uri:, scope:, state:,
                              code_challenge:, code_challenge_method: 'S256', **)
              params = URI.encode_www_form(
                client_id: client_id, redirect_uri: redirect_uri,
                scope: scope, state: state,
                code_challenge: code_challenge,
                code_challenge_method: code_challenge_method
              )
              { result: "https://github.com/login/oauth/authorize?#{params}" }
            end

            def exchange_code(client_id:, client_secret:, code:, redirect_uri:, code_verifier:, **)
              response = oauth_connection.post('/login/oauth/access_token', {
                                                client_id: client_id, client_secret: client_secret,
                                                code: code, redirect_uri: redirect_uri,
                                                code_verifier: code_verifier
                                              })
              { result: response.body }
            end

            def refresh_token(client_id:, client_secret:, refresh_token:, **)
              response = oauth_connection.post('/login/oauth/access_token', {
                                                client_id: client_id, client_secret: client_secret,
                                                refresh_token: refresh_token,
                                                grant_type: 'refresh_token'
                                              })
              { result: response.body }
            end

            def request_device_code(client_id:, scope: 'repo', **)
              response = oauth_connection.post('/login/device/code', {
                                                client_id: client_id, scope: scope
                                              })
              { result: response.body }
            end

            def poll_device_code(client_id:, device_code:, interval: 5, timeout: 300, **)
              deadline = Time.now + timeout
              current_interval = interval

              loop do
                response = oauth_connection.post('/login/oauth/access_token', {
                                                   client_id: client_id,
                                                   device_code: device_code,
                                                   grant_type: 'urn:ietf:params:oauth:grant-type:device_code'
                                                 })
                body = response.body
                return { result: body } if body['access_token']

                case body['error']
                when 'authorization_pending'
                  return { error: 'timeout', description: "Device code flow timed out after #{timeout}s" } if Time.now > deadline

                  sleep(current_interval) unless current_interval.zero?
                when 'slow_down'
                  current_interval += 5
                  sleep(current_interval) unless current_interval.zero?
                else
                  return { error: body['error'], description: body['error_description'] }
                end
              end
            end

            def revoke_token(client_id:, client_secret:, access_token:, **)
              conn = Faraday.new(url: 'https://api.github.com') do |f|
                f.request :json
                f.request :authorization, :basic, client_id, client_secret
                f.response :json, content_type: /\bjson$/
              end
              response = conn.delete("/applications/#{client_id}/token", { access_token: access_token })
              { result: response.status == 204 }
            end

            def oauth_connection(**)
              Faraday.new(url: 'https://github.com') do |conn|
                conn.request :json
                conn.response :json, content_type: /\bjson$/
                conn.headers['Accept'] = 'application/json'
              end
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
```

**Step 4: Require in entry point**

In `lib/legion/extensions/github.rb`, add:

```ruby
require 'legion/extensions/github/oauth/runners/auth'
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/oauth/runners/auth_spec.rb`
Expected: All 8 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/oauth/runners/auth.rb \
        spec/legion/extensions/github/oauth/runners/auth_spec.rb \
        lib/legion/extensions/github.rb
git commit -m "add OAuth::Runners::Auth for delegated OAuth with PKCE and device code"
```

---

### Task 6: Helpers::Cache — two-tier read-through/write-through caching

**Files:**
- Create: `lib/legion/extensions/github/helpers/cache.rb`
- Create: `spec/legion/extensions/github/helpers/cache_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/helpers/cache_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Helpers::Cache do
  let(:helper) { Object.new.extend(described_class) }

  before do
    allow(helper).to receive(:cache_connected?).and_return(false)
    allow(helper).to receive(:local_cache_connected?).and_return(false)
  end

  describe '#cached_get' do
    it 'calls the block when no cache is connected' do
      result = helper.cached_get('github:repo:test/repo') { { 'name' => 'repo' } }
      expect(result).to eq({ 'name' => 'repo' })
    end

    context 'with global cache connected' do
      before do
        allow(helper).to receive(:cache_connected?).and_return(true)
        allow(helper).to receive(:cache_set)
      end

      it 'returns cached value on hit' do
        allow(helper).to receive(:cache_get).with('github:repo:test/repo').and_return({ 'name' => 'cached' })
        result = helper.cached_get('github:repo:test/repo') { { 'name' => 'fresh' } }
        expect(result).to eq({ 'name' => 'cached' })
      end

      it 'calls block and writes to cache on miss' do
        allow(helper).to receive(:cache_get).with('github:repo:test/repo').and_return(nil)
        expect(helper).to receive(:cache_set).with('github:repo:test/repo', { 'name' => 'fresh' }, ttl: 600)
        helper.cached_get('github:repo:test/repo', ttl: 600) { { 'name' => 'fresh' } }
      end
    end

    context 'with local cache connected' do
      before do
        allow(helper).to receive(:local_cache_connected?).and_return(true)
        allow(helper).to receive(:local_cache_set)
      end

      it 'returns local cached value on hit' do
        allow(helper).to receive(:local_cache_get).with('github:repo:test/repo').and_return({ 'name' => 'local' })
        result = helper.cached_get('github:repo:test/repo') { { 'name' => 'fresh' } }
        expect(result).to eq({ 'name' => 'local' })
      end
    end

    context 'with both caches connected' do
      before do
        allow(helper).to receive(:cache_connected?).and_return(true)
        allow(helper).to receive(:local_cache_connected?).and_return(true)
        allow(helper).to receive(:cache_set)
        allow(helper).to receive(:local_cache_set)
      end

      it 'checks global first, then local' do
        allow(helper).to receive(:cache_get).and_return(nil)
        allow(helper).to receive(:local_cache_get).and_return({ 'name' => 'local' })
        result = helper.cached_get('github:repo:test/repo') { { 'name' => 'fresh' } }
        expect(result).to eq({ 'name' => 'local' })
      end

      it 'writes to both caches on miss' do
        allow(helper).to receive(:cache_get).and_return(nil)
        allow(helper).to receive(:local_cache_get).and_return(nil)
        expect(helper).to receive(:cache_set)
        expect(helper).to receive(:local_cache_set)
        helper.cached_get('github:repo:test/repo') { { 'name' => 'fresh' } }
      end
    end
  end

  describe '#cache_write' do
    it 'writes to both caches when connected' do
      allow(helper).to receive(:cache_connected?).and_return(true)
      allow(helper).to receive(:local_cache_connected?).and_return(true)
      expect(helper).to receive(:cache_set).with('github:repo:test/repo', { 'name' => 'new' }, ttl: 300)
      expect(helper).to receive(:local_cache_set).with('github:repo:test/repo', { 'name' => 'new' }, ttl: 300)
      helper.cache_write('github:repo:test/repo', { 'name' => 'new' }, ttl: 300)
    end

    it 'skips disconnected caches silently' do
      helper.cache_write('github:repo:test/repo', { 'name' => 'new' })
    end
  end

  describe '#cache_invalidate' do
    it 'deletes from both caches when connected' do
      allow(helper).to receive(:cache_connected?).and_return(true)
      allow(helper).to receive(:local_cache_connected?).and_return(true)
      expect(helper).to receive(:cache_delete).with('github:repo:test/repo')
      expect(helper).to receive(:local_cache_delete).with('github:repo:test/repo')
      helper.cache_invalidate('github:repo:test/repo')
    end
  end

  describe '#github_ttl_for' do
    it 'returns default TTL for unknown key patterns' do
      expect(helper.github_ttl_for('github:unknown:key')).to eq(300)
    end

    it 'returns commit TTL for commit keys' do
      expect(helper.github_ttl_for('github:repo:test/repo:commits:abc123')).to eq(86_400)
    end

    it 'returns pull_request TTL for PR keys' do
      expect(helper.github_ttl_for('github:repo:test/repo:pulls:1')).to eq(60)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/cache_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/helpers/cache.rb`:

```ruby
# frozen_string_literal: true

require 'legion/cache/helper'

module Legion
  module Extensions
    module Github
      module Helpers
        module Cache
          include Legion::Cache::Helper

          DEFAULT_TTLS = {
            repo: 600, issue: 120, pull_request: 60, commit: 86_400,
            branch: 120, user: 3600, org: 3600, search: 60
          }.freeze

          DEFAULT_TTL = 300

          def cached_get(cache_key, ttl: nil, &block)
            if cache_connected?
              result = cache_get(cache_key)
              return result if result
            end

            if local_cache_connected?
              result = local_cache_get(cache_key)
              return result if result
            end

            result = yield
            effective_ttl = ttl || github_ttl_for(cache_key)
            cache_set(cache_key, result, ttl: effective_ttl) if cache_connected?
            local_cache_set(cache_key, result, ttl: effective_ttl) if local_cache_connected?
            result
          end

          def cache_write(cache_key, value, ttl: nil)
            effective_ttl = ttl || github_ttl_for(cache_key)
            cache_set(cache_key, value, ttl: effective_ttl) if cache_connected?
            local_cache_set(cache_key, value, ttl: effective_ttl) if local_cache_connected?
          end

          def cache_invalidate(cache_key)
            cache_delete(cache_key) if cache_connected?
            local_cache_delete(cache_key) if local_cache_connected?
          end

          def github_ttl_for(cache_key)
            configured_ttls = github_cache_ttls
            case cache_key
            when /:commits:/ then configured_ttls[:commit]
            when /:pulls:/   then configured_ttls[:pull_request]
            when /:issues:/  then configured_ttls[:issue]
            when /:branches:/ then configured_ttls[:branch]
            when /\Agithub:user:/ then configured_ttls[:user]
            when /\Agithub:org:/  then configured_ttls[:org]
            when /\Agithub:repo:[^:]+\z/ then configured_ttls[:repo]
            when /:search:/  then configured_ttls[:search]
            else configured_ttls.fetch(:default, DEFAULT_TTL)
            end
          end

          private

          def github_cache_ttls
            return DEFAULT_TTLS.merge(default: DEFAULT_TTL) unless defined?(Legion::Settings)

            overrides = Legion::Settings.dig(:github, :cache, :ttls) || {}
            DEFAULT_TTLS.merge(default: DEFAULT_TTL).merge(overrides.transform_keys(&:to_sym))
          rescue StandardError
            DEFAULT_TTLS.merge(default: DEFAULT_TTL)
          end
        end
      end
    end
  end
end
```

**Step 4: Require in entry point**

In `lib/legion/extensions/github.rb`, add before the runner requires:

```ruby
require 'legion/extensions/github/helpers/cache'
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/cache_spec.rb`
Expected: All 10 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/helpers/cache.rb \
        spec/legion/extensions/github/helpers/cache_spec.rb \
        lib/legion/extensions/github.rb
git commit -m "add Helpers::Cache for two-tier read-through/write-through API caching"
```

---

### Task 7: Helpers::TokenCache — credential lifecycle management

**Files:**
- Create: `lib/legion/extensions/github/helpers/token_cache.rb`
- Create: `spec/legion/extensions/github/helpers/token_cache_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/helpers/token_cache_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Helpers::TokenCache do
  let(:helper) { Object.new.extend(described_class) }

  before do
    allow(helper).to receive(:cache_connected?).and_return(false)
    allow(helper).to receive(:local_cache_connected?).and_return(true)
    allow(helper).to receive(:local_cache_get).and_return(nil)
    allow(helper).to receive(:local_cache_set)
  end

  describe '#store_token' do
    it 'stores a token with auth_type and expires_at' do
      expect(helper).to receive(:local_cache_set).with(
        'github:token:app_installation',
        hash_including(token: 'ghs_test', auth_type: :app_installation),
        ttl: anything
      )
      helper.store_token(token: 'ghs_test', auth_type: :app_installation,
                         expires_at: Time.now + 3600)
    end
  end

  describe '#fetch_token' do
    it 'returns nil when no token is cached' do
      expect(helper.fetch_token(auth_type: :app_installation)).to be_nil
    end

    it 'returns the cached token when present and not expired' do
      cached = { token: 'ghs_test', auth_type: :app_installation,
                 expires_at: (Time.now + 3600).iso8601 }
      allow(helper).to receive(:local_cache_get).and_return(cached)
      result = helper.fetch_token(auth_type: :app_installation)
      expect(result[:token]).to eq('ghs_test')
    end

    it 'returns nil when token is expired' do
      cached = { token: 'ghs_test', auth_type: :app_installation,
                 expires_at: (Time.now - 60).iso8601 }
      allow(helper).to receive(:local_cache_get).and_return(cached)
      expect(helper.fetch_token(auth_type: :app_installation)).to be_nil
    end
  end

  describe '#mark_rate_limited' do
    it 'stores rate limit info for a credential' do
      expect(helper).to receive(:local_cache_set).with(
        'github:rate_limit:app_installation',
        hash_including(reset_at: anything),
        ttl: anything
      )
      helper.mark_rate_limited(auth_type: :app_installation,
                               reset_at: Time.now + 300)
    end
  end

  describe '#rate_limited?' do
    it 'returns false when no rate limit is recorded' do
      expect(helper.rate_limited?(auth_type: :app_installation)).to be false
    end

    it 'returns true when rate limited' do
      allow(helper).to receive(:local_cache_get)
        .with('github:rate_limit:app_installation')
        .and_return({ reset_at: (Time.now + 300).iso8601 })
      expect(helper.rate_limited?(auth_type: :app_installation)).to be true
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/token_cache_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/helpers/token_cache.rb`:

```ruby
# frozen_string_literal: true

require 'legion/cache/helper'

module Legion
  module Extensions
    module Github
      module Helpers
        module TokenCache
          include Legion::Cache::Helper

          TOKEN_BUFFER_SECONDS = 300

          def store_token(token:, auth_type:, expires_at:, metadata: {}, **)
            entry = { token: token, auth_type: auth_type,
                      expires_at: expires_at.respond_to?(:iso8601) ? expires_at.iso8601 : expires_at,
                      metadata: metadata }
            ttl = [(expires_at.respond_to?(:to_i) ? expires_at.to_i - Time.now.to_i : 3600), 60].max
            key = "github:token:#{auth_type}"
            cache_set(key, entry, ttl: ttl) if cache_connected?
            local_cache_set(key, entry, ttl: ttl) if local_cache_connected?
          end

          def fetch_token(auth_type:, **)
            key = "github:token:#{auth_type}"
            entry = if cache_connected?
                      cache_get(key)
                    elsif local_cache_connected?
                      local_cache_get(key)
                    end
            return nil unless entry

            expires = Time.parse(entry[:expires_at]) rescue nil
            return nil if expires && expires < Time.now + TOKEN_BUFFER_SECONDS

            entry
          end

          def mark_rate_limited(auth_type:, reset_at:, **)
            entry = { reset_at: reset_at.respond_to?(:iso8601) ? reset_at.iso8601 : reset_at }
            ttl = [(reset_at.respond_to?(:to_i) ? reset_at.to_i - Time.now.to_i : 300), 10].max
            key = "github:rate_limit:#{auth_type}"
            cache_set(key, entry, ttl: ttl) if cache_connected?
            local_cache_set(key, entry, ttl: ttl) if local_cache_connected?
          end

          def rate_limited?(auth_type:, **)
            key = "github:rate_limit:#{auth_type}"
            entry = if cache_connected?
                      cache_get(key)
                    elsif local_cache_connected?
                      local_cache_get(key)
                    end
            return false unless entry

            reset = Time.parse(entry[:reset_at]) rescue nil
            reset.nil? || reset > Time.now
          end
        end
      end
    end
  end
end
```

**Step 4: Require in entry point**

In `lib/legion/extensions/github.rb`, add:

```ruby
require 'legion/extensions/github/helpers/token_cache'
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/token_cache_spec.rb`
Expected: All 6 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/helpers/token_cache.rb \
        spec/legion/extensions/github/helpers/token_cache_spec.rb \
        lib/legion/extensions/github.rb
git commit -m "add Helpers::TokenCache for credential lifecycle and rate limit tracking"
```

---

### Task 8: Helpers::ScopeRegistry — credential authorization cache

**Files:**
- Create: `lib/legion/extensions/github/helpers/scope_registry.rb`
- Create: `spec/legion/extensions/github/helpers/scope_registry_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/helpers/scope_registry_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Helpers::ScopeRegistry do
  let(:registry) { Object.new.extend(described_class) }

  before do
    allow(registry).to receive(:cache_connected?).and_return(false)
    allow(registry).to receive(:local_cache_connected?).and_return(false)
  end

  describe '#credential_fingerprint' do
    it 'generates a stable fingerprint from auth_type and identifier' do
      fp = registry.credential_fingerprint(auth_type: :oauth_user, identifier: 'vault_delegated')
      expect(fp).to be_a(String)
      expect(fp).not_to be_empty
    end

    it 'generates different fingerprints for different credentials' do
      fp1 = registry.credential_fingerprint(auth_type: :oauth_user, identifier: 'vault')
      fp2 = registry.credential_fingerprint(auth_type: :pat, identifier: 'vault')
      expect(fp1).not_to eq(fp2)
    end
  end

  describe '#scope_status' do
    it 'returns :unknown when no registry entry exists' do
      result = registry.scope_status(fingerprint: 'fp1', owner: 'OrgZ')
      expect(result).to eq(:unknown)
    end

    it 'returns :authorized after registering authorization' do
      allow(registry).to receive(:local_cache_connected?).and_return(true)
      allow(registry).to receive(:local_cache_get).and_return(nil)
      allow(registry).to receive(:local_cache_set)
      registry.register_scope(fingerprint: 'fp1', owner: 'OrgZ', status: :authorized)
      allow(registry).to receive(:local_cache_get)
        .with('github:scope:fp1:OrgZ').and_return(:authorized)
      expect(registry.scope_status(fingerprint: 'fp1', owner: 'OrgZ')).to eq(:authorized)
    end

    it 'returns :denied after registering denial' do
      allow(registry).to receive(:local_cache_connected?).and_return(true)
      allow(registry).to receive(:local_cache_get).and_return(nil)
      allow(registry).to receive(:local_cache_set)
      registry.register_scope(fingerprint: 'fp1', owner: 'OrgZ', status: :denied)
      allow(registry).to receive(:local_cache_get)
        .with('github:scope:fp1:OrgZ').and_return(:denied)
      expect(registry.scope_status(fingerprint: 'fp1', owner: 'OrgZ')).to eq(:denied)
    end

    it 'checks repo-level scope when repo is provided' do
      allow(registry).to receive(:local_cache_connected?).and_return(true)
      allow(registry).to receive(:local_cache_get)
        .with('github:scope:fp1:OrgZ/repo1').and_return(:authorized)
      expect(registry.scope_status(fingerprint: 'fp1', owner: 'OrgZ', repo: 'repo1'))
        .to eq(:authorized)
    end

    it 'falls back to org-level when repo-level is unknown' do
      allow(registry).to receive(:local_cache_connected?).and_return(true)
      allow(registry).to receive(:local_cache_get)
        .with('github:scope:fp1:OrgZ/repo1').and_return(nil)
      allow(registry).to receive(:cache_connected?).and_return(false)
      allow(registry).to receive(:local_cache_get)
        .with('github:scope:fp1:OrgZ').and_return(:authorized)
      expect(registry.scope_status(fingerprint: 'fp1', owner: 'OrgZ', repo: 'repo1'))
        .to eq(:authorized)
    end
  end

  describe '#rate_limited?' do
    it 'returns false when no rate limit is cached' do
      expect(registry.rate_limited?(fingerprint: 'fp1')).to be false
    end

    it 'returns true when rate limit is cached' do
      allow(registry).to receive(:local_cache_connected?).and_return(true)
      allow(registry).to receive(:local_cache_get)
        .with('github:rate_limit:fp1').and_return({ reset_at: Time.now + 300 })
      expect(registry.rate_limited?(fingerprint: 'fp1')).to be true
    end
  end

  describe '#mark_rate_limited' do
    it 'stores rate limit with TTL matching reset window' do
      allow(registry).to receive(:local_cache_connected?).and_return(true)
      reset_at = Time.now + 300
      expect(registry).to receive(:local_cache_set)
        .with('github:rate_limit:fp1', hash_including(reset_at: reset_at), ttl: anything)
      registry.mark_rate_limited(fingerprint: 'fp1', reset_at: reset_at)
    end
  end

  describe '#invalidate_scope' do
    it 'deletes scope entries for owner' do
      allow(registry).to receive(:cache_connected?).and_return(true)
      allow(registry).to receive(:local_cache_connected?).and_return(true)
      expect(registry).to receive(:cache_delete).with('github:scope:fp1:OrgZ')
      expect(registry).to receive(:local_cache_delete).with('github:scope:fp1:OrgZ')
      registry.invalidate_scope(fingerprint: 'fp1', owner: 'OrgZ')
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/scope_registry_spec.rb`
Expected: FAIL — file does not exist

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/helpers/scope_registry.rb`:

```ruby
# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Github
      module Helpers
        module ScopeRegistry
          def credential_fingerprint(auth_type:, identifier:)
            Digest::SHA256.hexdigest("#{auth_type}:#{identifier}")[0, 16]
          end

          def scope_status(fingerprint:, owner:, repo: nil)
            if repo
              status = scope_cache_get("github:scope:#{fingerprint}:#{owner}/#{repo}")
              return status if status
            end

            scope_cache_get("github:scope:#{fingerprint}:#{owner}") || :unknown
          end

          def register_scope(fingerprint:, owner:, repo: nil, status:)
            key = repo ? "github:scope:#{fingerprint}:#{owner}/#{repo}" : "github:scope:#{fingerprint}:#{owner}"
            ttl = status == :denied ? scope_denied_ttl : (repo ? scope_repo_ttl : scope_org_ttl)
            cache_set(key, status, ttl: ttl) if cache_connected?
            local_cache_set(key, status, ttl: ttl) if local_cache_connected?
          end

          def rate_limited?(fingerprint:)
            entry = scope_cache_get("github:rate_limit:#{fingerprint}")
            return false unless entry

            entry[:reset_at] > Time.now
          end

          def mark_rate_limited(fingerprint:, reset_at:)
            ttl = [(reset_at - Time.now).ceil, 1].max
            value = { reset_at: reset_at, remaining: 0 }
            cache_set("github:rate_limit:#{fingerprint}", value, ttl: ttl) if cache_connected?
            local_cache_set("github:rate_limit:#{fingerprint}", value, ttl: ttl) if local_cache_connected?
          end

          def invalidate_scope(fingerprint:, owner:, repo: nil)
            key = repo ? "github:scope:#{fingerprint}:#{owner}/#{repo}" : "github:scope:#{fingerprint}:#{owner}"
            cache_delete(key) if cache_connected?
            local_cache_delete(key) if local_cache_connected?
          end

          private

          def scope_cache_get(key)
            if cache_connected?
              result = cache_get(key)
              return result if result
            end
            local_cache_get(key) if local_cache_connected?
          end

          def scope_org_ttl
            return 3600 unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :scope_registry, :org_ttl) || 3600
          rescue StandardError
            3600
          end

          def scope_repo_ttl
            return 300 unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :scope_registry, :repo_ttl) || 300
          rescue StandardError
            300
          end

          def scope_denied_ttl
            return 300 unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :scope_registry, :denied_ttl) || 300
          rescue StandardError
            300
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/scope_registry_spec.rb`
Expected: All 9 examples pass

**Step 5: Full suite + commit**

```bash
bundle exec rspec
bundle exec rubocop -A
bundle exec rubocop
git add lib/legion/extensions/github/helpers/scope_registry.rb \
        spec/legion/extensions/github/helpers/scope_registry_spec.rb
git commit -m "add Helpers::ScopeRegistry for credential-to-scope authorization cache"
```

---

### Task 8b: Helpers::Client — scope-aware credential resolution chain

**Files:**
- Modify: `lib/legion/extensions/github/helpers/client.rb`
- Create: `spec/legion/extensions/github/helpers/client_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/helpers/client_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Helpers::Client do
  let(:helper) { Object.new.extend(described_class) }

  before do
    allow(helper).to receive(:cache_connected?).and_return(false)
    allow(helper).to receive(:local_cache_connected?).and_return(false)
  end

  describe '#connection' do
    it 'returns a Faraday connection with explicit token' do
      conn = helper.connection(token: 'ghp_explicit')
      expect(conn).to be_a(Faraday::Connection)
      expect(conn.headers['Authorization']).to eq('Bearer ghp_explicit')
    end

    it 'returns a connection without auth when no token is provided and no sources available' do
      allow(helper).to receive(:resolve_credential).and_return(nil)
      conn = helper.connection
      expect(conn.headers['Authorization']).to be_nil
    end

    it 'accepts owner: and repo: for scope-aware resolution' do
      allow(helper).to receive(:resolve_credential)
        .with(owner: 'LegionIO', repo: 'lex-github')
        .and_return({ token: 'ghp_scoped', auth_type: :oauth_user })
      conn = helper.connection(owner: 'LegionIO', repo: 'lex-github')
      expect(conn.headers['Authorization']).to eq('Bearer ghp_scoped')
    end
  end

  describe '#resolve_credential' do
    before do
      allow(helper).to receive(:resolve_vault_delegated).and_return(nil)
      allow(helper).to receive(:resolve_settings_delegated).and_return(nil)
      allow(helper).to receive(:resolve_vault_app).and_return(nil)
      allow(helper).to receive(:resolve_settings_app).and_return(nil)
      allow(helper).to receive(:resolve_vault_pat).and_return(nil)
      allow(helper).to receive(:resolve_settings_pat).and_return(nil)
      allow(helper).to receive(:resolve_gh_cli).and_return(nil)
      allow(helper).to receive(:resolve_env).and_return(nil)
      allow(helper).to receive(:credential_fallback?).and_return(true)
    end

    it 'returns nil when no credentials are available' do
      expect(helper.resolve_credential).to be_nil
    end

    it 'prefers delegated over app' do
      delegated = { token: 'delegated', auth_type: :oauth_user,
                    metadata: { source: :vault, credential_fingerprint: 'fp_d' } }
      app = { token: 'app', auth_type: :app_installation,
              metadata: { source: :vault, credential_fingerprint: 'fp_a' } }
      allow(helper).to receive(:resolve_vault_delegated).and_return(delegated)
      allow(helper).to receive(:resolve_vault_app).and_return(app)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status).and_return(:unknown)
      result = helper.resolve_credential
      expect(result[:auth_type]).to eq(:oauth_user)
    end

    it 'falls back to env when nothing else is available' do
      env = { token: 'env-token', auth_type: :env,
              metadata: { source: :env, credential_fingerprint: 'fp_e' } }
      allow(helper).to receive(:resolve_env).and_return(env)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status).and_return(:unknown)
      result = helper.resolve_credential
      expect(result[:auth_type]).to eq(:env)
    end

    it 'skips rate-limited credentials' do
      delegated = { token: 'delegated', auth_type: :oauth_user,
                    metadata: { source: :vault, credential_fingerprint: 'fp_d' } }
      app = { token: 'app', auth_type: :app_installation,
              metadata: { source: :vault, credential_fingerprint: 'fp_a' } }
      allow(helper).to receive(:resolve_vault_delegated).and_return(delegated)
      allow(helper).to receive(:resolve_vault_app).and_return(app)
      allow(helper).to receive(:rate_limited?).with(fingerprint: 'fp_d').and_return(true)
      allow(helper).to receive(:rate_limited?).with(fingerprint: 'fp_a').and_return(false)
      allow(helper).to receive(:scope_status).and_return(:unknown)
      result = helper.resolve_credential
      expect(result[:auth_type]).to eq(:app_installation)
    end

    it 'skips scope-denied credentials for a given owner' do
      delegated = { token: 'delegated', auth_type: :oauth_user,
                    metadata: { source: :vault, credential_fingerprint: 'fp_d' } }
      app = { token: 'app', auth_type: :app_installation,
              metadata: { source: :vault, credential_fingerprint: 'fp_a' } }
      allow(helper).to receive(:resolve_vault_delegated).and_return(delegated)
      allow(helper).to receive(:resolve_vault_app).and_return(app)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status)
        .with(fingerprint: 'fp_d', owner: 'OrgZ', repo: 'repo1').and_return(:denied)
      allow(helper).to receive(:scope_status)
        .with(fingerprint: 'fp_a', owner: 'OrgZ', repo: 'repo1').and_return(:authorized)
      result = helper.resolve_credential(owner: 'OrgZ', repo: 'repo1')
      expect(result[:auth_type]).to eq(:app_installation)
    end

    it 'skips scope check when owner is nil' do
      delegated = { token: 'delegated', auth_type: :oauth_user,
                    metadata: { source: :vault, credential_fingerprint: 'fp_d' } }
      allow(helper).to receive(:resolve_vault_delegated).and_return(delegated)
      allow(helper).to receive(:rate_limited?).and_return(false)
      result = helper.resolve_credential(owner: nil, repo: nil)
      expect(result[:auth_type]).to eq(:oauth_user)
      expect(helper).not_to have_received(:scope_status) if helper.respond_to?(:scope_status)
    end
  end

  describe '#resolve_gh_cli' do
    it 'returns token from gh auth token command' do
      allow(helper).to receive(:`).with('gh auth token 2>/dev/null').and_return("ghp_cli123\n")
      allow($CHILD_STATUS).to receive(:success?).and_return(true)
      result = helper.resolve_gh_cli
      expect(result[:token]).to eq('ghp_cli123')
      expect(result[:auth_type]).to eq(:cli)
    end

    it 'returns nil when gh is not installed' do
      allow(helper).to receive(:`).with('gh auth token 2>/dev/null').and_return('')
      allow($CHILD_STATUS).to receive(:success?).and_return(false)
      expect(helper.resolve_gh_cli).to be_nil
    end
  end

  describe '#resolve_env' do
    it 'returns GITHUB_TOKEN from environment' do
      allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('ghp_env456')
      result = helper.resolve_env
      expect(result[:token]).to eq('ghp_env456')
      expect(result[:auth_type]).to eq(:env)
    end

    it 'returns nil when GITHUB_TOKEN is not set' do
      allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
      expect(helper.resolve_env).to be_nil
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/client_spec.rb`
Expected: FAIL — existing `connection` method has no scope-aware `resolve_credential`

**Step 3: Update the implementation**

Replace `lib/legion/extensions/github/helpers/client.rb` entirely:

```ruby
# frozen_string_literal: true

require 'faraday'
require 'legion/extensions/github/helpers/token_cache'
require 'legion/extensions/github/helpers/scope_registry'

module Legion
  module Extensions
    module Github
      module Helpers
        module Client
          include TokenCache
          include ScopeRegistry

          CREDENTIAL_RESOLVERS = %i[
            resolve_vault_delegated resolve_settings_delegated
            resolve_vault_app resolve_settings_app
            resolve_vault_pat resolve_settings_pat
            resolve_gh_cli resolve_env
          ].freeze

          def connection(owner: nil, repo: nil, api_url: 'https://api.github.com', token: nil, **_opts)
            resolved_token = token || resolve_credential(owner: owner, repo: repo)&.dig(:token)
            Faraday.new(url: api_url) do |conn|
              conn.request :json
              conn.response :json, content_type: /\bjson$/
              conn.headers['Accept'] = 'application/vnd.github+json'
              conn.headers['Authorization'] = "Bearer #{resolved_token}" if resolved_token
              conn.headers['X-GitHub-Api-Version'] = '2022-11-28'
            end
          end

          def resolve_credential(owner: nil, repo: nil)
            CREDENTIAL_RESOLVERS.each do |method|
              next unless respond_to?(method, true)

              result = send(method)
              next unless result

              fingerprint = result.dig(:metadata, :credential_fingerprint)

              next if fingerprint && rate_limited?(fingerprint: fingerprint)

              if owner && fingerprint
                scope = scope_status(fingerprint: fingerprint, owner: owner, repo: repo)
                next if scope == :denied
              end

              return result
            end
            nil
          end

          def resolve_vault_delegated
            return nil unless defined?(Legion::Crypt)

            token_data = vault_get('github/oauth/delegated/token')
            return nil unless token_data&.dig('access_token')

            fp = credential_fingerprint(auth_type: :oauth_user, identifier: 'vault_delegated')
            { token: token_data['access_token'], auth_type: :oauth_user,
              expires_at: token_data['expires_at'],
              metadata: { source: :vault, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_settings_delegated
            return nil unless defined?(Legion::Settings)

            token = Legion::Settings.dig(:github, :oauth, :access_token)
            return nil unless token

            fp = credential_fingerprint(auth_type: :oauth_user, identifier: 'settings_delegated')
            { token: token, auth_type: :oauth_user,
              metadata: { source: :settings, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_vault_app
            return nil unless defined?(Legion::Crypt)

            key_data = vault_get('github/app/private_key')
            return nil unless key_data

            app_id = vault_get('github/app/app_id')
            installation_id = vault_get('github/app/installation_id')
            return nil unless app_id && installation_id

            fp = credential_fingerprint(auth_type: :app_installation, identifier: "vault_app_#{app_id}")
            cached = fetch_token(auth_type: :app_installation)
            return cached.merge(metadata: { source: :vault, credential_fingerprint: fp }) if cached

            nil
          rescue StandardError
            nil
          end

          def resolve_settings_app
            return nil unless defined?(Legion::Settings)

            app_id = Legion::Settings.dig(:github, :app, :app_id)
            return nil unless app_id

            fp = credential_fingerprint(auth_type: :app_installation, identifier: "settings_app_#{app_id}")
            cached = fetch_token(auth_type: :app_installation)
            return cached.merge(metadata: { source: :settings, credential_fingerprint: fp }) if cached

            nil
          rescue StandardError
            nil
          end

          def resolve_vault_pat
            return nil unless defined?(Legion::Crypt)

            token = vault_get('github/token')
            return nil unless token

            fp = credential_fingerprint(auth_type: :pat, identifier: 'vault_pat')
            { token: token, auth_type: :pat, metadata: { source: :vault, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_settings_pat
            return nil unless defined?(Legion::Settings)

            token = Legion::Settings.dig(:github, :token)
            return nil unless token

            fp = credential_fingerprint(auth_type: :pat, identifier: 'settings_pat')
            { token: token, auth_type: :pat, metadata: { source: :settings, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_gh_cli
            if cache_connected? || local_cache_connected?
              cached = cache_connected? ? cache_get('github:cli_token') : local_cache_get('github:cli_token')
              return cached if cached
            end

            output = `gh auth token 2>/dev/null`.strip
            return nil unless $CHILD_STATUS&.success? && !output.empty?

            fp = credential_fingerprint(auth_type: :cli, identifier: 'gh_cli')
            result = { token: output, auth_type: :cli, metadata: { source: :gh_cli, credential_fingerprint: fp } }
            cache_set('github:cli_token', result, ttl: 300) if cache_connected?
            local_cache_set('github:cli_token', result, ttl: 300) if local_cache_connected?
            result
          rescue StandardError
            nil
          end

          def resolve_env
            token = ENV['GITHUB_TOKEN']
            return nil if token.nil? || token.empty?

            fp = credential_fingerprint(auth_type: :env, identifier: 'env')
            { token: token, auth_type: :env, metadata: { source: :env, credential_fingerprint: fp } }
          end

          private

          def credential_fallback?
            return true unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :credential_fallback) != false
          rescue StandardError
            true
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/client_spec.rb`
Expected: All 10 examples pass

**Step 5: Run full suite to check existing tests still pass**

Run: `bundle exec rspec`
Expected: All pass — existing tests pass explicit `token:` to `connection()`, bypassing the resolver

**Step 6: Rubocop + commit**

```bash
bundle exec rubocop -A
bundle exec rubocop
git add lib/legion/extensions/github/helpers/client.rb \
        lib/legion/extensions/github/helpers/scope_registry.rb \
        spec/legion/extensions/github/helpers/client_spec.rb \
        spec/legion/extensions/github/helpers/scope_registry_spec.rb
git commit -m "add scope-aware credential resolution with ScopeRegistry and rate limit checks"
```

---

### Task 9: Update Client class to include App and OAuth runners

**Files:**
- Modify: `lib/legion/extensions/github/client.rb`
- Modify: `spec/legion/extensions/github/client_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/legion/extensions/github/client_spec.rb`:

```ruby
describe 'App runner inclusion' do
  it 'responds to generate_jwt' do
    expect(client).to respond_to(:generate_jwt)
  end

  it 'responds to create_installation_token' do
    expect(client).to respond_to(:create_installation_token)
  end

  it 'responds to verify_signature' do
    expect(client).to respond_to(:verify_signature)
  end

  it 'responds to generate_manifest' do
    expect(client).to respond_to(:generate_manifest)
  end
end

describe 'OAuth runner inclusion' do
  it 'responds to authorize_url' do
    expect(client).to respond_to(:authorize_url)
  end

  it 'responds to exchange_code' do
    expect(client).to respond_to(:exchange_code)
  end

  it 'responds to generate_pkce' do
    expect(client).to respond_to(:generate_pkce)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/client_spec.rb`
Expected: FAIL — `respond_to` checks fail

**Step 3: Update the Client class**

In `lib/legion/extensions/github/client.rb`, add the requires and includes:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'
require 'legion/extensions/github/runners/repositories'
require 'legion/extensions/github/runners/issues'
require 'legion/extensions/github/runners/pull_requests'
require 'legion/extensions/github/runners/users'
require 'legion/extensions/github/runners/organizations'
require 'legion/extensions/github/runners/gists'
require 'legion/extensions/github/runners/search'
require 'legion/extensions/github/runners/commits'
require 'legion/extensions/github/runners/labels'
require 'legion/extensions/github/runners/comments'
require 'legion/extensions/github/runners/branches'
require 'legion/extensions/github/runners/contents'
require 'legion/extensions/github/app/runners/auth'
require 'legion/extensions/github/app/runners/webhooks'
require 'legion/extensions/github/app/runners/manifest'
require 'legion/extensions/github/oauth/runners/auth'

module Legion
  module Extensions
    module Github
      class Client
        include Helpers::Client
        include Helpers::Cache
        include Runners::Repositories
        include Runners::Issues
        include Runners::PullRequests
        include Runners::Users
        include Runners::Organizations
        include Runners::Gists
        include Runners::Search
        include Runners::Commits
        include Runners::Labels
        include Runners::Comments
        include Runners::Branches
        include Runners::Contents
        include App::Runners::Auth
        include App::Runners::Webhooks
        include App::Runners::Manifest
        include OAuth::Runners::Auth

        attr_reader :opts

        def initialize(token: nil, api_url: 'https://api.github.com', **extra)
          @opts = { token: token, api_url: api_url, **extra }
        end

        def connection(**override)
          super(**@opts.merge(override))
        end
      end
    end
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/client_spec.rb`
Expected: All pass (existing + new)

**Step 5: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/client.rb \
        spec/legion/extensions/github/client_spec.rb
git commit -m "update Client to include App and OAuth runners"
```

---

### Task 10: Update extension entry point and version

**Files:**
- Modify: `lib/legion/extensions/github.rb`
- Modify: `lib/legion/extensions/github/version.rb`

**Step 1: Consolidate all requires in github.rb**

Ensure `lib/legion/extensions/github.rb` requires all new modules in proper order:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/version'
require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'
require 'legion/extensions/github/helpers/token_cache'
require 'legion/extensions/github/runners/repositories'
require 'legion/extensions/github/runners/issues'
require 'legion/extensions/github/runners/pull_requests'
require 'legion/extensions/github/runners/users'
require 'legion/extensions/github/runners/organizations'
require 'legion/extensions/github/runners/gists'
require 'legion/extensions/github/runners/search'
require 'legion/extensions/github/runners/commits'
require 'legion/extensions/github/runners/labels'
require 'legion/extensions/github/runners/comments'
require 'legion/extensions/github/runners/branches'
require 'legion/extensions/github/runners/contents'
require 'legion/extensions/github/app/runners/auth'
require 'legion/extensions/github/app/runners/webhooks'
require 'legion/extensions/github/app/runners/manifest'
require 'legion/extensions/github/oauth/runners/auth'
require 'legion/extensions/github/client'

module Legion
  module Extensions
    module Github
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core, false
    end
  end
end
```

**Step 2: Bump version**

In `lib/legion/extensions/github/version.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      VERSION = '0.3.0'
    end
  end
end
```

**Step 3: Run full suite**

Run: `bundle exec rspec`
Expected: All pass

**Step 4: Rubocop**

Run: `bundle exec rubocop -A && bundle exec rubocop`
Expected: Zero offenses

**Step 5: Commit**

```bash
git add lib/legion/extensions/github.rb \
        lib/legion/extensions/github/version.rb
git commit -m "consolidate requires, bump version to 0.3.0"
```

---

### Task 11: Update CHANGELOG.md and README.md

**Files:**
- Create or modify: `CHANGELOG.md`
- Modify: `README.md` (if it documents auth usage)

**Step 1: Create/update CHANGELOG.md**

```markdown
# Changelog

## [0.3.0] - 2026-03-30

### Added
- GitHub App authentication (JWT generation, installation tokens)
- OAuth delegated user authentication (Authorization Code + PKCE, device code flow)
- GitHub App manifest flow for streamlined app registration
- Webhook signature verification and event parsing
- 8-source credential resolution chain (Vault delegated -> Settings delegated -> Vault App -> Settings App -> Vault PAT -> Settings PAT -> GH CLI -> ENV)
- Rate limit fallback across credential sources (configurable)
- Two-tier API response caching (global Redis + local in-memory) with configurable per-resource TTLs
- Token lifecycle management with automatic rate limit tracking
- `jwt` and `base64` runtime dependencies
```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "add CHANGELOG.md for v0.3.0"
```

---

### Task 12: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update CLAUDE.md** to reflect the new architecture (App/OAuth sub-modules, new runners, helpers, version bump to 0.3.0, new dependencies, spec count increase).

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "update CLAUDE.md for v0.3.0 github app and oauth support"
```

---

### Task 13: App transport classes

**Dependency:** legion-transport >= 1.4.5 (resolved)

**Files:**
- Create: `lib/legion/extensions/github/app/transport/exchanges/app.rb`
- Create: `lib/legion/extensions/github/app/transport/queues/auth.rb`
- Create: `lib/legion/extensions/github/app/transport/queues/webhooks.rb`
- Create: `lib/legion/extensions/github/app/transport/messages/event.rb`

These transport classes auto-derive correct names from the `Github::App` namespace via boundary-walking:
- Exchange: `lex.github.app`
- Queues: `lex.github.app.runners.auth`, `lex.github.app.runners.webhooks`
- DLX: `lex.github.app.dlx`

Implementation follows the standard transport patterns from existing LEX extensions.

---

### Task 14: App hooks and actors

**Dependency:** Task 13

**Files:**
- Create: `lib/legion/extensions/github/app/hooks/webhook.rb`
- Create: `lib/legion/extensions/github/app/hooks/setup.rb`
- Create: `lib/legion/extensions/github/app/actor/token_refresh.rb`
- Create: `lib/legion/extensions/github/app/actor/webhook_poller.rb`

**App::Hooks::Webhook** — `< Legion::Extensions::Hooks::Base`, mount `/webhook`, `def runner_class` returns `Legion::Extensions::Github::App::Runners::Webhooks`.

**App::Hooks::Setup** — `< Legion::Extensions::Hooks::Base`, mount `/setup/callback`, `def runner_class` returns `Legion::Extensions::Github::App::Runners::Manifest`.

**App::Actor::TokenRefresh** — `< Legion::Extensions::Actors::Every`, `time 45.minutes`, generates JWT and refreshes installation token.

**App::Actor::WebhookPoller** — `< Legion::Extensions::Actors::Poll`, `time 60`, polls `/repos/:owner/:repo/events`, deduplicates via HighWaterMark, publishes to `lex.github.app` exchange.

---

### Task 15: OAuth transport, hooks, and actor

**Dependency:** legion-transport >= 1.4.5 (resolved)

**Files:**
- Create: `lib/legion/extensions/github/oauth/transport/exchanges/oauth.rb`
- Create: `lib/legion/extensions/github/oauth/transport/queues/auth.rb`
- Create: `lib/legion/extensions/github/oauth/hooks/callback.rb`
- Create: `lib/legion/extensions/github/oauth/actor/token_refresh.rb`

**OAuth::Hooks::Callback** — `< Legion::Extensions::Hooks::Base`, mount `/callback`.

**OAuth::Actor::TokenRefresh** — `< Legion::Extensions::Actors::Every`, `time 3.hours`, refreshes before GitHub's 8hr expiry.

---

## Additional Tasks

These tasks can run immediately after Tasks 1-12. They do not depend on AMQP transport.

---

### Task 16: App::Runners::Installations — full installation management

**Files:**
- Create: `lib/legion/extensions/github/app/runners/installations.rb`
- Create: `spec/legion/extensions/github/app/runners/installations_spec.rb`
- Modify: `lib/legion/extensions/github/client.rb` (add include)
- Modify: `lib/legion/extensions/github.rb` (add require)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/app/runners/installations_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Installations do
  let(:runner) { Object.new.extend(described_class) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(runner).to receive(:connection).and_return(test_connection) }

  describe '#list_installations' do
    it 'lists all installations for the app' do
      stubs.get('/app/installations') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 1, 'account' => { 'login' => 'LegionIO' } },
          { 'id' => 2, 'account' => { 'login' => 'other-org' } }]]
      end
      result = runner.list_installations(jwt: 'fake-jwt')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].length).to eq(2)
    end
  end

  describe '#get_installation' do
    it 'returns a single installation' do
      stubs.get('/app/installations/12345') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 12345, 'account' => { 'login' => 'LegionIO' },
           'permissions' => { 'contents' => 'write' } }]
      end
      result = runner.get_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]['id']).to eq(12345)
    end
  end

  describe '#list_installation_repos' do
    it 'lists repos accessible to an installation' do
      stubs.get('/installation/repositories') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'repositories' => [{ 'full_name' => 'LegionIO/lex-github' }] }]
      end
      result = runner.list_installation_repos(token: 'ghs_test')
      expect(result[:result]['repositories'].first['full_name']).to eq('LegionIO/lex-github')
    end
  end

  describe '#suspend_installation' do
    it 'suspends an installation' do
      stubs.put('/app/installations/12345/suspended') { [204, {}, ''] }
      result = runner.suspend_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]).to be true
    end
  end

  describe '#unsuspend_installation' do
    it 'unsuspends an installation' do
      stubs.delete('/app/installations/12345/suspended') { [204, {}, ''] }
      result = runner.unsuspend_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]).to be true
    end
  end

  describe '#delete_installation' do
    it 'deletes an installation' do
      stubs.delete('/app/installations/12345') { [204, {}, ''] }
      result = runner.delete_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]).to be true
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/installations_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/app/runners/installations.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Installations
            include Legion::Extensions::Github::Helpers::Client

            def list_installations(jwt:, per_page: 30, page: 1, **)
              conn = connection(token: jwt, **)
              response = conn.get('/app/installations', per_page: per_page, page: page)
              { result: response.body }
            end

            def get_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.get("/app/installations/#{installation_id}")
              { result: response.body }
            end

            def list_installation_repos(per_page: 30, page: 1, **)
              response = connection(**).get('/installation/repositories',
                                           per_page: per_page, page: page)
              { result: response.body }
            end

            def suspend_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.put("/app/installations/#{installation_id}/suspended")
              { result: response.status == 204 }
            end

            def unsuspend_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.delete("/app/installations/#{installation_id}/suspended")
              { result: response.status == 204 }
            end

            def delete_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.delete("/app/installations/#{installation_id}")
              { result: response.status == 204 }
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
```

**Step 4: Add require and include to entry point and Client**

In `lib/legion/extensions/github.rb`, add:
```ruby
require 'legion/extensions/github/app/runners/installations'
```

In `lib/legion/extensions/github/client.rb`, add:
```ruby
include App::Runners::Installations
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/installations_spec.rb`
Expected: All 6 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/app/runners/installations.rb \
        spec/legion/extensions/github/app/runners/installations_spec.rb \
        lib/legion/extensions/github.rb \
        lib/legion/extensions/github/client.rb
git commit -m "add App::Runners::Installations for full installation management"
```

---

### Task 17: Rate limit and scope-aware Faraday middleware

**Files:**
- Create: `lib/legion/extensions/github/middleware/rate_limit.rb`
- Create: `lib/legion/extensions/github/middleware/scope_probe.rb`
- Create: `spec/legion/extensions/github/middleware/rate_limit_spec.rb`
- Create: `spec/legion/extensions/github/middleware/scope_probe_spec.rb`
- Modify: `lib/legion/extensions/github/helpers/client.rb` (plug middleware into connection, add retry-on-fallback)

**Step 1: Write the failing tests for RateLimit middleware**

Create `spec/legion/extensions/github/middleware/rate_limit_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Middleware::RateLimit do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:handler) { double('handler') }
  let(:conn) do
    Faraday.new do |f|
      f.use described_class, handler: handler
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end
  end

  describe 'normal response' do
    it 'passes through without modification' do
      stubs.get('/repos/test/repo') do
        [200, { 'Content-Type' => 'application/json',
                'X-RateLimit-Remaining' => '4999',
                'X-RateLimit-Reset' => (Time.now.to_i + 3600).to_s }, { 'name' => 'repo' }]
      end
      response = conn.get('/repos/test/repo')
      expect(response.status).to eq(200)
    end
  end

  describe '429 response' do
    it 'calls on_rate_limit on the handler with fingerprint' do
      reset_time = Time.now.to_i + 300
      stubs.get('/repos/test/repo') do
        [429, { 'Content-Type' => 'application/json',
                'X-RateLimit-Remaining' => '0',
                'X-RateLimit-Reset' => reset_time.to_s },
         { 'message' => 'API rate limit exceeded' }]
      end
      expect(handler).to receive(:on_rate_limit).with(
        hash_including(remaining: 0, reset_at: anything, status: 429)
      )
      conn.get('/repos/test/repo')
    end
  end

  describe 'X-RateLimit-Remaining: 0 on 200' do
    it 'calls on_rate_limit when remaining hits zero' do
      reset_time = Time.now.to_i + 300
      stubs.get('/repos/test/repo') do
        [200, { 'Content-Type' => 'application/json',
                'X-RateLimit-Remaining' => '0',
                'X-RateLimit-Reset' => reset_time.to_s }, { 'name' => 'repo' }]
      end
      expect(handler).to receive(:on_rate_limit).with(hash_including(remaining: 0))
      conn.get('/repos/test/repo')
    end
  end

  describe 'no rate limit headers' do
    it 'does not call handler' do
      stubs.get('/repos/test/repo') do
        [200, { 'Content-Type' => 'application/json' }, { 'name' => 'repo' }]
      end
      expect(handler).not_to receive(:on_rate_limit)
      conn.get('/repos/test/repo')
    end
  end
end
```

**Step 2: Write the failing tests for ScopeProbe middleware**

Create `spec/legion/extensions/github/middleware/scope_probe_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Middleware::ScopeProbe do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:handler) { double('handler') }
  let(:conn) do
    Faraday.new do |f|
      f.use described_class, handler: handler
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end
  end

  describe '403 response' do
    it 'calls on_scope_denied on the handler' do
      stubs.get('/repos/OrgZ/repo1') do
        [403, { 'Content-Type' => 'application/json' },
         { 'message' => 'Resource not accessible by integration' }]
      end
      expect(handler).to receive(:on_scope_denied).with(
        hash_including(status: 403, url: anything)
      )
      conn.get('/repos/OrgZ/repo1')
    end
  end

  describe '2xx response' do
    it 'calls on_scope_authorized on the handler' do
      stubs.get('/repos/OrgZ/repo1') do
        [200, { 'Content-Type' => 'application/json' }, { 'name' => 'repo1' }]
      end
      expect(handler).to receive(:on_scope_authorized).with(
        hash_including(status: 200, url: anything)
      )
      conn.get('/repos/OrgZ/repo1')
    end
  end

  describe '404 response' do
    it 'calls on_scope_denied (repo not visible = not authorized)' do
      stubs.get('/repos/OrgZ/private-repo') do
        [404, { 'Content-Type' => 'application/json' },
         { 'message' => 'Not Found' }]
      end
      expect(handler).to receive(:on_scope_denied).with(
        hash_including(status: 404)
      )
      conn.get('/repos/OrgZ/private-repo')
    end
  end

  describe 'non-repo path' do
    it 'does not call scope handlers for global endpoints' do
      stubs.get('/user') do
        [200, { 'Content-Type' => 'application/json' }, { 'login' => 'test' }]
      end
      expect(handler).not_to receive(:on_scope_denied)
      expect(handler).not_to receive(:on_scope_authorized)
      conn.get('/user')
    end
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/middleware/`
Expected: FAIL — files do not exist

**Step 4: Write the RateLimit middleware**

Create `lib/legion/extensions/github/middleware/rate_limit.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module Middleware
        class RateLimit < Faraday::Middleware
          def initialize(app, handler: nil)
            super(app)
            @handler = handler
          end

          def on_complete(env)
            remaining = env.response_headers['x-ratelimit-remaining']
            reset = env.response_headers['x-ratelimit-reset']
            return unless remaining

            remaining_int = remaining.to_i
            return unless remaining_int.zero? || env.status == 429
            return unless @handler&.respond_to?(:on_rate_limit)

            reset_at = reset ? Time.at(reset.to_i) : Time.now + 60
            @handler.on_rate_limit(
              remaining: remaining_int,
              reset_at: reset_at,
              status: env.status,
              url: env.url.to_s
            )
          end
        end
      end
    end
  end
end

Faraday::Response.register_middleware(
  github_rate_limit: Legion::Extensions::Github::Middleware::RateLimit
)
```

**Step 5: Write the ScopeProbe middleware**

Create `lib/legion/extensions/github/middleware/scope_probe.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module Middleware
        class ScopeProbe < Faraday::Middleware
          REPO_PATH_PATTERN = %r{^/repos/([^/]+)/([^/]+)}.freeze

          def initialize(app, handler: nil)
            super(app)
            @handler = handler
          end

          def on_complete(env)
            return unless @handler
            return unless env.url.path.match?(REPO_PATH_PATTERN)

            info = { status: env.status, url: env.url.to_s, path: env.url.path }

            if env.status == 403 || env.status == 404
              @handler.on_scope_denied(info) if @handler.respond_to?(:on_scope_denied)
            elsif env.status >= 200 && env.status < 300
              @handler.on_scope_authorized(info) if @handler.respond_to?(:on_scope_authorized)
            end
          end
        end
      end
    end
  end
end

Faraday::Response.register_middleware(
  github_scope_probe: Legion::Extensions::Github::Middleware::ScopeProbe
)
```

**Step 6: Wire middleware into Helpers::Client#connection**

In `lib/legion/extensions/github/helpers/client.rb`, update the `connection` method to include both middleware and add the callback methods:

```ruby
def connection(owner: nil, repo: nil, api_url: 'https://api.github.com', token: nil, **_opts)
  resolved = token ? { token: token } : resolve_credential(owner: owner, repo: repo)
  resolved_token = resolved&.dig(:token)
  @current_credential = resolved

  Faraday.new(url: api_url) do |conn|
    conn.request :json
    conn.response :json, content_type: /\bjson$/
    conn.response :github_rate_limit, handler: self
    conn.response :github_scope_probe, handler: self
    conn.headers['Accept'] = 'application/vnd.github+json'
    conn.headers['Authorization'] = "Bearer #{resolved_token}" if resolved_token
    conn.headers['X-GitHub-Api-Version'] = '2022-11-28'
  end
end

def on_rate_limit(remaining:, reset_at:, status:, url:, **)
  fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
  return unless fingerprint

  mark_rate_limited(fingerprint: fingerprint, reset_at: reset_at)
end

def on_scope_denied(status:, url:, path:, **)
  fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
  owner, repo = extract_owner_repo(path)
  return unless fingerprint && owner

  register_scope(fingerprint: fingerprint, owner: owner, repo: repo, status: :denied)
end

def on_scope_authorized(status:, url:, path:, **)
  fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
  owner, repo = extract_owner_repo(path)
  return unless fingerprint && owner

  register_scope(fingerprint: fingerprint, owner: owner, repo: repo, status: :authorized)
end

private

def extract_owner_repo(path)
  match = path.match(%r{^/repos/([^/]+)/([^/]+)})
  return [nil, nil] unless match

  [match[1], match[2]]
end
```

**Step 7: Require in entry point**

In `lib/legion/extensions/github.rb`, add before helpers:

```ruby
require 'legion/extensions/github/middleware/rate_limit'
require 'legion/extensions/github/middleware/scope_probe'
```

**Step 8: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/middleware/`
Expected: All 8 examples pass

**Step 9: Full suite + commit**

```bash
bundle exec rspec
bundle exec rubocop -A
bundle exec rubocop
git add lib/legion/extensions/github/middleware/rate_limit.rb \
        lib/legion/extensions/github/middleware/scope_probe.rb \
        spec/legion/extensions/github/middleware/rate_limit_spec.rb \
        spec/legion/extensions/github/middleware/scope_probe_spec.rb \
        lib/legion/extensions/github/helpers/client.rb \
        lib/legion/extensions/github.rb
git commit -m "add rate limit and scope probe Faraday middleware with credential fallback"
```

---

### Task 18: Wire app token generation on credential cache miss

**Files:**
- Modify: `lib/legion/extensions/github/helpers/client.rb`
- Modify: `spec/legion/extensions/github/helpers/client_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/legion/extensions/github/helpers/client_spec.rb`:

```ruby
describe '#resolve_vault_app' do
  before do
    allow(helper).to receive(:vault_get).with('github/app/private_key').and_return('-----BEGIN RSA PRIVATE KEY-----...')
    allow(helper).to receive(:vault_get).with('github/app/app_id').and_return('12345')
    allow(helper).to receive(:vault_get).with('github/app/installation_id').and_return('67890')
    allow(helper).to receive(:fetch_token).and_return(nil)
    allow(helper).to receive(:store_token)
  end

  it 'generates a fresh installation token on cache miss' do
    jwt_result = { result: 'fake-jwt' }
    token_result = { result: { 'token' => 'ghs_fresh', 'expires_at' => '2026-03-30T13:00:00Z' } }
    allow(helper).to receive(:generate_jwt).and_return(jwt_result)
    allow(helper).to receive(:create_installation_token).and_return(token_result)

    result = helper.resolve_vault_app
    expect(result[:token]).to eq('ghs_fresh')
    expect(result[:auth_type]).to eq(:app_installation)
  end
end

describe '#resolve_settings_app' do
  before do
    stub_const('Legion::Settings', double)
    allow(Legion::Settings).to receive(:dig).with(:github, :app, :app_id).and_return('12345')
    allow(Legion::Settings).to receive(:dig).with(:github, :app, :private_key_path).and_return('/tmp/test.pem')
    allow(Legion::Settings).to receive(:dig).with(:github, :app, :installation_id).and_return('67890')
    allow(helper).to receive(:fetch_token).and_return(nil)
    allow(helper).to receive(:store_token)
    allow(File).to receive(:read).with('/tmp/test.pem').and_return('-----BEGIN RSA PRIVATE KEY-----...')
  end

  it 'generates a fresh installation token from settings on cache miss' do
    jwt_result = { result: 'fake-jwt' }
    token_result = { result: { 'token' => 'ghs_settings', 'expires_at' => '2026-03-30T13:00:00Z' } }
    allow(helper).to receive(:generate_jwt).and_return(jwt_result)
    allow(helper).to receive(:create_installation_token).and_return(token_result)

    result = helper.resolve_settings_app
    expect(result[:token]).to eq('ghs_settings')
    expect(result[:auth_type]).to eq(:app_installation)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/client_spec.rb`
Expected: New tests FAIL — `resolve_vault_app` returns nil on cache miss

**Step 3: Update resolve_vault_app and resolve_settings_app**

In `lib/legion/extensions/github/helpers/client.rb`, replace `resolve_vault_app`:

```ruby
def resolve_vault_app
  return nil unless defined?(Legion::Crypt)

  private_key = vault_get('github/app/private_key') rescue nil
  return nil unless private_key

  app_id = vault_get('github/app/app_id') rescue nil
  installation_id = vault_get('github/app/installation_id') rescue nil
  return nil unless app_id && installation_id

  cached = fetch_token(auth_type: :app_installation)
  return cached if cached

  jwt = generate_jwt(app_id: app_id, private_key: private_key)[:result]
  token_data = create_installation_token(jwt: jwt, installation_id: installation_id)[:result]
  return nil unless token_data&.dig('token')

  expires_at = Time.parse(token_data['expires_at']) rescue (Time.now + 3600)
  fp = credential_fingerprint(auth_type: :app_installation, identifier: "vault_app_#{app_id}")
  result = { token: token_data['token'], auth_type: :app_installation,
             expires_at: expires_at,
             metadata: { source: :vault, installation_id: installation_id, credential_fingerprint: fp } }
  store_token(**result)
  result
rescue StandardError
  nil
end
```

Replace `resolve_settings_app`:

```ruby
def resolve_settings_app
  return nil unless defined?(Legion::Settings)

  app_id = Legion::Settings.dig(:github, :app, :app_id) rescue nil
  return nil unless app_id

  fp = credential_fingerprint(auth_type: :app_installation, identifier: "settings_app_#{app_id}")
  cached = fetch_token(auth_type: :app_installation)
  return cached.merge(metadata: cached.fetch(:metadata, {}).merge(credential_fingerprint: fp)) if cached

  key_path = Legion::Settings.dig(:github, :app, :private_key_path) rescue nil
  installation_id = Legion::Settings.dig(:github, :app, :installation_id) rescue nil
  return nil unless key_path && installation_id

  private_key = File.read(key_path)
  jwt = generate_jwt(app_id: app_id, private_key: private_key)[:result]
  token_data = create_installation_token(jwt: jwt, installation_id: installation_id)[:result]
  return nil unless token_data&.dig('token')

  expires_at = Time.parse(token_data['expires_at']) rescue (Time.now + 3600)
  result = { token: token_data['token'], auth_type: :app_installation,
             expires_at: expires_at,
             metadata: { source: :settings, installation_id: installation_id, credential_fingerprint: fp } }
  store_token(**result)
  result
rescue StandardError
  nil
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/client_spec.rb`
Expected: All pass

**Step 5: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/helpers/client.rb \
        spec/legion/extensions/github/helpers/client_spec.rb
git commit -m "wire app token generation on credential cache miss in resolve_vault_app and resolve_settings_app"
```

---

### Task 19: Vault persistence after manifest flow

**Files:**
- Create: `lib/legion/extensions/github/app/runners/credential_store.rb`
- Create: `spec/legion/extensions/github/app/runners/credential_store_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/app/runners/credential_store_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::CredentialStore do
  let(:runner) { Object.new.extend(described_class) }

  describe '#store_app_credentials' do
    it 'stores all app credentials from manifest exchange' do
      expect(runner).to receive(:vault_set).with('github/app/app_id', '12345')
      expect(runner).to receive(:vault_set).with('github/app/private_key', '-----BEGIN RSA...')
      expect(runner).to receive(:vault_set).with('github/app/client_id', 'Iv1.abc')
      expect(runner).to receive(:vault_set).with('github/app/client_secret', 'secret123')
      expect(runner).to receive(:vault_set).with('github/app/webhook_secret', 'whsec123')

      runner.store_app_credentials(
        app_id: '12345', private_key: '-----BEGIN RSA...',
        client_id: 'Iv1.abc', client_secret: 'secret123',
        webhook_secret: 'whsec123'
      )
    end

    it 'returns success result' do
      allow(runner).to receive(:vault_set)
      result = runner.store_app_credentials(
        app_id: '12345', private_key: 'key',
        client_id: 'id', client_secret: 'secret',
        webhook_secret: 'whsec'
      )
      expect(result[:result]).to eq(true)
    end
  end

  describe '#store_oauth_token' do
    it 'stores delegated token at user-scoped path' do
      expect(runner).to receive(:vault_set).with(
        'github/oauth/matt/token',
        hash_including('access_token' => 'ghu_test', 'refresh_token' => 'ghr_test')
      )
      runner.store_oauth_token(
        user: 'matt', access_token: 'ghu_test',
        refresh_token: 'ghr_test', expires_in: 28800
      )
    end
  end

  describe '#load_oauth_token' do
    it 'loads delegated token from user-scoped path' do
      allow(runner).to receive(:vault_get).with('github/oauth/matt/token')
                                          .and_return({ 'access_token' => 'ghu_test' })
      result = runner.load_oauth_token(user: 'matt')
      expect(result[:result]['access_token']).to eq('ghu_test')
    end

    it 'returns nil when no token exists' do
      allow(runner).to receive(:vault_get).and_return(nil)
      result = runner.load_oauth_token(user: 'matt')
      expect(result[:result]).to be_nil
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/credential_store_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/app/runners/credential_store.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module CredentialStore
            def store_app_credentials(app_id:, private_key:, client_id:, client_secret:, webhook_secret:, **)
              vault_set('github/app/app_id', app_id)
              vault_set('github/app/private_key', private_key)
              vault_set('github/app/client_id', client_id)
              vault_set('github/app/client_secret', client_secret)
              vault_set('github/app/webhook_secret', webhook_secret)
              { result: true }
            end

            def store_oauth_token(user:, access_token:, refresh_token:, expires_in: nil, scope: nil, **)
              data = { 'access_token' => access_token, 'refresh_token' => refresh_token,
                       'expires_in' => expires_in, 'scope' => scope,
                       'stored_at' => Time.now.iso8601 }.compact
              vault_set("github/oauth/#{user}/token", data)
              { result: true }
            end

            def load_oauth_token(user:, **)
              data = vault_get("github/oauth/#{user}/token") rescue nil
              { result: data }
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
```

**Step 4: Add require, include, run tests, commit**

```bash
# Add require to github.rb, include to client.rb
bundle exec rspec
git add lib/legion/extensions/github/app/runners/credential_store.rb \
        spec/legion/extensions/github/app/runners/credential_store_spec.rb \
        lib/legion/extensions/github.rb \
        lib/legion/extensions/github/client.rb
git commit -m "add App::Runners::CredentialStore for Vault persistence of app and oauth tokens"
```

---

### Task 20: Per-installation token cache

**Files:**
- Modify: `lib/legion/extensions/github/helpers/token_cache.rb`
- Modify: `spec/legion/extensions/github/helpers/token_cache_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/legion/extensions/github/helpers/token_cache_spec.rb`:

```ruby
describe '#store_token with installation_id' do
  it 'stores tokens keyed by installation_id' do
    expect(helper).to receive(:local_cache_set).with(
      'github:token:app_installation:67890',
      hash_including(token: 'ghs_inst1'),
      ttl: anything
    )
    helper.store_token(token: 'ghs_inst1', auth_type: :app_installation,
                       expires_at: Time.now + 3600, installation_id: '67890')
  end
end

describe '#fetch_token with installation_id' do
  it 'fetches token by installation_id' do
    cached = { token: 'ghs_inst1', auth_type: :app_installation,
               expires_at: (Time.now + 3600).iso8601 }
    allow(helper).to receive(:local_cache_get)
      .with('github:token:app_installation:67890')
      .and_return(cached)
    result = helper.fetch_token(auth_type: :app_installation, installation_id: '67890')
    expect(result[:token]).to eq('ghs_inst1')
  end

  it 'falls back to generic key when installation_id not found' do
    cached = { token: 'ghs_generic', auth_type: :app_installation,
               expires_at: (Time.now + 3600).iso8601 }
    allow(helper).to receive(:local_cache_get)
      .with('github:token:app_installation:99999')
      .and_return(nil)
    allow(helper).to receive(:local_cache_get)
      .with('github:token:app_installation')
      .and_return(cached)
    result = helper.fetch_token(auth_type: :app_installation, installation_id: '99999')
    expect(result[:token]).to eq('ghs_generic')
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/token_cache_spec.rb`
Expected: New tests FAIL

**Step 3: Update store_token and fetch_token**

In `lib/legion/extensions/github/helpers/token_cache.rb`, update `store_token` to include `installation_id` in the cache key:

```ruby
def store_token(token:, auth_type:, expires_at:, installation_id: nil, metadata: {}, **)
  entry = { token: token, auth_type: auth_type,
            expires_at: expires_at.respond_to?(:iso8601) ? expires_at.iso8601 : expires_at,
            installation_id: installation_id, metadata: metadata }
  ttl = [(expires_at.respond_to?(:to_i) ? expires_at.to_i - Time.now.to_i : 3600), 60].max
  key = token_cache_key(auth_type, installation_id)
  cache_set(key, entry, ttl: ttl) if cache_connected?
  local_cache_set(key, entry, ttl: ttl) if local_cache_connected?
end
```

Update `fetch_token`:

```ruby
def fetch_token(auth_type:, installation_id: nil, **)
  key = token_cache_key(auth_type, installation_id)
  entry = token_cache_read(key)

  # Fall back to generic key if installation-specific miss
  if entry.nil? && installation_id
    entry = token_cache_read(token_cache_key(auth_type, nil))
  end

  return nil unless entry

  expires = Time.parse(entry[:expires_at]) rescue nil
  return nil if expires && expires < Time.now + TOKEN_BUFFER_SECONDS

  entry
end
```

Add private helpers:

```ruby
private

def token_cache_key(auth_type, installation_id)
  base = "github:token:#{auth_type}"
  installation_id ? "#{base}:#{installation_id}" : base
end

def token_cache_read(key)
  if cache_connected?
    cache_get(key)
  elsif local_cache_connected?
    local_cache_get(key)
  end
end
```

**Step 4: Run tests + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/helpers/token_cache.rb \
        spec/legion/extensions/github/helpers/token_cache_spec.rb
git commit -m "add per-installation token cache keying with generic fallback"
```

---

### Task 21: Helpers::CallbackServer — ephemeral OAuth callback listener

**Files:**
- Create: `lib/legion/extensions/github/helpers/callback_server.rb`
- Create: `spec/legion/extensions/github/helpers/callback_server_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/helpers/callback_server_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Helpers::CallbackServer do
  subject(:server) { described_class.new }

  describe '#start and #redirect_uri' do
    it 'binds to a random port on localhost' do
      server.start
      expect(server.port).to be_a(Integer)
      expect(server.port).to be > 0
      expect(server.redirect_uri).to match(%r{http://127\.0\.0\.1:\d+/callback})
    ensure
      server.shutdown
    end
  end

  describe '#wait_for_callback' do
    it 'returns code and state from callback request' do
      server.start
      Thread.new do
        sleep 0.1
        Net::HTTP.get(URI("#{server.redirect_uri}?code=test-code&state=test-state"))
      end
      result = server.wait_for_callback(timeout: 5)
      expect(result[:code]).to eq('test-code')
      expect(result[:state]).to eq('test-state')
    ensure
      server.shutdown
    end

    it 'returns nil on timeout' do
      server.start
      result = server.wait_for_callback(timeout: 0.1)
      expect(result).to be_nil
    ensure
      server.shutdown
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/callback_server_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/helpers/callback_server.rb`:

```ruby
# frozen_string_literal: true

require 'socket'
require 'uri'

module Legion
  module Extensions
    module Github
      module Helpers
        class CallbackServer
          RESPONSE_HTML = <<~HTML
            <html><body style="font-family:sans-serif;text-align:center;padding:40px;">
            <h2>GitHub authentication complete</h2><p>You can close this window.</p></body></html>
          HTML

          attr_reader :port

          def initialize
            @server = nil
            @port = nil
            @result = nil
            @mutex = Mutex.new
            @cv = ConditionVariable.new
          end

          def start
            @server = TCPServer.new('127.0.0.1', 0)
            @port = @server.addr[1]
            @thread = Thread.new { listen } # rubocop:disable ThreadSafety/NewThread
          end

          def wait_for_callback(timeout: 120)
            @mutex.synchronize do
              @cv.wait(@mutex, timeout) unless @result
              @result
            end
          end

          def shutdown
            @server&.close rescue nil # rubocop:disable Style/RescueModifier
            @thread&.join(2)
            @thread&.kill
          end

          def redirect_uri
            "http://127.0.0.1:#{@port}/callback"
          end

          private

          def listen
            loop do
              client = @server.accept
              request_line = client.gets
              loop do
                line = client.gets
                break if line.nil? || line.strip.empty?
              end

              if request_line&.include?('/callback?')
                query = request_line.split[1].split('?', 2).last
                params = URI.decode_www_form(query).to_h

                @mutex.synchronize do
                  @result = { code: params['code'], state: params['state'] }
                  @cv.broadcast
                end
              end

              client.print "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n#{RESPONSE_HTML}"
              client.close
              break if @result
            end
          rescue IOError # rubocop:disable Legion/RescueLogging/NoCapture
            nil
          rescue StandardError => e
            @mutex.synchronize do
              @result ||= { error: e.message }
              @cv.broadcast
            end
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/helpers/callback_server.rb \
        spec/legion/extensions/github/helpers/callback_server_spec.rb
git commit -m "add Helpers::CallbackServer for ephemeral OAuth callback listener"
```

---

### Task 22: Helpers::BrowserAuth — browser + device code orchestration

**Files:**
- Create: `lib/legion/extensions/github/helpers/browser_auth.rb`
- Create: `spec/legion/extensions/github/helpers/browser_auth_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/helpers/browser_auth_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Helpers::BrowserAuth do
  let(:oauth_runner) { Object.new.extend(Legion::Extensions::Github::OAuth::Runners::Auth) }
  let(:auth) { described_class.new(client_id: 'Iv1.abc', client_secret: 'secret', auth: oauth_runner) }

  describe '#gui_available?' do
    it 'returns true on macOS' do
      allow(auth).to receive(:host_os).and_return('darwin23')
      expect(auth.gui_available?).to be true
    end

    it 'returns false on headless linux without DISPLAY' do
      allow(auth).to receive(:host_os).and_return('linux-gnu')
      allow(ENV).to receive(:[]).with('DISPLAY').and_return(nil)
      allow(ENV).to receive(:[]).with('WAYLAND_DISPLAY').and_return(nil)
      expect(auth.gui_available?).to be false
    end
  end

  describe '#authenticate' do
    context 'without GUI' do
      before do
        allow(auth).to receive(:gui_available?).and_return(false)
      end

      it 'falls back to device code flow' do
        expect(oauth_runner).to receive(:request_device_code).and_return(
          result: { 'device_code' => 'dc', 'user_code' => 'ABCD',
                    'verification_uri' => 'https://github.com/login/device',
                    'expires_in' => 900, 'interval' => 5 }
        )
        expect(oauth_runner).to receive(:poll_device_code).and_return(
          result: { 'access_token' => 'ghu_device' }
        )
        result = auth.authenticate
        expect(result[:result]['access_token']).to eq('ghu_device')
      end
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/helpers/browser_auth_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/helpers/browser_auth.rb`:

```ruby
# frozen_string_literal: true

require 'securerandom'
require 'rbconfig'
require 'legion/extensions/github/oauth/runners/auth'
require 'legion/extensions/github/helpers/callback_server'

module Legion
  module Extensions
    module Github
      module Helpers
        class BrowserAuth
          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)

          DEFAULT_SCOPES = 'repo admin:org admin:repo_hook read:user'

          attr_reader :client_id, :client_secret, :scopes

          def initialize(client_id:, client_secret:, scopes: DEFAULT_SCOPES, auth: nil, **)
            @client_id = client_id
            @client_secret = client_secret
            @scopes = scopes
            @auth = auth || Object.new.extend(OAuth::Runners::Auth)
          end

          def authenticate
            if gui_available?
              authenticate_browser
            else
              authenticate_device_code
            end
          end

          def gui_available?
            os = host_os
            return true if /darwin|mswin|mingw/.match?(os)

            !ENV['DISPLAY'].nil? || !ENV['WAYLAND_DISPLAY'].nil?
          end

          def open_browser(url)
            cmd = case host_os
                  when /darwin/      then 'open'
                  when /linux/       then 'xdg-open'
                  when /mswin|mingw/ then 'start'
                  end
            return false unless cmd

            system(cmd, url)
          end

          private

          def host_os
            RbConfig::CONFIG['host_os']
          end

          def authenticate_browser
            pkce = @auth.generate_pkce[:result]
            state = SecureRandom.hex(32)

            server = CallbackServer.new
            server.start
            callback_uri = server.redirect_uri

            url = @auth.authorize_url(
              client_id: client_id, redirect_uri: callback_uri,
              scope: scopes, state: state,
              code_challenge: pkce[:challenge],
              code_challenge_method: pkce[:challenge_method]
            )[:result]

            unless open_browser(url)
              return authenticate_device_code
            end

            result = server.wait_for_callback(timeout: 120)

            unless result&.dig(:code)
              return { error: 'timeout', description: 'No callback received within timeout' }
            end

            unless result[:state] == state
              return { error: 'state_mismatch', description: 'CSRF state parameter mismatch' }
            end

            @auth.exchange_code(
              client_id: client_id, client_secret: client_secret,
              code: result[:code], redirect_uri: callback_uri,
              code_verifier: pkce[:verifier]
            )
          ensure
            server&.shutdown
          end

          def authenticate_device_code
            dc = @auth.request_device_code(client_id: client_id, scope: scopes)
            return { error: dc[:error], description: dc[:description] } if dc[:error]

            body = dc[:result]
            $stderr.puts "Go to:  #{body['verification_uri']}"
            $stderr.puts "Code:   #{body['user_code']}"
            open_browser(body['verification_uri']) if gui_available?

            @auth.poll_device_code(
              client_id: client_id,
              device_code: body['device_code']
            )
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/helpers/browser_auth.rb \
        spec/legion/extensions/github/helpers/browser_auth_spec.rb
git commit -m "add Helpers::BrowserAuth for browser and device code OAuth orchestration"
```

---

### Task 23: CLI::Auth — `legion lex exec github auth login`

**Files:**
- Create: `lib/legion/extensions/github/cli/auth.rb`
- Create: `spec/legion/extensions/github/cli/auth_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/cli/auth_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::CLI::Auth do
  let(:cli) { Object.new.extend(described_class) }
  let(:browser_auth) { instance_double(Legion::Extensions::Github::Helpers::BrowserAuth) }

  before do
    allow(Legion::Extensions::Github::Helpers::BrowserAuth).to receive(:new).and_return(browser_auth)
  end

  describe '#login' do
    it 'authenticates and returns token result' do
      allow(browser_auth).to receive(:authenticate).and_return(
        result: { 'access_token' => 'ghu_test', 'refresh_token' => 'ghr_test' }
      )
      result = cli.login(client_id: 'Iv1.abc', client_secret: 'secret')
      expect(result[:result]['access_token']).to eq('ghu_test')
    end
  end

  describe '#status' do
    it 'returns current auth info when token available' do
      allow(cli).to receive(:resolve_credential).and_return(
        { token: 'ghp_test', auth_type: :pat }
      )
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get('/user') do
        [200, { 'Content-Type' => 'application/json' }, { 'login' => 'octocat' }]
      end
      conn = Faraday.new(url: 'https://api.github.com') do |f|
        f.response :json, content_type: /\bjson$/
        f.adapter :test, stubs
      end
      allow(cli).to receive(:connection).and_return(conn)

      result = cli.status
      expect(result[:result][:auth_type]).to eq(:pat)
      expect(result[:result][:user]).to eq('octocat')
    end

    it 'returns unauthenticated when no credentials' do
      allow(cli).to receive(:resolve_credential).and_return(nil)
      result = cli.status
      expect(result[:result][:authenticated]).to be false
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/cli/auth_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/cli/auth.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/browser_auth'

module Legion
  module Extensions
    module Github
      module CLI
        module Auth
          include Helpers::Client

          def login(client_id: nil, client_secret: nil, scopes: nil, **)
            cid = client_id || settings_client_id
            csec = client_secret || settings_client_secret
            sc = scopes || settings_scopes

            unless cid && csec
              return { error: 'missing_config',
                       description: 'Set github.oauth.client_id and github.app.client_secret in settings or pass as arguments' }
            end

            browser = Helpers::BrowserAuth.new(client_id: cid, client_secret: csec, scopes: sc)
            result = browser.authenticate

            if result[:result]&.dig('access_token') && respond_to?(:store_oauth_token, true)
              user = current_user(token: result[:result]['access_token']) rescue 'default'
              store_oauth_token(
                user: user,
                access_token: result[:result]['access_token'],
                refresh_token: result[:result]['refresh_token'],
                expires_in: result[:result]['expires_in']
              )
            end

            result
          end

          def status(**)
            cred = resolve_credential
            return { result: { authenticated: false } } unless cred

            user_info = connection(token: cred[:token]).get('/user').body rescue {}
            { result: { authenticated: true, auth_type: cred[:auth_type],
                        user: user_info['login'], scopes: user_info['scopes'] } }
          end

          private

          def current_user(token:)
            connection(token: token).get('/user').body['login']
          end

          def settings_client_id
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :oauth, :client_id) ||
              Legion::Settings.dig(:github, :app, :client_id)
          rescue StandardError
            nil
          end

          def settings_client_secret
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :app, :client_secret)
          rescue StandardError
            nil
          end

          def settings_scopes
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :oauth, :scopes)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/cli/auth.rb \
        spec/legion/extensions/github/cli/auth_spec.rb
git commit -m "add CLI::Auth for legion lex exec github auth login/status"
```

---

### Task 24: CLI::App — `legion lex exec github app setup`

**Files:**
- Create: `lib/legion/extensions/github/cli/app.rb`
- Create: `spec/legion/extensions/github/cli/app_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/cli/app_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::CLI::App do
  let(:cli) { Object.new.extend(described_class) }
  let(:server) { instance_double(Legion::Extensions::Github::Helpers::CallbackServer) }

  before do
    allow(Legion::Extensions::Github::Helpers::CallbackServer).to receive(:new).and_return(server)
    allow(server).to receive(:start)
    allow(server).to receive(:shutdown)
    allow(server).to receive(:port).and_return(12345)
    allow(server).to receive(:redirect_uri).and_return('http://127.0.0.1:12345/callback')
  end

  describe '#setup' do
    it 'generates manifest and returns manifest URL' do
      result = cli.setup(
        name: 'LegionIO Bot',
        url: 'https://legionio.dev',
        webhook_url: 'https://legion.example.com/api/hooks/lex/github/app/webhook'
      )
      expect(result[:result][:manifest_url]).to include('github.com/settings/apps/new')
    end

    it 'supports org-scoped setup' do
      result = cli.setup(
        name: 'LegionIO Bot',
        url: 'https://legionio.dev',
        webhook_url: 'https://legion.example.com/webhook',
        org: 'LegionIO'
      )
      expect(result[:result][:manifest_url]).to include('/organizations/LegionIO/')
    end
  end

  describe '#complete_setup' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:test_connection) do
      Faraday.new(url: 'https://api.github.com') do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, stubs
      end
    end

    before { allow(cli).to receive(:connection).and_return(test_connection) }

    it 'exchanges manifest code and stores credentials' do
      stubs.post('/app-manifests/test-code/conversions') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 12345, 'pem' => '-----BEGIN RSA...', 'client_id' => 'Iv1.abc',
           'client_secret' => 'secret', 'webhook_secret' => 'whsec' }]
      end
      allow(cli).to receive(:store_app_credentials)

      result = cli.complete_setup(code: 'test-code')
      expect(result[:result]['id']).to eq(12345)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/cli/app_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/cli/app.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/callback_server'
require 'legion/extensions/github/app/runners/manifest'
require 'legion/extensions/github/app/runners/credential_store'

module Legion
  module Extensions
    module Github
      module CLI
        module App
          include Helpers::Client
          include Github::App::Runners::Manifest
          include Github::App::Runners::CredentialStore

          def setup(name:, url:, webhook_url:, org: nil, **)
            server = Helpers::CallbackServer.new
            server.start
            callback_url = server.redirect_uri

            manifest = generate_manifest(
              name: name, url: url,
              webhook_url: webhook_url,
              callback_url: callback_url
            )[:result]

            url_result = manifest_url(manifest: manifest, org: org)[:result]

            { result: { manifest_url: url_result, callback_port: server.port,
                        message: 'Open the manifest URL in your browser to create the GitHub App' } }
          ensure
            server&.shutdown
          end

          def complete_setup(code:, **)
            result = exchange_manifest_code(code: code)[:result]
            return { error: 'exchange_failed' } unless result&.dig('id')

            if respond_to?(:store_app_credentials, true)
              store_app_credentials(
                app_id: result['id'].to_s,
                private_key: result['pem'],
                client_id: result['client_id'],
                client_secret: result['client_secret'],
                webhook_secret: result['webhook_secret']
              )
            end

            { result: result }
          end
        end
      end
    end
  end
end
```

**Step 4: Run tests + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/cli/app.rb \
        spec/legion/extensions/github/cli/app_spec.rb
git commit -m "add CLI::App for legion lex exec github app setup/complete_setup"
```

---

### Task 25: Retrofit existing runners with caching

**Files:**
- Modify: `lib/legion/extensions/github/runners/repositories.rb`
- Modify: `lib/legion/extensions/github/runners/issues.rb`
- Modify: `lib/legion/extensions/github/runners/pull_requests.rb`
- Modify: `lib/legion/extensions/github/runners/users.rb`
- Modify: `lib/legion/extensions/github/runners/organizations.rb`
- Modify: `lib/legion/extensions/github/runners/commits.rb`
- Modify: `lib/legion/extensions/github/runners/search.rb`
- Modify: `lib/legion/extensions/github/runners/gists.rb`
- Modify: `lib/legion/extensions/github/runners/labels.rb`
- Modify: `lib/legion/extensions/github/runners/comments.rb`
- Modify: `lib/legion/extensions/github/runners/branches.rb`
- Modify: `lib/legion/extensions/github/runners/contents.rb`
- Modify: 12 corresponding spec files

This task is large — break it into sub-steps per runner. Pattern is identical for each. Example for Repositories:

**Step 1: Add `include Helpers::Cache` to the runner**

In `lib/legion/extensions/github/runners/repositories.rb`, add after `include Helpers::Client`:

```ruby
include Legion::Extensions::Github::Helpers::Cache
```

**Step 2: Wrap GET methods with `cached_get`**

Before:
```ruby
def get_repo(owner:, repo:, **)
  response = connection(**).get("/repos/#{owner}/#{repo}")
  { result: response.body }
end
```

After:
```ruby
def get_repo(owner:, repo:, **)
  cached_get("github:repo:#{owner}/#{repo}") do
    response = connection(**).get("/repos/#{owner}/#{repo}")
    response.body
  end.then { |body| { result: body } }
end
```

**Step 3: Wrap mutations with `cache_write`**

Before:
```ruby
def create_repo(name:, description: nil, private: false, **)
  body = { name: name, description: description, private: private }
  response = connection(**).post('/user/repos', body)
  { result: response.body }
end
```

After:
```ruby
def create_repo(name:, description: nil, private: false, **)
  body = { name: name, description: description, private: private }
  response = connection(**).post('/user/repos', body)
  result = response.body
  if result['full_name']
    cache_write("github:repo:#{result['full_name']}", result)
  end
  { result: result }
end
```

**Step 4: Update specs to mock cache helpers**

Add to each spec's `before` block:

```ruby
allow(client).to receive(:cache_connected?).and_return(false)
allow(client).to receive(:local_cache_connected?).and_return(false)
```

This ensures existing tests pass without a cache backend.

**Step 5: Repeat for all 12 runners**

Apply the same pattern:
- `get_*` methods → `cached_get` with appropriate cache key
- `list_*` methods → `cached_get` (short TTL, key includes pagination params hash)
- `create_*` / `update_*` methods → `cache_write` after success
- `delete_*` methods → `cache_invalidate` after success
- `search_*` methods → `cached_get` with `search:{type}:{Digest::MD5.hexdigest(query)}` key

Cache key mapping per runner:

| Runner | GET key pattern | Mutation behavior |
|--------|----------------|-------------------|
| Repositories | `github:repo:{owner}/{repo}` | create → write, delete → invalidate |
| Issues | `github:repo:{owner}/{repo}:issues:{number}` | create/update → write |
| PullRequests | `github:repo:{owner}/{repo}:pulls:{number}` | create/update/merge → write |
| Users | `github:user:{username}` | read-only |
| Organizations | `github:org:{org}` | read-only |
| Commits | `github:repo:{owner}/{repo}:commits:{sha}` | read-only |
| Search | `github:search:{type}:{query_hash}` | read-only |
| Gists | `github:gist:{id}` | create/update → write, delete → invalidate |
| Labels | `github:repo:{owner}/{repo}:labels:{name}` | create/update → write, delete → invalidate |
| Comments | `github:repo:{owner}/{repo}:comments:{id}` | create/update → write, delete → invalidate |
| Branches | `github:repo:{owner}/{repo}:branches:{name}` | create → write |
| Contents | n/a (file commits vary) | write → invalidate branch cache |

**Step 6: Run full suite**

Run: `bundle exec rspec`
Expected: All pass

**Step 7: Rubocop + commit**

```bash
bundle exec rubocop -A && bundle exec rubocop
git add lib/legion/extensions/github/runners/*.rb spec/legion/extensions/github/runners/*_spec.rb
git commit -m "retrofit all existing runners with two-tier API response caching"
```

---

## Phase 3: New API Runners (no transport dependency)

These add coverage for GitHub APIs critical to a self-building system: CI/CD, checks, releases, deployments, and webhook management.

---

### Task 26: Runners::Actions — GitHub Actions workflow management

**Files:**
- Create: `lib/legion/extensions/github/runners/actions.rb`
- Create: `spec/legion/extensions/github/runners/actions_spec.rb`
- Modify: `lib/legion/extensions/github.rb` (add require)
- Modify: `lib/legion/extensions/github/client.rb` (add include)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/runners/actions_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Actions do
  let(:client) { Legion::Extensions::Github::Client.new(token: 'test-token') }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(client).to receive(:connection).and_return(test_connection) }

  describe '#list_workflows' do
    it 'returns workflows for a repo' do
      stubs.get('/repos/LegionIO/lex-github/actions/workflows') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'workflows' => [{ 'id' => 1, 'name' => 'CI' }] }]
      end
      result = client.list_workflows(owner: 'LegionIO', repo: 'lex-github')
      expect(result[:result]['workflows'].first['name']).to eq('CI')
    end
  end

  describe '#get_workflow' do
    it 'returns a single workflow' do
      stubs.get('/repos/LegionIO/lex-github/actions/workflows/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'name' => 'CI', 'state' => 'active' }]
      end
      result = client.get_workflow(owner: 'LegionIO', repo: 'lex-github', workflow_id: 1)
      expect(result[:result]['state']).to eq('active')
    end
  end

  describe '#list_workflow_runs' do
    it 'returns runs for a workflow' do
      stubs.get('/repos/LegionIO/lex-github/actions/workflows/1/runs') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'workflow_runs' => [{ 'id' => 100, 'status' => 'completed' }] }]
      end
      result = client.list_workflow_runs(owner: 'LegionIO', repo: 'lex-github', workflow_id: 1)
      expect(result[:result]['workflow_runs'].first['status']).to eq('completed')
    end
  end

  describe '#get_workflow_run' do
    it 'returns a single run' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 100, 'status' => 'completed', 'conclusion' => 'success' }]
      end
      result = client.get_workflow_run(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#trigger_workflow' do
    it 'dispatches a workflow run' do
      stubs.post('/repos/LegionIO/lex-github/actions/workflows/1/dispatches') do
        [204, {}, '']
      end
      result = client.trigger_workflow(owner: 'LegionIO', repo: 'lex-github',
                                       workflow_id: 1, ref: 'main')
      expect(result[:result]).to be true
    end
  end

  describe '#cancel_workflow_run' do
    it 'cancels a running workflow' do
      stubs.post('/repos/LegionIO/lex-github/actions/runs/100/cancel') do
        [202, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.cancel_workflow_run(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be true
    end
  end

  describe '#rerun_workflow' do
    it 'reruns a workflow' do
      stubs.post('/repos/LegionIO/lex-github/actions/runs/100/rerun') do
        [201, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.rerun_workflow(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be true
    end
  end

  describe '#rerun_failed_jobs' do
    it 'reruns only failed jobs in a workflow run' do
      stubs.post('/repos/LegionIO/lex-github/actions/runs/100/rerun-failed-jobs') do
        [201, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.rerun_failed_jobs(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be true
    end
  end

  describe '#list_workflow_run_jobs' do
    it 'returns jobs for a run' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100/jobs') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'jobs' => [{ 'id' => 200, 'name' => 'test', 'conclusion' => 'success' }] }]
      end
      result = client.list_workflow_run_jobs(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]['jobs'].first['name']).to eq('test')
    end
  end

  describe '#download_workflow_run_logs' do
    it 'returns the log download URL' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100/logs') do
        [200, { 'Content-Type' => 'application/json', 'Location' => 'https://logs.example.com/100.zip' }, '']
      end
      result = client.download_workflow_run_logs(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be_a(Hash)
    end
  end

  describe '#list_workflow_run_artifacts' do
    it 'returns artifacts for a run' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100/artifacts') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'artifacts' => [{ 'id' => 300, 'name' => 'coverage' }] }]
      end
      result = client.list_workflow_run_artifacts(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]['artifacts'].first['name']).to eq('coverage')
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/runners/actions_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/runners/actions.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Actions
          include Legion::Extensions::Github::Helpers::Client

          def list_workflows(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/actions/workflows",
                                         per_page: per_page, page: page)
            { result: response.body }
          end

          def get_workflow(owner:, repo:, workflow_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}")
            { result: response.body }
          end

          def list_workflow_runs(owner:, repo:, workflow_id:, status: nil, branch: nil,
                                per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page, status: status, branch: branch }.compact
            response = connection(**).get("/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/runs", params)
            { result: response.body }
          end

          def get_workflow_run(owner:, repo:, run_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}")
            { result: response.body }
          end

          def trigger_workflow(owner:, repo:, workflow_id:, ref:, inputs: {}, **)
            payload = { ref: ref, inputs: inputs }
            response = connection(**).post("/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/dispatches", payload)
            { result: response.status == 204 }
          end

          def cancel_workflow_run(owner:, repo:, run_id:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/cancel")
            { result: [202, 204].include?(response.status) }
          end

          def rerun_workflow(owner:, repo:, run_id:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun")
            { result: [201, 204].include?(response.status) }
          end

          def rerun_failed_jobs(owner:, repo:, run_id:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun-failed-jobs")
            { result: [201, 204].include?(response.status) }
          end

          def list_workflow_run_jobs(owner:, repo:, run_id:, filter: 'latest', per_page: 30, page: 1, **)
            params = { filter: filter, per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/jobs", params)
            { result: response.body }
          end

          def download_workflow_run_logs(owner:, repo:, run_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/logs")
            { result: { status: response.status, headers: response.headers.to_h, body: response.body } }
          end

          def list_workflow_run_artifacts(owner:, repo:, run_id:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/actions/runs/#{run_id}/artifacts", params)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
```

**Step 4: Add require to `github.rb`, add include to `client.rb`**

In `lib/legion/extensions/github.rb`, add:
```ruby
require 'legion/extensions/github/runners/actions'
```

In `lib/legion/extensions/github/client.rb`, add:
```ruby
include Runners::Actions
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/runners/actions_spec.rb`
Expected: All 11 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/runners/actions.rb \
        spec/legion/extensions/github/runners/actions_spec.rb \
        lib/legion/extensions/github.rb \
        lib/legion/extensions/github/client.rb
git commit -m "add Runners::Actions for GitHub Actions workflow management"
```

---

### Task 27: Runners::Checks — check runs and check suites

**Files:**
- Create: `lib/legion/extensions/github/runners/checks.rb`
- Create: `spec/legion/extensions/github/runners/checks_spec.rb`
- Modify: `lib/legion/extensions/github.rb` (add require)
- Modify: `lib/legion/extensions/github/client.rb` (add include)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/runners/checks_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Checks do
  let(:client) { Legion::Extensions::Github::Client.new(token: 'test-token') }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(client).to receive(:connection).and_return(test_connection) }

  describe '#create_check_run' do
    it 'creates a check run' do
      stubs.post('/repos/LegionIO/lex-github/check-runs') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'name' => 'Legion CI', 'status' => 'queued' }]
      end
      result = client.create_check_run(owner: 'LegionIO', repo: 'lex-github',
                                       name: 'Legion CI', head_sha: 'abc123')
      expect(result[:result]['name']).to eq('Legion CI')
      expect(result[:result]['status']).to eq('queued')
    end
  end

  describe '#update_check_run' do
    it 'updates a check run with conclusion' do
      stubs.patch('/repos/LegionIO/lex-github/check-runs/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'status' => 'completed', 'conclusion' => 'success' }]
      end
      result = client.update_check_run(owner: 'LegionIO', repo: 'lex-github',
                                       check_run_id: 1, status: 'completed', conclusion: 'success')
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#get_check_run' do
    it 'returns a check run' do
      stubs.get('/repos/LegionIO/lex-github/check-runs/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'name' => 'Legion CI', 'conclusion' => 'success' }]
      end
      result = client.get_check_run(owner: 'LegionIO', repo: 'lex-github', check_run_id: 1)
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#list_check_runs_for_ref' do
    it 'returns check runs for a commit ref' do
      stubs.get('/repos/LegionIO/lex-github/commits/abc123/check-runs') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'check_runs' => [{ 'id' => 1, 'name' => 'Legion CI' }] }]
      end
      result = client.list_check_runs_for_ref(owner: 'LegionIO', repo: 'lex-github', ref: 'abc123')
      expect(result[:result]['check_runs'].first['name']).to eq('Legion CI')
    end
  end

  describe '#list_check_suites_for_ref' do
    it 'returns check suites for a commit ref' do
      stubs.get('/repos/LegionIO/lex-github/commits/abc123/check-suites') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'check_suites' => [{ 'id' => 10, 'status' => 'completed' }] }]
      end
      result = client.list_check_suites_for_ref(owner: 'LegionIO', repo: 'lex-github', ref: 'abc123')
      expect(result[:result]['check_suites'].first['status']).to eq('completed')
    end
  end

  describe '#get_check_suite' do
    it 'returns a check suite' do
      stubs.get('/repos/LegionIO/lex-github/check-suites/10') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 10, 'status' => 'completed', 'conclusion' => 'success' }]
      end
      result = client.get_check_suite(owner: 'LegionIO', repo: 'lex-github', check_suite_id: 10)
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#rerequest_check_suite' do
    it 'rerequests a check suite' do
      stubs.post('/repos/LegionIO/lex-github/check-suites/10/rerequest') do
        [201, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.rerequest_check_suite(owner: 'LegionIO', repo: 'lex-github', check_suite_id: 10)
      expect(result[:result]).to be true
    end
  end

  describe '#list_check_run_annotations' do
    it 'returns annotations for a check run' do
      stubs.get('/repos/LegionIO/lex-github/check-runs/1/annotations') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'path' => 'lib/foo.rb', 'message' => 'Lint error', 'annotation_level' => 'warning' }]]
      end
      result = client.list_check_run_annotations(owner: 'LegionIO', repo: 'lex-github', check_run_id: 1)
      expect(result[:result].first['annotation_level']).to eq('warning')
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/runners/checks_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/runners/checks.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Checks
          include Legion::Extensions::Github::Helpers::Client

          def create_check_run(owner:, repo:, name:, head_sha:, status: nil,
                               conclusion: nil, output: nil, details_url: nil, **)
            payload = { name: name, head_sha: head_sha, status: status,
                        conclusion: conclusion, output: output, details_url: details_url }.compact
            response = connection(**).post("/repos/#{owner}/#{repo}/check-runs", payload)
            { result: response.body }
          end

          def update_check_run(owner:, repo:, check_run_id:, **opts)
            payload = opts.slice(:name, :status, :conclusion, :output, :details_url,
                                 :started_at, :completed_at)
            response = connection(**opts).patch("/repos/#{owner}/#{repo}/check-runs/#{check_run_id}", payload)
            { result: response.body }
          end

          def get_check_run(owner:, repo:, check_run_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/check-runs/#{check_run_id}")
            { result: response.body }
          end

          def list_check_runs_for_ref(owner:, repo:, ref:, check_name: nil, status: nil,
                                      per_page: 30, page: 1, **)
            params = { check_name: check_name, status: status,
                       per_page: per_page, page: page }.compact
            response = connection(**).get("/repos/#{owner}/#{repo}/commits/#{ref}/check-runs", params)
            { result: response.body }
          end

          def list_check_suites_for_ref(owner:, repo:, ref:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/commits/#{ref}/check-suites", params)
            { result: response.body }
          end

          def get_check_suite(owner:, repo:, check_suite_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/check-suites/#{check_suite_id}")
            { result: response.body }
          end

          def rerequest_check_suite(owner:, repo:, check_suite_id:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/check-suites/#{check_suite_id}/rerequest")
            { result: [201, 204].include?(response.status) }
          end

          def list_check_run_annotations(owner:, repo:, check_run_id:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/check-runs/#{check_run_id}/annotations", params)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
```

**Step 4: Add require to `github.rb`, add include to `client.rb`**

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/runners/checks_spec.rb`
Expected: All 8 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/runners/checks.rb \
        spec/legion/extensions/github/runners/checks_spec.rb \
        lib/legion/extensions/github.rb \
        lib/legion/extensions/github/client.rb
git commit -m "add Runners::Checks for check runs and check suites"
```

---

### Task 28: Runners::Releases — release and asset management

**Files:**
- Create: `lib/legion/extensions/github/runners/releases.rb`
- Create: `spec/legion/extensions/github/runners/releases_spec.rb`
- Modify: `lib/legion/extensions/github.rb` (add require)
- Modify: `lib/legion/extensions/github/client.rb` (add include)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/runners/releases_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Releases do
  let(:client) { Legion::Extensions::Github::Client.new(token: 'test-token') }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(client).to receive(:connection).and_return(test_connection) }

  describe '#list_releases' do
    it 'returns releases for a repo' do
      stubs.get('/repos/LegionIO/lex-github/releases') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 1, 'tag_name' => 'v0.3.0' }]]
      end
      result = client.list_releases(owner: 'LegionIO', repo: 'lex-github')
      expect(result[:result].first['tag_name']).to eq('v0.3.0')
    end
  end

  describe '#get_release' do
    it 'returns a single release' do
      stubs.get('/repos/LegionIO/lex-github/releases/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'tag_name' => 'v0.3.0', 'name' => 'v0.3.0' }]
      end
      result = client.get_release(owner: 'LegionIO', repo: 'lex-github', release_id: 1)
      expect(result[:result]['tag_name']).to eq('v0.3.0')
    end
  end

  describe '#get_latest_release' do
    it 'returns the latest release' do
      stubs.get('/repos/LegionIO/lex-github/releases/latest') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'tag_name' => 'v0.3.0' }]
      end
      result = client.get_latest_release(owner: 'LegionIO', repo: 'lex-github')
      expect(result[:result]['tag_name']).to eq('v0.3.0')
    end
  end

  describe '#get_release_by_tag' do
    it 'returns a release by tag name' do
      stubs.get('/repos/LegionIO/lex-github/releases/tags/v0.3.0') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'tag_name' => 'v0.3.0' }]
      end
      result = client.get_release_by_tag(owner: 'LegionIO', repo: 'lex-github', tag: 'v0.3.0')
      expect(result[:result]['tag_name']).to eq('v0.3.0')
    end
  end

  describe '#create_release' do
    it 'creates a release' do
      stubs.post('/repos/LegionIO/lex-github/releases') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 2, 'tag_name' => 'v0.4.0', 'name' => 'v0.4.0' }]
      end
      result = client.create_release(owner: 'LegionIO', repo: 'lex-github',
                                     tag_name: 'v0.4.0', name: 'v0.4.0')
      expect(result[:result]['tag_name']).to eq('v0.4.0')
    end
  end

  describe '#update_release' do
    it 'updates a release' do
      stubs.patch('/repos/LegionIO/lex-github/releases/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'name' => 'Updated Release' }]
      end
      result = client.update_release(owner: 'LegionIO', repo: 'lex-github',
                                     release_id: 1, name: 'Updated Release')
      expect(result[:result]['name']).to eq('Updated Release')
    end
  end

  describe '#delete_release' do
    it 'deletes a release' do
      stubs.delete('/repos/LegionIO/lex-github/releases/1') { [204, {}, ''] }
      result = client.delete_release(owner: 'LegionIO', repo: 'lex-github', release_id: 1)
      expect(result[:result]).to be true
    end
  end

  describe '#list_release_assets' do
    it 'returns assets for a release' do
      stubs.get('/repos/LegionIO/lex-github/releases/1/assets') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 50, 'name' => 'lex-github-0.3.0.gem' }]]
      end
      result = client.list_release_assets(owner: 'LegionIO', repo: 'lex-github', release_id: 1)
      expect(result[:result].first['name']).to eq('lex-github-0.3.0.gem')
    end
  end

  describe '#delete_release_asset' do
    it 'deletes a release asset' do
      stubs.delete('/repos/LegionIO/lex-github/releases/assets/50') { [204, {}, ''] }
      result = client.delete_release_asset(owner: 'LegionIO', repo: 'lex-github', asset_id: 50)
      expect(result[:result]).to be true
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/runners/releases_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/runners/releases.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Releases
          include Legion::Extensions::Github::Helpers::Client

          def list_releases(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/releases",
                                         per_page: per_page, page: page)
            { result: response.body }
          end

          def get_release(owner:, repo:, release_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/releases/#{release_id}")
            { result: response.body }
          end

          def get_latest_release(owner:, repo:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/releases/latest")
            { result: response.body }
          end

          def get_release_by_tag(owner:, repo:, tag:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/releases/tags/#{tag}")
            { result: response.body }
          end

          def create_release(owner:, repo:, tag_name:, name: nil, body: nil,
                             target_commitish: nil, draft: false, prerelease: false,
                             generate_release_notes: false, **)
            payload = { tag_name: tag_name, name: name, body: body,
                        target_commitish: target_commitish, draft: draft,
                        prerelease: prerelease,
                        generate_release_notes: generate_release_notes }.compact
            response = connection(**).post("/repos/#{owner}/#{repo}/releases", payload)
            { result: response.body }
          end

          def update_release(owner:, repo:, release_id:, **opts)
            payload = opts.slice(:tag_name, :name, :body, :draft, :prerelease,
                                 :target_commitish)
            response = connection(**opts).patch("/repos/#{owner}/#{repo}/releases/#{release_id}", payload)
            { result: response.body }
          end

          def delete_release(owner:, repo:, release_id:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}/releases/#{release_id}")
            { result: response.status == 204 }
          end

          def list_release_assets(owner:, repo:, release_id:, per_page: 30, page: 1, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/releases/#{release_id}/assets",
                                         per_page: per_page, page: page)
            { result: response.body }
          end

          def delete_release_asset(owner:, repo:, asset_id:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}/releases/assets/#{asset_id}")
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
```

**Step 4: Add require to `github.rb`, add include to `client.rb`**

**Step 5: Run tests + full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/runners/releases.rb \
        spec/legion/extensions/github/runners/releases_spec.rb \
        lib/legion/extensions/github.rb \
        lib/legion/extensions/github/client.rb
git commit -m "add Runners::Releases for release and asset management"
```

---

### Task 29: Runners::Deployments — deployment and status management

**Files:**
- Create: `lib/legion/extensions/github/runners/deployments.rb`
- Create: `spec/legion/extensions/github/runners/deployments_spec.rb`
- Modify: `lib/legion/extensions/github.rb` (add require)
- Modify: `lib/legion/extensions/github/client.rb` (add include)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/runners/deployments_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Deployments do
  let(:client) { Legion::Extensions::Github::Client.new(token: 'test-token') }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(client).to receive(:connection).and_return(test_connection) }

  describe '#list_deployments' do
    it 'returns deployments for a repo' do
      stubs.get('/repos/LegionIO/lex-github/deployments') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 1, 'ref' => 'main', 'environment' => 'production' }]]
      end
      result = client.list_deployments(owner: 'LegionIO', repo: 'lex-github')
      expect(result[:result].first['environment']).to eq('production')
    end
  end

  describe '#get_deployment' do
    it 'returns a single deployment' do
      stubs.get('/repos/LegionIO/lex-github/deployments/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'ref' => 'main', 'environment' => 'production' }]
      end
      result = client.get_deployment(owner: 'LegionIO', repo: 'lex-github', deployment_id: 1)
      expect(result[:result]['ref']).to eq('main')
    end
  end

  describe '#create_deployment' do
    it 'creates a deployment' do
      stubs.post('/repos/LegionIO/lex-github/deployments') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 2, 'ref' => 'v0.3.0', 'environment' => 'staging' }]
      end
      result = client.create_deployment(owner: 'LegionIO', repo: 'lex-github',
                                        ref: 'v0.3.0', environment: 'staging')
      expect(result[:result]['environment']).to eq('staging')
    end
  end

  describe '#delete_deployment' do
    it 'deletes a deployment' do
      stubs.delete('/repos/LegionIO/lex-github/deployments/1') { [204, {}, ''] }
      result = client.delete_deployment(owner: 'LegionIO', repo: 'lex-github', deployment_id: 1)
      expect(result[:result]).to be true
    end
  end

  describe '#list_deployment_statuses' do
    it 'returns statuses for a deployment' do
      stubs.get('/repos/LegionIO/lex-github/deployments/1/statuses') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 10, 'state' => 'success', 'description' => 'Deployed' }]]
      end
      result = client.list_deployment_statuses(owner: 'LegionIO', repo: 'lex-github', deployment_id: 1)
      expect(result[:result].first['state']).to eq('success')
    end
  end

  describe '#create_deployment_status' do
    it 'creates a deployment status' do
      stubs.post('/repos/LegionIO/lex-github/deployments/1/statuses') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 11, 'state' => 'in_progress', 'description' => 'Deploying...' }]
      end
      result = client.create_deployment_status(owner: 'LegionIO', repo: 'lex-github',
                                               deployment_id: 1, state: 'in_progress',
                                               description: 'Deploying...')
      expect(result[:result]['state']).to eq('in_progress')
    end
  end

  describe '#get_deployment_status' do
    it 'returns a single deployment status' do
      stubs.get('/repos/LegionIO/lex-github/deployments/1/statuses/10') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 10, 'state' => 'success' }]
      end
      result = client.get_deployment_status(owner: 'LegionIO', repo: 'lex-github',
                                            deployment_id: 1, status_id: 10)
      expect(result[:result]['state']).to eq('success')
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/runners/deployments_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/runners/deployments.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Deployments
          include Legion::Extensions::Github::Helpers::Client

          def list_deployments(owner:, repo:, environment: nil, ref: nil, per_page: 30, page: 1, **)
            params = { environment: environment, ref: ref,
                       per_page: per_page, page: page }.compact
            response = connection(**).get("/repos/#{owner}/#{repo}/deployments", params)
            { result: response.body }
          end

          def get_deployment(owner:, repo:, deployment_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/deployments/#{deployment_id}")
            { result: response.body }
          end

          def create_deployment(owner:, repo:, ref:, environment: 'production',
                                description: nil, auto_merge: true, required_contexts: nil, **)
            payload = { ref: ref, environment: environment, description: description,
                        auto_merge: auto_merge, required_contexts: required_contexts }.compact
            response = connection(**).post("/repos/#{owner}/#{repo}/deployments", payload)
            { result: response.body }
          end

          def delete_deployment(owner:, repo:, deployment_id:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}/deployments/#{deployment_id}")
            { result: response.status == 204 }
          end

          def list_deployment_statuses(owner:, repo:, deployment_id:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/deployments/#{deployment_id}/statuses", params)
            { result: response.body }
          end

          def create_deployment_status(owner:, repo:, deployment_id:, state:,
                                       description: nil, environment_url: nil, log_url: nil, **)
            payload = { state: state, description: description,
                        environment_url: environment_url, log_url: log_url }.compact
            response = connection(**).post("/repos/#{owner}/#{repo}/deployments/#{deployment_id}/statuses", payload)
            { result: response.body }
          end

          def get_deployment_status(owner:, repo:, deployment_id:, status_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/deployments/#{deployment_id}/statuses/#{status_id}")
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
```

**Step 4: Add require to `github.rb`, add include to `client.rb`**

**Step 5: Run tests + full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/runners/deployments.rb \
        spec/legion/extensions/github/runners/deployments_spec.rb \
        lib/legion/extensions/github.rb \
        lib/legion/extensions/github/client.rb
git commit -m "add Runners::Deployments for deployment and status management"
```

---

### Task 30: Runners::RepositoryWebhooks — programmatic webhook management

**Files:**
- Create: `lib/legion/extensions/github/runners/repository_webhooks.rb`
- Create: `spec/legion/extensions/github/runners/repository_webhooks_spec.rb`
- Modify: `lib/legion/extensions/github.rb` (add require)
- Modify: `lib/legion/extensions/github/client.rb` (add include)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/runners/repository_webhooks_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::RepositoryWebhooks do
  let(:client) { Legion::Extensions::Github::Client.new(token: 'test-token') }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(client).to receive(:connection).and_return(test_connection) }

  describe '#list_webhooks' do
    it 'returns webhooks for a repo' do
      stubs.get('/repos/LegionIO/lex-github/hooks') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 1, 'active' => true, 'events' => ['push'] }]]
      end
      result = client.list_webhooks(owner: 'LegionIO', repo: 'lex-github')
      expect(result[:result].first['events']).to include('push')
    end
  end

  describe '#get_webhook' do
    it 'returns a single webhook' do
      stubs.get('/repos/LegionIO/lex-github/hooks/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'config' => { 'url' => 'https://legion.example.com/webhook' } }]
      end
      result = client.get_webhook(owner: 'LegionIO', repo: 'lex-github', hook_id: 1)
      expect(result[:result]['config']['url']).to include('legion')
    end
  end

  describe '#create_webhook' do
    it 'creates a webhook' do
      stubs.post('/repos/LegionIO/lex-github/hooks') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 2, 'active' => true, 'events' => %w[push pull_request] }]
      end
      result = client.create_webhook(
        owner: 'LegionIO', repo: 'lex-github',
        config: { url: 'https://legion.example.com/webhook', content_type: 'json', secret: 'whsec' },
        events: %w[push pull_request]
      )
      expect(result[:result]['events']).to include('pull_request')
    end
  end

  describe '#update_webhook' do
    it 'updates a webhook' do
      stubs.patch('/repos/LegionIO/lex-github/hooks/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'active' => false }]
      end
      result = client.update_webhook(owner: 'LegionIO', repo: 'lex-github',
                                     hook_id: 1, active: false)
      expect(result[:result]['active']).to be false
    end
  end

  describe '#delete_webhook' do
    it 'deletes a webhook' do
      stubs.delete('/repos/LegionIO/lex-github/hooks/1') { [204, {}, ''] }
      result = client.delete_webhook(owner: 'LegionIO', repo: 'lex-github', hook_id: 1)
      expect(result[:result]).to be true
    end
  end

  describe '#ping_webhook' do
    it 'pings a webhook' do
      stubs.post('/repos/LegionIO/lex-github/hooks/1/pings') { [204, {}, ''] }
      result = client.ping_webhook(owner: 'LegionIO', repo: 'lex-github', hook_id: 1)
      expect(result[:result]).to be true
    end
  end

  describe '#test_webhook' do
    it 'triggers a test push event' do
      stubs.post('/repos/LegionIO/lex-github/hooks/1/tests') { [204, {}, ''] }
      result = client.test_webhook(owner: 'LegionIO', repo: 'lex-github', hook_id: 1)
      expect(result[:result]).to be true
    end
  end

  describe '#list_webhook_deliveries' do
    it 'returns recent deliveries' do
      stubs.get('/repos/LegionIO/lex-github/hooks/1/deliveries') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 100, 'status_code' => 200, 'event' => 'push' }]]
      end
      result = client.list_webhook_deliveries(owner: 'LegionIO', repo: 'lex-github', hook_id: 1)
      expect(result[:result].first['event']).to eq('push')
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/runners/repository_webhooks_spec.rb`
Expected: FAIL

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/runners/repository_webhooks.rb`:

```ruby
# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module RepositoryWebhooks
          include Legion::Extensions::Github::Helpers::Client

          def list_webhooks(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/hooks",
                                         per_page: per_page, page: page)
            { result: response.body }
          end

          def get_webhook(owner:, repo:, hook_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/hooks/#{hook_id}")
            { result: response.body }
          end

          def create_webhook(owner:, repo:, config:, events: ['push'], active: true, **)
            payload = { config: config, events: events, active: active }
            response = connection(**).post("/repos/#{owner}/#{repo}/hooks", payload)
            { result: response.body }
          end

          def update_webhook(owner:, repo:, hook_id:, **opts)
            payload = opts.slice(:config, :events, :active, :add_events, :remove_events)
            response = connection(**opts).patch("/repos/#{owner}/#{repo}/hooks/#{hook_id}", payload)
            { result: response.body }
          end

          def delete_webhook(owner:, repo:, hook_id:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}/hooks/#{hook_id}")
            { result: response.status == 204 }
          end

          def ping_webhook(owner:, repo:, hook_id:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/hooks/#{hook_id}/pings")
            { result: response.status == 204 }
          end

          def test_webhook(owner:, repo:, hook_id:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/hooks/#{hook_id}/tests")
            { result: response.status == 204 }
          end

          def list_webhook_deliveries(owner:, repo:, hook_id:, per_page: 30, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/hooks/#{hook_id}/deliveries",
                                         per_page: per_page)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
```

**Step 4: Add require to `github.rb`, add include to `client.rb`**

**Step 5: Run tests + full suite + commit**

```bash
bundle exec rspec
git add lib/legion/extensions/github/runners/repository_webhooks.rb \
        spec/legion/extensions/github/runners/repository_webhooks_spec.rb \
        lib/legion/extensions/github.rb \
        lib/legion/extensions/github/client.rb
git commit -m "add Runners::RepositoryWebhooks for programmatic webhook management"
```

---

### Task 31: Error classes — RateLimitError and AuthorizationError

**Files:**
- Create: `lib/legion/extensions/github/errors.rb`
- Create: `spec/legion/extensions/github/errors_spec.rb`
- Modify: `lib/legion/extensions/github.rb` (add require)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/errors_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::RateLimitError do
  it 'stores reset_at timestamp' do
    reset_at = Time.now + 300
    error = described_class.new('rate limited', reset_at: reset_at)
    expect(error.reset_at).to eq(reset_at)
    expect(error.message).to eq('rate limited')
  end

  it 'stores credential_fingerprint' do
    error = described_class.new('rate limited', reset_at: Time.now, credential_fingerprint: 'fp1')
    expect(error.credential_fingerprint).to eq('fp1')
  end
end

RSpec.describe Legion::Extensions::Github::AuthorizationError do
  it 'stores owner and repo context' do
    error = described_class.new('no credential for OrgZ/repo1', owner: 'OrgZ', repo: 'repo1')
    expect(error.owner).to eq('OrgZ')
    expect(error.repo).to eq('repo1')
    expect(error.message).to eq('no credential for OrgZ/repo1')
  end

  it 'stores attempted_sources list' do
    error = described_class.new('exhausted', owner: 'OrgZ',
                                             attempted_sources: %i[oauth_user app_installation pat])
    expect(error.attempted_sources).to eq(%i[oauth_user app_installation pat])
  end
end

RSpec.describe Legion::Extensions::Github::ScopeDeniedError do
  it 'stores credential and scope context' do
    error = described_class.new('forbidden', owner: 'OrgZ', repo: 'repo1',
                                             credential_fingerprint: 'fp1', auth_type: :oauth_user)
    expect(error.owner).to eq('OrgZ')
    expect(error.credential_fingerprint).to eq('fp1')
    expect(error.auth_type).to eq(:oauth_user)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/errors_spec.rb`
Expected: FAIL — file does not exist

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/errors.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      class Error < StandardError; end

      class RateLimitError < Error
        attr_reader :reset_at, :credential_fingerprint

        def initialize(message = 'GitHub API rate limit exceeded', reset_at: nil, credential_fingerprint: nil)
          @reset_at = reset_at
          @credential_fingerprint = credential_fingerprint
          super(message)
        end
      end

      class AuthorizationError < Error
        attr_reader :owner, :repo, :attempted_sources

        def initialize(message = 'No authorized credential available', owner: nil, repo: nil, attempted_sources: [])
          @owner = owner
          @repo = repo
          @attempted_sources = attempted_sources
          super(message)
        end
      end

      class ScopeDeniedError < Error
        attr_reader :owner, :repo, :credential_fingerprint, :auth_type

        def initialize(message = 'Credential not authorized for this scope',
                       owner: nil, repo: nil, credential_fingerprint: nil, auth_type: nil)
          @owner = owner
          @repo = repo
          @credential_fingerprint = credential_fingerprint
          @auth_type = auth_type
          super(message)
        end
      end
    end
  end
end
```

**Step 4: Add require to entry point**

In `lib/legion/extensions/github.rb`, add near the top (before runners):

```ruby
require 'legion/extensions/github/errors'
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/errors_spec.rb`
Expected: All 5 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
bundle exec rubocop -A
bundle exec rubocop
git add lib/legion/extensions/github/errors.rb \
        spec/legion/extensions/github/errors_spec.rb \
        lib/legion/extensions/github.rb
git commit -m "add RateLimitError, AuthorizationError, and ScopeDeniedError classes"
```

---

### Task 32: Retry-on-fallback middleware for 403/429

When a request fails with 403 (scope denied) or 429 (rate limited), the middleware should mark the current credential, re-resolve starting from the next source, and replay the request — transparent to the caller.

**Files:**
- Create: `lib/legion/extensions/github/middleware/credential_fallback.rb`
- Create: `spec/legion/extensions/github/middleware/credential_fallback_spec.rb`
- Modify: `lib/legion/extensions/github/helpers/client.rb` (plug into connection, expose retry context)
- Modify: `lib/legion/extensions/github.rb` (add require)

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/middleware/credential_fallback_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Middleware::CredentialFallback do
  let(:resolver) { double('resolver') }
  let(:call_count) { { count: 0 } }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn) do
    counter = call_count
    s = stubs
    Faraday.new(url: 'https://api.github.com') do |f|
      f.use described_class, resolver: resolver
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter :test, s
    end
  end

  describe '403 with fallback enabled' do
    it 'retries with next credential' do
      attempt = 0
      stubs.get('/repos/OrgZ/repo1') do
        attempt += 1
        if attempt == 1
          [403, { 'Content-Type' => 'application/json' },
           { 'message' => 'Resource not accessible by integration' }]
        else
          [200, { 'Content-Type' => 'application/json' }, { 'name' => 'repo1' }]
        end
      end

      allow(resolver).to receive(:credential_fallback?).and_return(true)
      allow(resolver).to receive(:on_scope_denied)
      allow(resolver).to receive(:resolve_next_credential)
        .and_return({ token: 'ghp_fallback', auth_type: :app_installation,
                      metadata: { credential_fingerprint: 'fp2' } })
      allow(resolver).to receive(:max_fallback_retries).and_return(3)

      response = conn.get('/repos/OrgZ/repo1')
      expect(response.status).to eq(200)
      expect(response.body['name']).to eq('repo1')
    end
  end

  describe '429 with fallback enabled' do
    it 'retries with next credential' do
      attempt = 0
      stubs.get('/repos/OrgZ/repo1') do
        attempt += 1
        if attempt == 1
          [429, { 'Content-Type' => 'application/json',
                  'X-RateLimit-Remaining' => '0',
                  'X-RateLimit-Reset' => (Time.now.to_i + 300).to_s },
           { 'message' => 'API rate limit exceeded' }]
        else
          [200, { 'Content-Type' => 'application/json' }, { 'name' => 'repo1' }]
        end
      end

      allow(resolver).to receive(:credential_fallback?).and_return(true)
      allow(resolver).to receive(:on_rate_limit)
      allow(resolver).to receive(:resolve_next_credential)
        .and_return({ token: 'ghp_next', auth_type: :pat,
                      metadata: { credential_fingerprint: 'fp3' } })
      allow(resolver).to receive(:max_fallback_retries).and_return(3)

      response = conn.get('/repos/OrgZ/repo1')
      expect(response.status).to eq(200)
    end
  end

  describe '403 with fallback disabled' do
    it 'returns 403 without retry' do
      stubs.get('/repos/OrgZ/repo1') do
        [403, { 'Content-Type' => 'application/json' },
         { 'message' => 'Resource not accessible by integration' }]
      end

      allow(resolver).to receive(:credential_fallback?).and_return(false)

      response = conn.get('/repos/OrgZ/repo1')
      expect(response.status).to eq(403)
    end
  end

  describe 'exhaustion' do
    it 'returns last error when all credentials exhausted' do
      stubs.get('/repos/OrgZ/repo1') do
        [403, { 'Content-Type' => 'application/json' },
         { 'message' => 'Resource not accessible by integration' }]
      end

      allow(resolver).to receive(:credential_fallback?).and_return(true)
      allow(resolver).to receive(:on_scope_denied)
      allow(resolver).to receive(:resolve_next_credential).and_return(nil)
      allow(resolver).to receive(:max_fallback_retries).and_return(3)

      response = conn.get('/repos/OrgZ/repo1')
      expect(response.status).to eq(403)
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/middleware/credential_fallback_spec.rb`
Expected: FAIL — file does not exist

**Step 3: Write the implementation**

Create `lib/legion/extensions/github/middleware/credential_fallback.rb`:

```ruby
# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module Middleware
        class CredentialFallback < Faraday::Middleware
          RETRYABLE_STATUSES = [403, 429].freeze

          def initialize(app, resolver: nil)
            super(app)
            @resolver = resolver
          end

          def call(env)
            response = @app.call(env)
            return response unless should_retry?(response)

            retries = 0
            max = @resolver&.respond_to?(:max_fallback_retries) ? @resolver.max_fallback_retries : 3

            while retries < max && should_retry?(response)
              notify_resolver(response)

              next_credential = @resolver&.resolve_next_credential
              break unless next_credential

              env[:request_headers]['Authorization'] = "Bearer #{next_credential[:token]}"
              env[:body] = env[:request_body] if env[:request_body]

              response = @app.call(env)
              retries += 1
            end

            response
          end

          private

          def should_retry?(response)
            return false unless @resolver&.respond_to?(:credential_fallback?)
            return false unless @resolver.credential_fallback?

            RETRYABLE_STATUSES.include?(response.status)
          end

          def notify_resolver(response)
            if response.status == 429 && @resolver&.respond_to?(:on_rate_limit)
              reset = response.headers['x-ratelimit-reset']
              reset_at = reset ? Time.at(reset.to_i) : Time.now + 60
              @resolver.on_rate_limit(remaining: 0, reset_at: reset_at,
                                      status: 429, url: response.env.url.to_s)
            elsif response.status == 403 && @resolver&.respond_to?(:on_scope_denied)
              @resolver.on_scope_denied(status: 403, url: response.env.url.to_s,
                                        path: response.env.url.path)
            end
          end
        end
      end
    end
  end
end

Faraday::Middleware.register_middleware(
  github_credential_fallback: Legion::Extensions::Github::Middleware::CredentialFallback
)
```

**Step 4: Wire into Helpers::Client**

In `lib/legion/extensions/github/helpers/client.rb`, update the `connection` method. The CredentialFallback middleware goes at the **request** level (wraps the full call), before the response middleware:

```ruby
def connection(owner: nil, repo: nil, api_url: 'https://api.github.com', token: nil, **_opts)
  resolved = token ? { token: token } : resolve_credential(owner: owner, repo: repo)
  resolved_token = resolved&.dig(:token)
  @current_credential = resolved
  @skipped_fingerprints = []

  Faraday.new(url: api_url) do |conn|
    conn.use :github_credential_fallback, resolver: self
    conn.request :json
    conn.response :json, content_type: /\bjson$/
    conn.response :github_rate_limit, handler: self
    conn.response :github_scope_probe, handler: self
    conn.headers['Accept'] = 'application/vnd.github+json'
    conn.headers['Authorization'] = "Bearer #{resolved_token}" if resolved_token
    conn.headers['X-GitHub-Api-Version'] = '2022-11-28'
  end
end

def resolve_next_credential
  fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
  @skipped_fingerprints << fingerprint if fingerprint

  CREDENTIAL_RESOLVERS.each do |method|
    next unless respond_to?(method, true)

    result = send(method)
    next unless result

    fp = result.dig(:metadata, :credential_fingerprint)
    next if fp && @skipped_fingerprints.include?(fp)
    next if fp && rate_limited?(fingerprint: fp)

    @current_credential = result
    return result
  end
  nil
end

def max_fallback_retries
  CREDENTIAL_RESOLVERS.size
end
```

**Step 5: Add require to entry point**

In `lib/legion/extensions/github.rb`, add with other middleware requires:

```ruby
require 'legion/extensions/github/middleware/credential_fallback'
```

**Step 6: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/middleware/credential_fallback_spec.rb`
Expected: All 4 examples pass

**Step 7: Full suite + commit**

```bash
bundle exec rspec
bundle exec rubocop -A
bundle exec rubocop
git add lib/legion/extensions/github/middleware/credential_fallback.rb \
        spec/legion/extensions/github/middleware/credential_fallback_spec.rb \
        lib/legion/extensions/github/helpers/client.rb \
        lib/legion/extensions/github.rb
git commit -m "add CredentialFallback middleware for transparent 403/429 retry with next credential"
```

---

### Task 33: Forward owner:/repo: to connection() in existing runners

Existing runner methods like `get_repo(owner:, repo:, **)` consume `owner:` and `repo:` in the method signature, so the `**` splat does NOT pass them to `connection()`. This means scope-aware credential resolution never receives the owner/repo context. Fix: explicitly forward `owner:` and `repo:` to `connection()` in every runner method that has them.

**Files:**
- Modify: `lib/legion/extensions/github/runners/repositories.rb`
- Modify: `lib/legion/extensions/github/runners/issues.rb`
- Modify: `lib/legion/extensions/github/runners/pull_requests.rb`
- Modify: `lib/legion/extensions/github/runners/labels.rb`
- Modify: `lib/legion/extensions/github/runners/comments.rb`
- Modify: `lib/legion/extensions/github/runners/commits.rb`
- Modify: `lib/legion/extensions/github/runners/branches.rb`
- Modify: `lib/legion/extensions/github/runners/contents.rb`
- Modify: `lib/legion/extensions/github/runners/repository_webhooks.rb` (Task 30)

**Step 1: Write a failing test that proves owner: is not reaching connection()**

Add to `spec/legion/extensions/github/runners/repositories_spec.rb`:

```ruby
describe 'scope-aware connection' do
  it 'forwards owner and repo to connection for credential resolution' do
    expect(client).to receive(:connection)
      .with(hash_including(owner: 'LegionIO', repo: 'lex-github'))
      .and_return(test_connection)
    stubs.get('/repos/LegionIO/lex-github') do
      [200, { 'Content-Type' => 'application/json' }, { 'name' => 'lex-github' }]
    end
    client.get_repo(owner: 'LegionIO', repo: 'lex-github')
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/legion/extensions/github/runners/repositories_spec.rb`
Expected: FAIL — `connection` receives `{}` (empty kwargs), not `{owner: 'LegionIO', repo: 'lex-github'}`

**Step 3: Update all runner methods**

The pattern change for every method that has `owner:` and `repo:`:

Before:
```ruby
def get_repo(owner:, repo:, **)
  response = connection(**).get("/repos/#{owner}/#{repo}")
```

After:
```ruby
def get_repo(owner:, repo:, **)
  response = connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}")
```

For methods that only have `owner:` (rare, but check):
```ruby
def some_method(owner:, **)
  response = connection(owner: owner, **).get("/orgs/#{owner}/repos")
```

Apply this change to every method in these runners:

**`runners/repositories.rb`** — `get_repo`, `update_repo`, `delete_repo`, `list_branches`, `list_tags` (5 methods; `list_repos` uses `username:` not `owner:`, `create_repo` uses `/user/repos` — skip both)

**`runners/issues.rb`** — `list_issues`, `get_issue`, `create_issue`, `update_issue`, `list_issue_comments`, `create_issue_comment` (6 methods)

**`runners/pull_requests.rb`** — all methods (list, get, create, update, merge, list_commits, list_files, list_reviews — 8 methods)

**`runners/labels.rb`** — all methods (list, get, create, update, delete, add_to_issue, remove_from_issue — 7 methods)

**`runners/comments.rb`** — all methods that have `owner:, repo:` in signature

**`runners/commits.rb`** — all methods that have `owner:, repo:` in signature

**`runners/branches.rb`** — `create_branch` (1 method)

**`runners/contents.rb`** — all methods that have `owner:, repo:` in signature

**`runners/repository_webhooks.rb`** — all 8 methods (Task 30)

**Step 4: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass — existing tests stub `connection` and return a test Faraday instance, so they're unaffected by the new kwargs

**Step 5: Rubocop + commit**

```bash
bundle exec rubocop -A
bundle exec rubocop
git add lib/legion/extensions/github/runners/repositories.rb \
        lib/legion/extensions/github/runners/issues.rb \
        lib/legion/extensions/github/runners/pull_requests.rb \
        lib/legion/extensions/github/runners/labels.rb \
        lib/legion/extensions/github/runners/comments.rb \
        lib/legion/extensions/github/runners/commits.rb \
        lib/legion/extensions/github/runners/branches.rb \
        lib/legion/extensions/github/runners/contents.rb \
        lib/legion/extensions/github/runners/repository_webhooks.rb \
        spec/legion/extensions/github/runners/repositories_spec.rb
git commit -m "forward owner: and repo: to connection() in all runners for scope-aware resolution"
```

---

### Task 34: Webhook-driven scope invalidation

When a webhook event arrives for `installation.created`, `installation.deleted`, `installation_repositories.added`, or `installation_repositories.removed`, invalidate the relevant scope registry entries so the next credential resolution re-probes.

**Files:**
- Modify: `lib/legion/extensions/github/app/runners/webhooks.rb`
- Create: `spec/legion/extensions/github/app/runners/webhooks_scope_invalidation_spec.rb`

**Step 1: Write the failing tests**

Create `spec/legion/extensions/github/app/runners/webhooks_scope_invalidation_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe 'Webhook scope invalidation' do
  let(:runner) { Object.new.extend(Legion::Extensions::Github::App::Runners::Webhooks) }

  before do
    allow(runner).to receive(:cache_connected?).and_return(true)
    allow(runner).to receive(:local_cache_connected?).and_return(true)
    allow(runner).to receive(:cache_delete)
    allow(runner).to receive(:local_cache_delete)
  end

  describe '#invalidate_scopes_for_event' do
    it 'invalidates org scope on installation.created' do
      payload = {
        'action' => 'created',
        'installation' => {
          'id' => 12345,
          'account' => { 'login' => 'OrgZ', 'type' => 'Organization' }
        }
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation', payload: payload)
    end

    it 'invalidates org scope on installation.deleted' do
      payload = {
        'action' => 'deleted',
        'installation' => {
          'id' => 12345,
          'account' => { 'login' => 'OrgZ', 'type' => 'Organization' }
        }
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation', payload: payload)
    end

    it 'invalidates repo scopes on installation_repositories.added' do
      payload = {
        'action' => 'added',
        'installation' => {
          'id' => 12345,
          'account' => { 'login' => 'OrgZ' }
        },
        'repositories_added' => [
          { 'full_name' => 'OrgZ/repo1' },
          { 'full_name' => 'OrgZ/repo2' }
        ]
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation_repositories', payload: payload)
    end

    it 'invalidates repo scopes on installation_repositories.removed' do
      payload = {
        'action' => 'removed',
        'installation' => {
          'id' => 12345,
          'account' => { 'login' => 'OrgZ' }
        },
        'repositories_removed' => [
          { 'full_name' => 'OrgZ/repo1' }
        ]
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation_repositories', payload: payload)
    end

    it 'does nothing for unrelated events' do
      expect(runner).not_to receive(:invalidate_all_scopes_for_owner)
      runner.invalidate_scopes_for_event(event_type: 'push', payload: { 'ref' => 'refs/heads/main' })
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/webhooks_scope_invalidation_spec.rb`
Expected: FAIL — method does not exist

**Step 3: Add invalidation methods to App::Runners::Webhooks**

In `lib/legion/extensions/github/app/runners/webhooks.rb`, add:

```ruby
SCOPE_INVALIDATION_EVENTS = %w[installation installation_repositories].freeze

def invalidate_scopes_for_event(event_type:, payload:, **)
  return unless SCOPE_INVALIDATION_EVENTS.include?(event_type)

  owner = payload.dig('installation', 'account', 'login')
  return unless owner

  invalidate_all_scopes_for_owner(owner: owner)
end

def invalidate_all_scopes_for_owner(owner:)
  # Wipe all scope entries matching this owner across all fingerprints.
  # Since we use key-per-fingerprint-per-owner, we need to iterate known fingerprints
  # or use a wildcard pattern. Use a cache scan if available, otherwise invalidate
  # for all CREDENTIAL_RESOLVERS fingerprints.
  known_fingerprints = resolve_known_fingerprints
  known_fingerprints.each do |fp|
    invalidate_scope(fingerprint: fp, owner: owner)
  end
end

private

def resolve_known_fingerprints
  # Collect fingerprints from all currently-resolvable credential sources
  fingerprints = []
  Legion::Extensions::Github::Helpers::Client::CREDENTIAL_RESOLVERS.each do |method|
    next unless respond_to?(method, true)

    result = send(method)
    next unless result

    fp = result.dig(:metadata, :credential_fingerprint)
    fingerprints << fp if fp
  end
  fingerprints.uniq
rescue StandardError
  []
end
```

**Step 4: Wire into receive_event**

In the existing `receive_event` method (from Task 3), add after signature verification and event parsing:

```ruby
invalidate_scopes_for_event(event_type: event_type, payload: payload)
```

**Step 5: Run tests**

Run: `bundle exec rspec spec/legion/extensions/github/app/runners/webhooks_scope_invalidation_spec.rb`
Expected: All 5 examples pass

**Step 6: Full suite + commit**

```bash
bundle exec rspec
bundle exec rubocop -A
bundle exec rubocop
git add lib/legion/extensions/github/app/runners/webhooks.rb \
        spec/legion/extensions/github/app/runners/webhooks_scope_invalidation_spec.rb
git commit -m "add webhook-driven scope invalidation for installation and repository events"
```

---

### Task 35: CHANGELOG and README updates

**Files:**
- Create or modify: `CHANGELOG.md`
- Modify: `README.md`

**Step 1: Create CHANGELOG.md**

If `CHANGELOG.md` does not exist, create it. If it exists, update it.

```markdown
# Changelog

## [Unreleased]

### Added
- GitHub App authentication (JWT generation, installation tokens, manifest flow)
- OAuth delegated authentication (Authorization Code + PKCE, device code fallback)
- Scope-aware credential resolution chain (8 sources, rate limit + scope fallback)
- ScopeRegistry for caching credential-to-owner/repo authorization status
- CredentialFallback Faraday middleware (transparent 403/429 retry with next credential)
- RateLimit Faraday middleware with automatic credential exhaustion tracking
- ScopeProbe Faraday middleware for passive scope learning from API responses
- Helpers::Cache for two-tier API response caching (global Redis + local in-memory)
- Helpers::TokenCache for token lifecycle management
- App::Runners::Auth (JWT generation, installation token exchange)
- App::Runners::Webhooks (signature verification, event parsing, scope invalidation)
- App::Runners::Manifest (GitHub App manifest flow)
- App::Runners::Installations (list, get, suspend, unsuspend, delete)
- App::Runners::CredentialStore (Vault persistence after manifest flow)
- OAuth::Runners::Auth (authorize_url, exchange_code, refresh, device_code, revoke)
- Runners::Actions (GitHub Actions workflow management)
- Runners::Checks (check runs and check suites)
- Runners::Releases (release and asset management)
- Runners::Deployments (deployment and status management)
- Runners::RepositoryWebhooks (programmatic webhook management)
- CallbackServer for standalone OAuth redirect handling
- BrowserAuth for browser-based OAuth with PKCE
- CLI::Auth for `legion lex exec github auth login/status`
- CLI::App for `legion lex exec github app setup`
- RateLimitError, AuthorizationError, ScopeDeniedError error classes
- `jwt` (~> 2.7) and `base64` (>= 0.1) runtime dependencies

### Changed
- Helpers::Client now uses scope-aware credential resolution (`owner:`, `repo:` context)
- All existing runners forward `owner:` and `repo:` to `connection()` for scope-aware resolution
- `credential_fallback` setting (default: true) replaces `rate_limit_fallback`
- Client class includes App and OAuth runner modules
- Version bump to 0.3.0
```

**Step 2: Update README.md**

Add sections for:
- GitHub App authentication setup (app_id, private_key_path, installation_id)
- OAuth delegated setup (client_id, CLI login flow)
- Credential resolution chain (priority order, scope-aware fallback)
- New runners (Actions, Checks, Releases, Deployments, RepositoryWebhooks)
- Caching configuration (TTLs)
- Error handling (RateLimitError, AuthorizationError)

**Step 3: Commit**

```bash
git add CHANGELOG.md README.md
git commit -m "add CHANGELOG.md and update README.md for v0.3.0"
```
