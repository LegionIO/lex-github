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
        client_id:             'Iv1.abc',
        redirect_uri:          'http://localhost:12345/callback',
        scope:                 'repo admin:org',
        state:                 'random-state',
        code_challenge:        'challenge123',
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
           'token_type' => 'bearer', 'expires_in' => 28_800 }]
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
           'token_type' => 'bearer', 'expires_in' => 28_800 }]
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
         { access_token: 'ghu_device', token_type: 'bearer' }]
      end

      result = runner.poll_device_code(
        client_id: 'Iv1.abc', device_code: 'dc_123',
        interval: 0, timeout: 5
      )
      expect(result[:result][:access_token]).to eq('ghu_device')
    end

    it 'returns timeout error when deadline exceeded' do
      stubs.post('/login/oauth/access_token') do
        [200, { 'Content-Type' => 'application/json' },
         { error: 'authorization_pending' }]
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
