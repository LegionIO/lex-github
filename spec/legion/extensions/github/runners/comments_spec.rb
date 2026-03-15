# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Comments do
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

  describe '#list_comments' do
    it 'returns comments for an issue' do
      stubs.get('/repos/octocat/Hello-World/issues/1/comments') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'body' => 'Great work!' }]]
      end
      result = client.list_comments(owner: 'octocat', repo: 'Hello-World', issue_number: 1)
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['body']).to eq('Great work!')
    end
  end

  describe '#get_comment' do
    it 'returns a single comment by id' do
      stubs.get('/repos/octocat/Hello-World/issues/comments/42') do
        [200, { 'Content-Type' => 'application/json' }, { 'id' => 42, 'body' => 'Nice!' }]
      end
      result = client.get_comment(owner: 'octocat', repo: 'Hello-World', comment_id: 42)
      expect(result[:result]['id']).to eq(42)
      expect(result[:result]['body']).to eq('Nice!')
    end
  end

  describe '#create_comment' do
    it 'creates a comment on an issue' do
      stubs.post('/repos/octocat/Hello-World/issues/1/comments') do
        [201, { 'Content-Type' => 'application/json' }, { 'id' => 99, 'body' => 'Hello!' }]
      end
      result = client.create_comment(owner: 'octocat', repo: 'Hello-World', issue_number: 1, body: 'Hello!')
      expect(result[:result]['body']).to eq('Hello!')
    end
  end

  describe '#update_comment' do
    it 'updates an existing comment' do
      stubs.patch('/repos/octocat/Hello-World/issues/comments/42') do
        [200, { 'Content-Type' => 'application/json' }, { 'id' => 42, 'body' => 'Updated text' }]
      end
      result = client.update_comment(owner: 'octocat', repo: 'Hello-World', comment_id: 42, body: 'Updated text')
      expect(result[:result]['body']).to eq('Updated text')
    end
  end

  describe '#delete_comment' do
    it 'deletes a comment and returns true' do
      stubs.delete('/repos/octocat/Hello-World/issues/comments/42') { [204, {}, ''] }
      result = client.delete_comment(owner: 'octocat', repo: 'Hello-World', comment_id: 42)
      expect(result[:result]).to be true
    end
  end
end
