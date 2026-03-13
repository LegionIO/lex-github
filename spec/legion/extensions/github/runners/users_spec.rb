# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Users do
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

  describe '#get_authenticated_user' do
    it 'returns the authenticated user' do
      stubs.get('/user') { [200, { 'Content-Type' => 'application/json' }, { 'login' => 'octocat' }] }
      result = client.get_authenticated_user
      expect(result[:result]['login']).to eq('octocat')
    end
  end

  describe '#get_user' do
    it 'returns a user by username' do
      stubs.get('/users/octocat') { [200, { 'Content-Type' => 'application/json' }, { 'login' => 'octocat' }] }
      result = client.get_user(username: 'octocat')
      expect(result[:result]['login']).to eq('octocat')
    end
  end

  describe '#list_followers' do
    it 'returns followers for a user' do
      stubs.get('/users/octocat/followers') do
        [200, { 'Content-Type' => 'application/json' }, [{ 'login' => 'fan1' }]]
      end
      result = client.list_followers(username: 'octocat')
      expect(result[:result]).to be_an(Array)
    end
  end
end
