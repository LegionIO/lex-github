# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Branches do
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

  describe '#create_branch' do
    let(:sha) { 'abc123def456' }

    before do
      stubs.get('/repos/octocat/Hello-World/git/ref/heads/main') do
        [200, { 'Content-Type' => 'application/json' },
         { 'ref' => 'refs/heads/main', 'object' => { 'sha' => sha } }]
      end
      stubs.post('/repos/octocat/Hello-World/git/refs') do
        [201, { 'Content-Type' => 'application/json' },
         { 'ref' => 'refs/heads/feature-branch', 'object' => { 'sha' => sha } }]
      end
    end

    it 'returns success with ref and sha' do
      result = client.create_branch(owner: 'octocat', repo: 'Hello-World', branch: 'feature-branch')
      expect(result[:success]).to be true
      expect(result[:ref]).to eq('refs/heads/feature-branch')
      expect(result[:sha]).to eq(sha)
    end

    it 'GETs the source ref to resolve sha' do
      client.create_branch(owner: 'octocat', repo: 'Hello-World', branch: 'feature-branch')
      stubs.verify_stubbed_calls
    end

    it 'uses from_ref to resolve sha when specified' do
      stubs.get('/repos/octocat/Hello-World/git/ref/heads/develop') do
        [200, { 'Content-Type' => 'application/json' },
         { 'ref' => 'refs/heads/develop', 'object' => { 'sha' => 'devsha999' } }]
      end
      stubs.post('/repos/octocat/Hello-World/git/refs') do
        [201, { 'Content-Type' => 'application/json' },
         { 'ref' => 'refs/heads/from-develop', 'object' => { 'sha' => 'devsha999' } }]
      end
      result = client.create_branch(owner: 'octocat', repo: 'Hello-World',
                                    branch: 'from-develop', from_ref: 'develop')
      expect(result[:success]).to be true
      expect(result[:sha]).to eq('devsha999')
    end

    it 'returns success: false with error message on failure' do
      allow(client).to receive(:connection).and_raise(StandardError, 'network error')
      result = client.create_branch(owner: 'octocat', repo: 'Hello-World', branch: 'bad-branch')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('network error')
    end
  end
end
