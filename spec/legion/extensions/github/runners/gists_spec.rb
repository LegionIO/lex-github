# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::Gists do
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

  describe '#list_gists' do
    it 'returns gists for authenticated user' do
      stubs.get('/gists') { [200, { 'Content-Type' => 'application/json' }, [{ 'id' => '1' }]] }
      result = client.list_gists
      expect(result[:result]).to be_an(Array)
    end
  end

  describe '#create_gist' do
    it 'creates a new gist' do
      stubs.post('/gists') { [201, { 'Content-Type' => 'application/json' }, { 'id' => '2' }] }
      files = { 'hello.rb' => { content: 'puts "hello"' } }
      result = client.create_gist(files: files, description: 'test')
      expect(result[:result]['id']).to eq('2')
    end
  end

  describe '#delete_gist' do
    it 'deletes a gist' do
      stubs.delete('/gists/1') { [204, {}, ''] }
      result = client.delete_gist(gist_id: '1')
      expect(result[:result]).to be true
    end
  end
end
