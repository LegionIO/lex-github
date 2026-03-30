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
