# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Repositories do
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

  describe '#list_repos' do
    it 'returns repositories for a user' do
      stubs.get('/users/octocat/repos') { [200, { 'Content-Type' => 'application/json' }, [{ 'name' => 'Hello-World' }]] }
      result = client.list_repos(username: 'octocat')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['name']).to eq('Hello-World')
    end
  end

  describe '#get_repo' do
    it 'returns a single repository' do
      stubs.get('/repos/octocat/Hello-World') { [200, { 'Content-Type' => 'application/json' }, { 'full_name' => 'octocat/Hello-World' }] }
      result = client.get_repo(owner: 'octocat', repo: 'Hello-World')
      expect(result[:result]['full_name']).to eq('octocat/Hello-World')
    end
  end

  describe '#create_repo' do
    it 'creates a new repository' do
      stubs.post('/user/repos') { [201, { 'Content-Type' => 'application/json' }, { 'name' => 'new-repo' }] }
      result = client.create_repo(name: 'new-repo')
      expect(result[:result]['name']).to eq('new-repo')
    end
  end

  describe '#delete_repo' do
    it 'deletes a repository' do
      stubs.delete('/repos/octocat/Hello-World') { [204, {}, ''] }
      result = client.delete_repo(owner: 'octocat', repo: 'Hello-World')
      expect(result[:result]).to be true
    end
  end

  describe '#list_branches' do
    it 'returns branches for a repo' do
      stubs.get('/repos/octocat/Hello-World/branches') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'name' => 'main' }]]
      end
      result = client.list_branches(owner: 'octocat', repo: 'Hello-World')
      expect(result[:result].first['name']).to eq('main')
    end
  end
end
