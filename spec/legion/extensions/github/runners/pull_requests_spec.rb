# frozen_string_literal: true

require 'json'

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

  describe '#mark_pr_ready' do
    let(:graphql_stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:graphql_conn) do
      Faraday.new(url: 'https://api.github.com') do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, graphql_stubs
      end
    end

    before do
      stubs.get('/repos/octocat/Hello-World/pulls/42') do
        [200, { 'Content-Type' => 'application/json' },
         { 'number' => 42, 'node_id' => 'PR_abc123', 'draft' => true }]
      end
      conn = graphql_conn # force evaluation before mocking Faraday.new
      allow(Faraday).to receive(:new).with(url: 'https://api.github.com').and_return(conn)
      graphql_stubs.post('/graphql') do
        [200, { 'Content-Type' => 'application/json' },
         { 'data' => { 'markPullRequestAsReady' => {
           'pullRequest' => { 'id' => 'PR_abc123', 'isDraft' => false }
         } } }]
      end
    end

    it 'returns success: true when the mutation succeeds' do
      result = client.mark_pr_ready(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:success]).to be true
    end

    it 'returns the PR data from the mutation' do
      result = client.mark_pr_ready(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result]['isDraft']).to be false
    end
  end

  describe '#list_all_pull_request_files' do
    let(:page1) { (1..100).map { |i| { 'filename' => "file#{i}.rb" } } }
    let(:page2) { [{ 'filename' => 'file101.rb' }] }

    before do
      stubs.get('/repos/octocat/Hello-World/pulls/42/files') do |env|
        page = env.params['page'].to_i
        data = page == 1 ? page1 : page2
        [200, { 'Content-Type' => 'application/json' }, data]
      end
    end

    it 'fetches all pages until a page has fewer than per_page results' do
      result = client.list_all_pull_request_files(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result].size).to eq(101)
    end

    it 'handles a single page of results' do
      single_stubs = Faraday::Adapter::Test::Stubs.new
      single_conn = Faraday.new(url: 'https://api.github.com') do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, single_stubs
      end
      allow(client).to receive(:connection).and_return(single_conn)
      single_stubs.get('/repos/octocat/Hello-World/pulls/42/files') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'filename' => 'only.rb' }]]
      end
      result = client.list_all_pull_request_files(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result].size).to eq(1)
    end
  end

  describe '#list_pull_request_commits' do
    before do
      stubs.get('/repos/octocat/Hello-World/pulls/42/commits') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'sha' => 'abc123', 'commit' => { 'message' => 'Fix timeout' } },
          { 'sha' => 'def456', 'commit' => { 'message' => 'Add config param' } }]]
      end
    end

    it 'returns commits for a PR' do
      result = client.list_pull_request_commits(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result]).to be_an(Array)
      expect(result[:result].size).to eq(2)
    end

    it 'returns commit SHAs' do
      result = client.list_pull_request_commits(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      shas = result[:result].map { |c| c['sha'] }
      expect(shas).to eq(%w[abc123 def456])
    end
  end

  describe '#list_pull_request_review_comments' do
    before do
      stubs.get('/repos/octocat/Hello-World/pulls/42/comments') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 1, 'body' => 'Nit: rename this', 'path' => 'lib/foo.rb',
            'position' => 3, 'user' => { 'login' => 'reviewer' }, 'created_at' => '2026-04-01T00:00:00Z' }]]
      end
    end

    it 'returns review comments for a PR' do
      result = client.list_pull_request_review_comments(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      expect(result[:result]).to be_an(Array)
    end

    it 'includes comment body and path' do
      result = client.list_pull_request_review_comments(owner: 'octocat', repo: 'Hello-World', pull_number: 42)
      comment = result[:result].first
      expect(comment['body']).to eq('Nit: rename this')
      expect(comment['path']).to eq('lib/foo.rb')
    end
  end

  describe '#create_review' do
    it 'posts a COMMENT review with body and no inline comments' do
      stubs.post('/repos/octocat/Hello-World/pulls/42/reviews') do
        [200, { 'Content-Type' => 'application/json' }, { 'id' => 1, 'state' => 'COMMENTED' }]
      end
      result = client.create_review(owner: 'octocat', repo: 'Hello-World', pull_number: 42, body: 'Looks good overall')
      expect(result[:result]['state']).to eq('COMMENTED')
    end

    it 'posts inline comments when provided' do
      captured_body = nil
      stubs.post('/repos/octocat/Hello-World/pulls/42/reviews') do |env|
        captured_body = JSON.parse(env.body)
        [200, { 'Content-Type' => 'application/json' }, { 'id' => 2, 'state' => 'COMMENTED' }]
      end
      inline = [{ path: 'lib/foo.rb', position: 3, body: 'Nit: rename this' }]
      result = client.create_review(owner: 'octocat', repo: 'Hello-World', pull_number: 42, body: 'See inline', comments: inline)
      expect(result[:result]['id']).to eq(2)
      expect(captured_body['comments']).to be_an(Array)
      expect(captured_body['comments'].first['path']).to eq('lib/foo.rb')
      expect(captured_body['comments'].first['body']).to eq('Nit: rename this')
    end

    it 'defaults event to COMMENT' do
      captured_body = nil
      stubs.post('/repos/octocat/Hello-World/pulls/42/reviews') do |env|
        captured_body = JSON.parse(env.body)
        [200, { 'Content-Type' => 'application/json' }, { 'id' => 3 }]
      end
      client.create_review(owner: 'octocat', repo: 'Hello-World', pull_number: 42, body: 'review body')
      expect(captured_body['event']).to eq('COMMENT')
    end
  end
end
