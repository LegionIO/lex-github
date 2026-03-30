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
    it 'stores delegated token at user-scoped path and canonical delegated path' do
      expect(runner).to receive(:vault_set).with(
        'github/oauth/matt/token',
        hash_including('access_token' => 'ghu_test', 'refresh_token' => 'ghr_test')
      )
      expect(runner).to receive(:vault_set).with(
        'github/oauth/delegated/token',
        hash_including('access_token' => 'ghu_test', 'refresh_token' => 'ghr_test')
      )
      runner.store_oauth_token(
        user: 'matt', access_token: 'ghu_test',
        refresh_token: 'ghr_test', expires_in: 28_800
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
