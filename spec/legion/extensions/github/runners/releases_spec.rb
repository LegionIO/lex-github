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
