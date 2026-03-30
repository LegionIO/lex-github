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
