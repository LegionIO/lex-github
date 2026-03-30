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
