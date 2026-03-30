# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Deployments do
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

  describe '#list_deployments' do
    it 'returns deployments for a repo' do
      stubs.get('/repos/LegionIO/lex-github/deployments') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 1, 'ref' => 'main', 'environment' => 'production' }]]
      end
      result = client.list_deployments(owner: 'LegionIO', repo: 'lex-github')
      expect(result[:result].first['environment']).to eq('production')
    end
  end

  describe '#get_deployment' do
    it 'returns a single deployment' do
      stubs.get('/repos/LegionIO/lex-github/deployments/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'ref' => 'main', 'environment' => 'production' }]
      end
      result = client.get_deployment(owner: 'LegionIO', repo: 'lex-github', deployment_id: 1)
      expect(result[:result]['ref']).to eq('main')
    end
  end

  describe '#create_deployment' do
    it 'creates a deployment' do
      stubs.post('/repos/LegionIO/lex-github/deployments') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 2, 'ref' => 'v0.3.0', 'environment' => 'staging' }]
      end
      result = client.create_deployment(owner: 'LegionIO', repo: 'lex-github',
                                        ref: 'v0.3.0', environment: 'staging')
      expect(result[:result]['environment']).to eq('staging')
    end
  end

  describe '#delete_deployment' do
    it 'deletes a deployment' do
      stubs.delete('/repos/LegionIO/lex-github/deployments/1') { [204, {}, ''] }
      result = client.delete_deployment(owner: 'LegionIO', repo: 'lex-github', deployment_id: 1)
      expect(result[:result]).to be true
    end
  end

  describe '#list_deployment_statuses' do
    it 'returns statuses for a deployment' do
      stubs.get('/repos/LegionIO/lex-github/deployments/1/statuses') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 10, 'state' => 'success', 'description' => 'Deployed' }]]
      end
      result = client.list_deployment_statuses(owner: 'LegionIO', repo: 'lex-github', deployment_id: 1)
      expect(result[:result].first['state']).to eq('success')
    end
  end

  describe '#create_deployment_status' do
    it 'creates a deployment status' do
      stubs.post('/repos/LegionIO/lex-github/deployments/1/statuses') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 11, 'state' => 'in_progress', 'description' => 'Deploying...' }]
      end
      result = client.create_deployment_status(owner: 'LegionIO', repo: 'lex-github',
                                               deployment_id: 1, state: 'in_progress',
                                               description: 'Deploying...')
      expect(result[:result]['state']).to eq('in_progress')
    end
  end

  describe '#get_deployment_status' do
    it 'returns a single deployment status' do
      stubs.get('/repos/LegionIO/lex-github/deployments/1/statuses/10') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 10, 'state' => 'success' }]
      end
      result = client.get_deployment_status(owner: 'LegionIO', repo: 'lex-github',
                                            deployment_id: 1, status_id: 10)
      expect(result[:result]['state']).to eq('success')
    end
  end
end
