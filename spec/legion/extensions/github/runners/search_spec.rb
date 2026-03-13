# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Search do
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

  describe '#search_repositories' do
    it 'searches for repositories' do
      stubs.get('/search/repositories') do
        [200, { 'Content-Type' => 'application/json' }, { 'total_count' => 1, 'items' => [{ 'name' => 'ruby' }] }]
      end
      result = client.search_repositories(query: 'ruby language:ruby')
      expect(result[:result]['total_count']).to eq(1)
    end
  end

  describe '#search_issues' do
    it 'searches for issues' do
      stubs.get('/search/issues') do
        [200, { 'Content-Type' => 'application/json' }, { 'total_count' => 5, 'items' => [] }]
      end
      result = client.search_issues(query: 'bug label:bug')
      expect(result[:result]['total_count']).to eq(5)
    end
  end

  describe '#search_users' do
    it 'searches for users' do
      stubs.get('/search/users') do
        [200, { 'Content-Type' => 'application/json' }, { 'total_count' => 1, 'items' => [{ 'login' => 'octocat' }] }]
      end
      result = client.search_users(query: 'octocat')
      expect(result[:result]['items'].first['login']).to eq('octocat')
    end
  end
end
