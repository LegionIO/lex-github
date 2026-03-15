# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Labels do
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

  describe '#list_labels' do
    it 'returns labels for a repo' do
      stubs.get('/repos/octocat/Hello-World/labels') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'name' => 'bug' }]]
      end
      result = client.list_labels(owner: 'octocat', repo: 'Hello-World')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['name']).to eq('bug')
    end
  end

  describe '#get_label' do
    it 'returns a single label' do
      stubs.get('/repos/octocat/Hello-World/labels/bug') do
        [200, { 'Content-Type' => 'application/json' }, { 'name' => 'bug', 'color' => 'd73a4a' }]
      end
      result = client.get_label(owner: 'octocat', repo: 'Hello-World', name: 'bug')
      expect(result[:result]['name']).to eq('bug')
      expect(result[:result]['color']).to eq('d73a4a')
    end
  end

  describe '#create_label' do
    it 'creates a new label' do
      stubs.post('/repos/octocat/Hello-World/labels') do
        [201, { 'Content-Type' => 'application/json' }, { 'name' => 'enhancement', 'color' => 'a2eeef' }]
      end
      result = client.create_label(owner: 'octocat', repo: 'Hello-World', name: 'enhancement', color: 'a2eeef')
      expect(result[:result]['name']).to eq('enhancement')
    end
  end

  describe '#update_label' do
    it 'updates an existing label' do
      stubs.patch('/repos/octocat/Hello-World/labels/bug') do
        [200, { 'Content-Type' => 'application/json' }, { 'name' => 'defect', 'color' => 'ee0701' }]
      end
      result = client.update_label(owner: 'octocat', repo: 'Hello-World', name: 'bug', new_name: 'defect')
      expect(result[:result]['name']).to eq('defect')
    end
  end

  describe '#delete_label' do
    it 'deletes a label and returns true' do
      stubs.delete('/repos/octocat/Hello-World/labels/bug') { [204, {}, ''] }
      result = client.delete_label(owner: 'octocat', repo: 'Hello-World', name: 'bug')
      expect(result[:result]).to be true
    end
  end

  describe '#add_labels_to_issue' do
    it 'adds labels to an issue' do
      stubs.post('/repos/octocat/Hello-World/issues/1/labels') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'name' => 'bug' }]]
      end
      result = client.add_labels_to_issue(owner: 'octocat', repo: 'Hello-World', issue_number: 1, labels: ['bug'])
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['name']).to eq('bug')
    end
  end

  describe '#remove_label_from_issue' do
    it 'removes a label from an issue and returns true' do
      stubs.delete('/repos/octocat/Hello-World/issues/1/labels/bug') { [204, {}, ''] }
      result = client.remove_label_from_issue(owner: 'octocat', repo: 'Hello-World', issue_number: 1, name: 'bug')
      expect(result[:result]).to be true
    end
  end
end
