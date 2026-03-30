# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Client do
  subject(:client) { described_class.new(token: 'test-token') }

  it 'stores configuration' do
    expect(client.opts[:token]).to eq('test-token')
    expect(client.opts[:api_url]).to eq('https://api.github.com')
  end

  it 'accepts a custom api_url' do
    custom = described_class.new(token: 'tok', api_url: 'https://github.example.com/api/v3')
    expect(custom.opts[:api_url]).to eq('https://github.example.com/api/v3')
  end

  it 'returns a Faraday connection' do
    expect(client.connection).to be_a(Faraday::Connection)
  end

  describe 'App runner inclusion' do
    it 'responds to generate_jwt' do
      expect(client).to respond_to(:generate_jwt)
    end

    it 'responds to create_installation_token' do
      expect(client).to respond_to(:create_installation_token)
    end

    it 'responds to verify_signature' do
      expect(client).to respond_to(:verify_signature)
    end

    it 'responds to generate_manifest' do
      expect(client).to respond_to(:generate_manifest)
    end
  end

  describe 'OAuth runner inclusion' do
    it 'responds to authorize_url' do
      expect(client).to respond_to(:authorize_url)
    end

    it 'responds to exchange_code' do
      expect(client).to respond_to(:exchange_code)
    end

    it 'responds to generate_pkce' do
      expect(client).to respond_to(:generate_pkce)
    end
  end
end
