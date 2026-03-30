# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Actions do
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

  describe '#list_workflows' do
    it 'returns workflows for a repo' do
      stubs.get('/repos/LegionIO/lex-github/actions/workflows') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'workflows' => [{ 'id' => 1, 'name' => 'CI' }] }]
      end
      result = client.list_workflows(owner: 'LegionIO', repo: 'lex-github')
      expect(result[:result]['workflows'].first['name']).to eq('CI')
    end
  end

  describe '#get_workflow' do
    it 'returns a single workflow' do
      stubs.get('/repos/LegionIO/lex-github/actions/workflows/1') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 1, 'name' => 'CI', 'state' => 'active' }]
      end
      result = client.get_workflow(owner: 'LegionIO', repo: 'lex-github', workflow_id: 1)
      expect(result[:result]['state']).to eq('active')
    end
  end

  describe '#list_workflow_runs' do
    it 'returns runs for a workflow' do
      stubs.get('/repos/LegionIO/lex-github/actions/workflows/1/runs') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'workflow_runs' => [{ 'id' => 100, 'status' => 'completed' }] }]
      end
      result = client.list_workflow_runs(owner: 'LegionIO', repo: 'lex-github', workflow_id: 1)
      expect(result[:result]['workflow_runs'].first['status']).to eq('completed')
    end
  end

  describe '#get_workflow_run' do
    it 'returns a single run' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 100, 'status' => 'completed', 'conclusion' => 'success' }]
      end
      result = client.get_workflow_run(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]['conclusion']).to eq('success')
    end
  end

  describe '#trigger_workflow' do
    it 'dispatches a workflow run' do
      stubs.post('/repos/LegionIO/lex-github/actions/workflows/1/dispatches') do
        [204, {}, '']
      end
      result = client.trigger_workflow(owner: 'LegionIO', repo: 'lex-github',
                                       workflow_id: 1, ref: 'main')
      expect(result[:result]).to be true
    end
  end

  describe '#cancel_workflow_run' do
    it 'cancels a running workflow' do
      stubs.post('/repos/LegionIO/lex-github/actions/runs/100/cancel') do
        [202, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.cancel_workflow_run(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be true
    end
  end

  describe '#rerun_workflow' do
    it 'reruns a workflow' do
      stubs.post('/repos/LegionIO/lex-github/actions/runs/100/rerun') do
        [201, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.rerun_workflow(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be true
    end
  end

  describe '#rerun_failed_jobs' do
    it 'reruns only failed jobs in a workflow run' do
      stubs.post('/repos/LegionIO/lex-github/actions/runs/100/rerun-failed-jobs') do
        [201, { 'Content-Type' => 'application/json' }, {}]
      end
      result = client.rerun_failed_jobs(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be true
    end
  end

  describe '#list_workflow_run_jobs' do
    it 'returns jobs for a run' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100/jobs') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'jobs' => [{ 'id' => 200, 'name' => 'test', 'conclusion' => 'success' }] }]
      end
      result = client.list_workflow_run_jobs(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]['jobs'].first['name']).to eq('test')
    end
  end

  describe '#download_workflow_run_logs' do
    it 'returns the log download URL' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100/logs') do
        [200, { 'Content-Type' => 'application/json', 'Location' => 'https://logs.example.com/100.zip' }, '']
      end
      result = client.download_workflow_run_logs(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]).to be_a(Hash)
    end
  end

  describe '#list_workflow_run_artifacts' do
    it 'returns artifacts for a run' do
      stubs.get('/repos/LegionIO/lex-github/actions/runs/100/artifacts') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'artifacts' => [{ 'id' => 300, 'name' => 'coverage' }] }]
      end
      result = client.list_workflow_run_artifacts(owner: 'LegionIO', repo: 'lex-github', run_id: 100)
      expect(result[:result]['artifacts'].first['name']).to eq('coverage')
    end
  end
end
