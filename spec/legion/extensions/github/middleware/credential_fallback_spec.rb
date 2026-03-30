# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Middleware::CredentialFallback do
  let(:resolver) { double('resolver') }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:conn) do
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
          [429, { 'Content-Type'          => 'application/json',
                  'X-RateLimit-Remaining' => '0',
                  'X-RateLimit-Reset'     => (Time.now.to_i + 300).to_s },
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
