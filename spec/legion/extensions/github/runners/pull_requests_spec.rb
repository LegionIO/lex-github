# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::PullRequests do
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

  describe '#list_pull_requests' do
    it 'returns pull requests for a repo' do
      stubs.get('/repos/octocat/Hello-World/pulls') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'title' => 'Fix typo' }]]
      end
      result = client.list_pull_requests(owner: 'octocat', repo: 'Hello-World')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['title']).to eq('Fix typo')
    end
  end

  describe '#get_pull_request' do
    it 'returns a single pull request' do
      stubs.get('/repos/octocat/Hello-World/pulls/42') do
        [200, { 'Content-Type' => 'application/json' }, { 'number' => 42, 'title' => 'Fix' }]
      end
      result = client.get_pull_request(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result]['number']).to eq(42)
    end
  end

  describe '#create_pull_request' do
    it 'creates a new pull request' do
      stubs.post('/repos/octocat/Hello-World/pulls') do
        [201, { 'Content-Type' => 'application/json' }, { 'title' => 'New feature' }]
      end
      result = client.create_pull_request(owner: 'octocat', repo: 'Hello-World', title: 'New feature', head: 'feature', base: 'main')
      expect(result[:result]['title']).to eq('New feature')
    end
  end

  describe '#merge_pull_request' do
    it 'merges a pull request' do
      stubs.put('/repos/octocat/Hello-World/pulls/42/merge') do
        [200, { 'Content-Type' => 'application/json' }, { 'merged' => true }]
      end
      result = client.merge_pull_request(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result]['merged']).to be true
    end
  end

  describe '#update_pull_request' do
    it 'updates a pull request' do
      stubs.patch('/repos/octocat/Hello-World/pulls/42') do
        [200, { 'Content-Type' => 'application/json' }, { 'title' => 'Updated title' }]
      end
      result = client.update_pull_request(owner: 'octocat', repo: 'Hello-World', pull_number: 42, title: 'Updated title')
      expect(result[:result]['title']).to eq('Updated title')
    end
  end

  describe '#list_pull_request_files' do
    it 'returns files changed in a pull request' do
      stubs.get('/repos/octocat/Hello-World/pulls/42/files') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'filename' => 'README.md' }]]
      end
      result = client.list_pull_request_files(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['filename']).to eq('README.md')
    end
  end

  describe '#list_pull_request_reviews' do
    it 'returns reviews for a pull request' do
      stubs.get('/repos/octocat/Hello-World/pulls/42/reviews') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'state' => 'APPROVED' }]]
      end
      result = client.list_pull_request_reviews(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['state']).to eq('APPROVED')
    end
  end
end
