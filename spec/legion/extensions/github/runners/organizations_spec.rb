# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Organizations do
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

  describe '#get_org' do
    it 'returns an organization' do
      stubs.get('/orgs/github') { [200, { 'Content-Type' => 'application/json' }, { 'login' => 'github' }] }
      result = client.get_org(org: 'github')
      expect(result[:result]['login']).to eq('github')
    end
  end

  describe '#list_org_repos' do
    it 'returns repos for an org' do
      stubs.get('/orgs/github/repos') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'name' => 'docs' }]]
      end
      result = client.list_org_repos(org: 'github')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['name']).to eq('docs')
    end
  end
end
