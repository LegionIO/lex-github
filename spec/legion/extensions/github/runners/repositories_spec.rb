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

  describe '#get_tree' do
    before do
      stubs.get('/repos/octocat/Hello-World/git/trees/main') do
        [200, { 'Content-Type' => 'application/json' },
         { 'sha' => 'abc123', 'tree' => [
           { 'path' => 'lib/main.rb', 'type' => 'blob', 'sha' => 'aaa' },
           { 'path' => 'spec', 'type' => 'tree', 'sha' => 'bbb' }
         ], 'truncated' => false }]
      end
    end

    it 'returns the tree for a given sha/ref' do
      result = client.get_tree(owner: 'octocat', repo: 'Hello-World', tree_sha: 'main')
      expect(result[:result]['tree']).to be_an(Array)
      expect(result[:result]['tree'].first['path']).to eq('lib/main.rb')
    end

    it 'wraps the response under :result' do
      result = client.get_tree(owner: 'octocat', repo: 'Hello-World', tree_sha: 'main')
      expect(result).to have_key(:result)
    end
  end

  describe 'scope-aware connection' do
    it 'forwards owner and repo to connection for credential resolution' do
      expect(client).to receive(:connection)
        .with(hash_including(owner: 'LegionIO', repo: 'lex-github'))
        .and_return(test_connection)
      stubs.get('/repos/LegionIO/lex-github') do
        [200, { 'Content-Type' => 'application/json' }, { 'name' => 'lex-github' }]
      end
      client.get_repo(owner: 'LegionIO', repo: 'lex-github')
    end
  end
end
