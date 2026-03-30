# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Checks do
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

  describe '#create_check_run' do
    it 'creates a check run' do
      stubs.post('/repos/LegionIO/lex-github/check-runs') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'name' => 'Legion CI', 'status' => 'queued' }]
      end
      result = client.create_check_run(owner: 'LegionIO', repo: 'lex-github',
                                       name: 'Legion CI', head_sha: 'abc123')
      expect(result[:result]['name']).to eq('Legion CI')
      expect(result[:result]['status']).to eq('queued')
    end
  end

  describe '#update_check_run' do
    it 'updates a check run with conclusion' do
      stubs.patch('/repos/LegionIO/lex-github/check-runs/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'status' => 'completed', 'conclusion' => 'success' }]
      end
      result = client.update_check_run(owner: 'LegionIO', repo: 'lex-github',
                                       check_run_id: 1, status: 'completed', conclusion: 'success')
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#get_check_run' do
    it 'returns a check run' do
      stubs.get('/repos/LegionIO/lex-github/check-runs/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'name' => 'Legion CI', 'conclusion' => 'success' }]
      end
      result = client.get_check_run(owner: 'LegionIO', repo: 'lex-github', check_run_id: 1)
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#list_check_runs_for_ref' do
    it 'returns check runs for a commit ref' do
      stubs.get('/repos/LegionIO/lex-github/commits/abc123/check-runs') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'check_runs' => [{ 'id' => 1, 'name' => 'Legion CI' }] }]
      end
      result = client.list_check_runs_for_ref(owner: 'LegionIO', repo: 'lex-github', ref: 'abc123')
      expect(result[:result]['check_runs'].first['name']).to eq('Legion CI')
    end
  end

  describe '#list_check_suites_for_ref' do
    it 'returns check suites for a commit ref' do
      stubs.get('/repos/LegionIO/lex-github/commits/abc123/check-suites') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'check_suites' => [{ 'id' => 10, 'status' => 'completed' }] }]
      end
      result = client.list_check_suites_for_ref(owner: 'LegionIO', repo: 'lex-github', ref: 'abc123')
      expect(result[:result]['check_suites'].first['status']).to eq('completed')
    end
  end

  describe '#get_check_suite' do
    it 'returns a check suite' do
      stubs.get('/repos/LegionIO/lex-github/check-suites/10') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 10, 'status' => 'completed', 'conclusion' => 'success' }]
      end
      result = client.get_check_suite(owner: 'LegionIO', repo: 'lex-github', check_suite_id: 10)
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#rerequest_check_suite' do
    it 'rerequests a check suite' do
      stubs.post('/repos/LegionIO/lex-github/check-suites/10/rerequest') do
        [201, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.rerequest_check_suite(owner: 'LegionIO', repo: 'lex-github', check_suite_id: 10)
      expect(result[:result]).to be true
    end
  end

  describe '#list_check_run_annotations' do
    it 'returns annotations for a check run' do
      stubs.get('/repos/LegionIO/lex-github/check-runs/1/annotations') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'path' => 'lib/foo.rb', 'message' => 'Lint error', 'annotation_level' => 'warning' }]]
      end
      result = client.list_check_run_annotations(owner: 'LegionIO', repo: 'lex-github', check_run_id: 1)
      expect(result[:result].first['annotation_level']).to eq('warning')
    end
  end
end
