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
      allow(helper).to receive(:resolve_broker_app).and_return(nil)
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

  describe '#resolve_next_credential' do
    before do
      allow(helper).to receive(:resolve_vault_delegated).and_return(nil)
      allow(helper).to receive(:resolve_settings_delegated).and_return(nil)
      allow(helper).to receive(:resolve_broker_app).and_return(nil)
      allow(helper).to receive(:resolve_vault_app).and_return(nil)
      allow(helper).to receive(:resolve_settings_app).and_return(nil)
      allow(helper).to receive(:resolve_vault_pat).and_return(nil)
      allow(helper).to receive(:resolve_settings_pat).and_return(nil)
      allow(helper).to receive(:resolve_gh_cli).and_return(nil)
      allow(helper).to receive(:resolve_env).and_return(nil)
    end

    it 'returns nil when all resolvers are exhausted' do
      helper.instance_variable_set(:@current_credential, nil)
      helper.instance_variable_set(:@skipped_fingerprints, [])
      expect(helper.resolve_next_credential).to be_nil
    end

    it 'skips the current credential fingerprint' do
      delegated = { token: 'del', auth_type: :oauth_user,
                    metadata: { source: :vault, credential_fingerprint: 'fp_d' } }
      app = { token: 'app', auth_type: :app_installation,
              metadata: { source: :vault, credential_fingerprint: 'fp_a' } }
      helper.instance_variable_set(:@current_credential,
                                   { metadata: { credential_fingerprint: 'fp_d' } })
      helper.instance_variable_set(:@skipped_fingerprints, [])
      allow(helper).to receive(:resolve_vault_delegated).and_return(delegated)
      allow(helper).to receive(:resolve_vault_app).and_return(app)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status).and_return(:unknown)
      result = helper.resolve_next_credential
      expect(result[:auth_type]).to eq(:app_installation)
    end

    it 'skips scope-denied credentials for a given owner/repo' do
      delegated = { token: 'del', auth_type: :oauth_user,
                    metadata: { source: :vault, credential_fingerprint: 'fp_d' } }
      app = { token: 'app', auth_type: :app_installation,
              metadata: { source: :vault, credential_fingerprint: 'fp_a' } }
      helper.instance_variable_set(:@current_credential, nil)
      helper.instance_variable_set(:@skipped_fingerprints, [])
      allow(helper).to receive(:resolve_vault_delegated).and_return(delegated)
      allow(helper).to receive(:resolve_vault_app).and_return(app)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status)
        .with(fingerprint: 'fp_d', owner: 'OrgX', repo: 'repoY').and_return(:denied)
      allow(helper).to receive(:scope_status)
        .with(fingerprint: 'fp_a', owner: 'OrgX', repo: 'repoY').and_return(:unknown)
      result = helper.resolve_next_credential(owner: 'OrgX', repo: 'repoY')
      expect(result[:auth_type]).to eq(:app_installation)
    end
  end

  describe '#resolve_broker_app' do
    context 'when Broker is available with a github lease' do
      let(:lease) { double('Lease', metadata: { installation_id: '12345' }) }

      before do
        stub_const('Legion::Identity::Broker', double)
        allow(Legion::Identity::Broker).to receive(:token_for).with(:github).and_return('ghs_broker_token')
        allow(Legion::Identity::Broker).to receive(:lease_for).with(:github).and_return(lease)
      end

      it 'returns a credential hash with broker source' do
        result = helper.resolve_broker_app
        expect(result[:token]).to eq('ghs_broker_token')
        expect(result[:auth_type]).to eq(:app_installation)
        expect(result[:metadata][:source]).to eq(:broker)
        expect(result[:metadata][:credential_type]).to eq(:installation_token)
      end

      it 'includes a stable fingerprint derived from installation_id' do
        result = helper.resolve_broker_app
        expected_fp = Digest::SHA256.hexdigest('app_installation:broker_app_12345')[0, 16]
        expect(result[:metadata][:credential_fingerprint]).to eq(expected_fp)
      end
    end

    context 'when Broker returns nil token' do
      before do
        stub_const('Legion::Identity::Broker', double)
        allow(Legion::Identity::Broker).to receive(:token_for).with(:github).and_return(nil)
      end

      it 'returns nil' do
        expect(helper.resolve_broker_app).to be_nil
      end
    end

    context 'when Broker is not defined' do
      it 'returns nil' do
        expect(helper.resolve_broker_app).to be_nil
      end
    end

    context 'when lease has no installation_id' do
      let(:lease) { double('Lease', metadata: {}) }

      before do
        stub_const('Legion::Identity::Broker', double)
        allow(Legion::Identity::Broker).to receive(:token_for).with(:github).and_return('ghs_token')
        allow(Legion::Identity::Broker).to receive(:lease_for).with(:github).and_return(lease)
      end

      it 'uses unknown as installation_id in fingerprint' do
        result = helper.resolve_broker_app
        expected_fp = Digest::SHA256.hexdigest('app_installation:broker_app_unknown')[0, 16]
        expect(result[:metadata][:credential_fingerprint]).to eq(expected_fp)
      end
    end
  end

  describe '#resolve_credential with broker' do
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

    it 'prefers delegated over broker app token' do
      delegated = { token: 'delegated', auth_type: :oauth_user,
                    metadata: { source: :vault, credential_fingerprint: 'fp_d' } }
      broker = { token: 'broker', auth_type: :app_installation,
                 metadata: { source: :broker, credential_fingerprint: 'fp_b' } }
      allow(helper).to receive(:resolve_vault_delegated).and_return(delegated)
      allow(helper).to receive(:resolve_broker_app).and_return(broker)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status).and_return(:unknown)
      result = helper.resolve_credential
      expect(result[:auth_type]).to eq(:oauth_user)
    end

    it 'prefers broker app token over legacy vault app' do
      broker = { token: 'broker', auth_type: :app_installation,
                 metadata: { source: :broker, credential_fingerprint: 'fp_b' } }
      vault_app = { token: 'vault_app', auth_type: :app_installation,
                    metadata: { source: :vault, credential_fingerprint: 'fp_v' } }
      allow(helper).to receive(:resolve_broker_app).and_return(broker)
      allow(helper).to receive(:resolve_vault_app).and_return(vault_app)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status).and_return(:unknown)
      result = helper.resolve_credential
      expect(result[:auth_type]).to eq(:app_installation)
      expect(result[:metadata][:source]).to eq(:broker)
    end

    it 'falls back to legacy vault app when broker returns nil' do
      vault_app = { token: 'vault_app', auth_type: :app_installation,
                    metadata: { source: :vault, credential_fingerprint: 'fp_v' } }
      allow(helper).to receive(:resolve_broker_app).and_return(nil)
      allow(helper).to receive(:resolve_vault_app).and_return(vault_app)
      allow(helper).to receive(:rate_limited?).and_return(false)
      allow(helper).to receive(:scope_status).and_return(:unknown)
      result = helper.resolve_credential
      expect(result[:metadata][:source]).to eq(:vault)
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

  describe '#resolve_vault_app' do
    before do
      allow(helper).to receive(:vault_get).with('github/app/private_key').and_return('-----BEGIN RSA PRIVATE KEY-----...')
      allow(helper).to receive(:vault_get).with('github/app/app_id').and_return('12345')
      allow(helper).to receive(:vault_get).with('github/app/installation_id').and_return('67890')
      allow(helper).to receive(:fetch_token).and_return(nil)
      allow(helper).to receive(:store_token)
    end

    it 'generates a fresh installation token on cache miss' do
      stub_const('Legion::Crypt', double)
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

  describe '#resolve_env' do
    it 'returns GITHUB_TOKEN from environment' do
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return('ghp_env456')
      result = helper.resolve_env
      expect(result[:token]).to eq('ghp_env456')
      expect(result[:auth_type]).to eq(:env)
    end

    it 'returns nil when GITHUB_TOKEN is not set' do
      allow(ENV).to receive(:fetch).with('GITHUB_TOKEN', nil).and_return(nil)
      expect(helper.resolve_env).to be_nil
    end
  end
end
