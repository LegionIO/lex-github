# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Issues do
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

  describe '#list_issues' do
    it 'returns issues for a repo' do
      stubs.get('/repos/octocat/Hello-World/issues') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'title' => 'Bug report' }]]
      end
      result = client.list_issues(owner: 'octocat', repo: 'Hello-World')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['title']).to eq('Bug report')
    end
  end

  describe '#get_issue' do
    it 'returns a single issue' do
      stubs.get('/repos/octocat/Hello-World/issues/1') do
        [200, { 'Content-Type' => 'application/json' }, { 'number' => 1, 'title' => 'Bug' }]
      end
      result = client.get_issue(owner: 'octocat', repo: 'Hello-World', issue_number: 1)
      expect(result[:result]['number']).to eq(1)
    end
  end

  describe '#create_issue' do
    it 'creates a new issue' do
      stubs.post('/repos/octocat/Hello-World/issues') do
        [201, { 'Content-Type' => 'application/json' }, { 'title' => 'New issue' }]
      end
      result = client.create_issue(owner: 'octocat', repo: 'Hello-World', title: 'New issue')
      expect(result[:result]['title']).to eq('New issue')
    end
  end

  describe '#create_issue_comment' do
    it 'creates a comment on an issue' do
      stubs.post('/repos/octocat/Hello-World/issues/1/comments') do
        [201, { 'Content-Type' => 'application/json' }, { 'body' => 'Great!' }]
      end
      result = client.create_issue_comment(owner: 'octocat', repo: 'Hello-World', issue_number: 1, body: 'Great!')
      expect(result[:result]['body']).to eq('Great!')
    end
  end
end
