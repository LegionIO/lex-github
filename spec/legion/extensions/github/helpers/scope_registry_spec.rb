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
