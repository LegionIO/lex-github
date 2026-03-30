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
      allow(helper).to receive(:scope_status)
      result = helper.resolve_credential(owner: nil, repo: nil)
      expect(result[:auth_type]).to eq(:oauth_user)
      expect(helper).not_to have_received(:scope_status)
    end
  end

  describe '#resolve_gh_cli' do
    it 'returns token from gh auth token command' do
      allow(helper).to receive(:gh_cli_token_output).and_return('ghp_cli123')
      result = helper.resolve_gh_cli
      expect(result[:token]).to eq('ghp_cli123')
      expect(result[:auth_type]).to eq(:cli)
    end

    it 'returns nil when gh is not installed' do
      allow(helper).to receive(:gh_cli_token_output).and_return(nil)
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
