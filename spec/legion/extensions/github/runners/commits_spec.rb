# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Commits do
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

  describe '#list_commits' do
    it 'returns commits for a repo' do
      stubs.get('/repos/octocat/Hello-World/commits') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'sha' => 'abc123', 'commit' => { 'message' => 'initial commit' } }]]
      end
      result = client.list_commits(owner: 'octocat', repo: 'Hello-World')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['sha']).to eq('abc123')
    end
  end

  describe '#get_commit' do
    it 'returns a single commit' do
      stubs.get('/repos/octocat/Hello-World/commits/abc123') do
        [200, { 'Content-Type' => 'application/json' },
         { 'sha' => 'abc123', 'commit' => { 'message' => 'initial commit' } }]
      end
      result = client.get_commit(owner: 'octocat', repo: 'Hello-World', ref: 'abc123')
      expect(result[:result]['sha']).to eq('abc123')
    end
  end

  describe '#compare_commits' do
    it 'returns comparison between two refs' do
      stubs.get('/repos/octocat/Hello-World/compare/main...feature') do
        [200, { 'Content-Type' => 'application/json' },
         { 'status' => 'ahead', 'ahead_by' => 3,
           'commits' => [{ 'sha' => 'abc' }],
           'files' => [{ 'filename' => 'README.md' }] }]
      end
      result = client.compare_commits(owner: 'octocat', repo: 'Hello-World', base: 'main', head: 'feature')
      expect(result[:result]['status']).to eq('ahead')
      expect(result[:result]['ahead_by']).to eq(3)
      expect(result[:result]['files'].first['filename']).to eq('README.md')
    end
  end
end
