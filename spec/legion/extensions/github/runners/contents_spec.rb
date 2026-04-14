# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Contents do
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

  describe '#get_file_content' do
    before do
      stubs.get('/repos/octocat/Hello-World/contents/README.md') do
        [200, { 'Content-Type' => 'application/json' },
         { 'name' => 'README.md', 'path' => 'README.md',
           'content' => 'SGVsbG8gV29ybGQ=', 'encoding' => 'base64', 'sha' => 'abc123' }]
      end
    end

    it 'fetches file content from the GitHub Contents API' do
      result = client.get_file_content(owner: 'octocat', repo: 'Hello-World', path: 'README.md')
      expect(result[:result]).to be_a(Hash)
      expect(result[:result]['path']).to eq('README.md')
    end

    it 'wraps the response under :result' do
      result = client.get_file_content(owner: 'octocat', repo: 'Hello-World', path: 'README.md')
      expect(result).to have_key(:result)
    end

    it 'accepts a ref parameter' do
      stubs.get('/repos/octocat/Hello-World/contents/README.md') do |env|
        expect(env.params['ref']).to eq('main')
        [200, { 'Content-Type' => 'application/json' },
         { 'path' => 'README.md', 'sha' => 'abc123' }]
      end
      client.get_file_content(owner: 'octocat', repo: 'Hello-World', path: 'README.md', ref: 'main')
    end
  end

  describe '#commit_files' do
    let(:commit_sha) { 'commit111' }
    let(:base_tree_sha) { 'tree222' }
    let(:new_tree_sha) { 'tree333' }
    let(:new_commit_sha) { 'commit444' }
    let(:files) { [{ path: 'README.md', content: '# Hello' }] }

    before do
      stubs.get('/repos/octocat/Hello-World/git/ref/heads/main') do
        [200, { 'Content-Type' => 'application/json' },
         { 'ref' => 'refs/heads/main', 'object' => { 'sha' => commit_sha } }]
      end
      stubs.get("/repos/octocat/Hello-World/git/commits/#{commit_sha}") do
        [200, { 'Content-Type' => 'application/json' },
         { 'sha' => commit_sha, 'tree' => { 'sha' => base_tree_sha } }]
      end
      stubs.post('/repos/octocat/Hello-World/git/trees') do
        [201, { 'Content-Type' => 'application/json' },
         { 'sha' => new_tree_sha }]
      end
      stubs.post('/repos/octocat/Hello-World/git/commits') do
        [201, { 'Content-Type' => 'application/json' },
         { 'sha' => new_commit_sha }]
      end
      stubs.patch('/repos/octocat/Hello-World/git/refs/heads/main') do
        [200, { 'Content-Type' => 'application/json' },
         { 'ref' => 'refs/heads/main', 'object' => { 'sha' => new_commit_sha } }]
      end
    end

    it 'returns success with commit_sha and tree_sha' do
      result = client.commit_files(owner: 'octocat', repo: 'Hello-World',
                                   branch: 'main', files: files, message: 'add readme')
      expect(result[:success]).to be true
      expect(result[:commit_sha]).to eq(new_commit_sha)
      expect(result[:tree_sha]).to eq(new_tree_sha)
    end

    it 'executes the full multi-step git data API flow' do
      client.commit_files(owner: 'octocat', repo: 'Hello-World',
                          branch: 'main', files: files, message: 'add readme')
      stubs.verify_stubbed_calls
    end

    it 'returns success: false with error message on failure' do
      allow(client).to receive(:connection).and_raise(StandardError, 'api error')
      result = client.commit_files(owner: 'octocat', repo: 'Hello-World',
                                   branch: 'main', files: files, message: 'add readme')
      expect(result[:success]).to be false
      expect(result[:error]).to eq('api error')
    end
  end
end
