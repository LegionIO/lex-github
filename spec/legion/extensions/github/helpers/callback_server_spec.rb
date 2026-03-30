# frozen_string_literal: true

require 'net/http'
require 'uri'

RSpec.describe Legion::Extensions::Github::Helpers::CallbackServer do
  subject(:server) { described_class.new }

  describe '#start and #redirect_uri' do
    it 'binds to a random port on localhost' do
      server.start
      expect(server.port).to be_a(Integer)
      expect(server.port).to be > 0
      expect(server.redirect_uri).to match(%r{http://127\.0\.0\.1:\d+/callback})
    ensure
      server.shutdown
    end
  end

  describe '#wait_for_callback' do
    it 'returns code and state from callback request' do
      server.start
      Thread.new do
        sleep 0.1
        Net::HTTP.get(URI("#{server.redirect_uri}?code=test-code&state=test-state"))
      end
      result = server.wait_for_callback(timeout: 5)
      expect(result[:code]).to eq('test-code')
      expect(result[:state]).to eq('test-state')
    ensure
      server.shutdown
    end

    it 'returns nil on timeout' do
      server.start
      result = server.wait_for_callback(timeout: 0.1)
      expect(result).to be_nil
    ensure
      server.shutdown
    end
  end
end
