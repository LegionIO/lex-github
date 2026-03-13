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
end
