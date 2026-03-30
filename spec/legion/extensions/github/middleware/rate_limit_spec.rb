# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Middleware::RateLimit do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:handler) { double('handler') }
  let(:conn) do
    Faraday.new do |f|
      f.use described_class, handler: handler
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.adapter :test, stubs
    end
  end

  describe 'normal response' do
    it 'passes through without modification' do
      stubs.get('/repos/test/repo') do
        [200, { 'Content-Type'          => 'application/json',
                'X-RateLimit-Remaining' => '4999',
                'X-RateLimit-Reset'     => (Time.now.to_i + 3600).to_s }, { 'name' => 'repo' }]
      end
      response = conn.get('/repos/test/repo')
      expect(response.status).to eq(200)
    end
  end

  describe '429 response' do
    it 'calls on_rate_limit on the handler with fingerprint' do
      reset_time = Time.now.to_i + 300
      stubs.get('/repos/test/repo') do
        [429, { 'Content-Type'          => 'application/json',
                'X-RateLimit-Remaining' => '0',
                'X-RateLimit-Reset'     => reset_time.to_s },
         { 'message' => 'API rate limit exceeded' }]
      end
      expect(handler).to receive(:on_rate_limit).with(
        hash_including(remaining: 0, reset_at: anything, status: 429)
      )
      conn.get('/repos/test/repo')
    end
  end

  describe 'X-RateLimit-Remaining: 0 on 200' do
    it 'calls on_rate_limit when remaining hits zero' do
      reset_time = Time.now.to_i + 300
      stubs.get('/repos/test/repo') do
        [200, { 'Content-Type'          => 'application/json',
                'X-RateLimit-Remaining' => '0',
                'X-RateLimit-Reset'     => reset_time.to_s }, { 'name' => 'repo' }]
      end
      expect(handler).to receive(:on_rate_limit).with(hash_including(remaining: 0))
      conn.get('/repos/test/repo')
    end
  end

  describe 'no rate limit headers' do
    it 'does not call handler' do
      stubs.get('/repos/test/repo') do
        [200, { 'Content-Type' => 'application/json' }, { 'name' => 'repo' }]
      end
      expect(handler).not_to receive(:on_rate_limit)
      conn.get('/repos/test/repo')
    end
  end
end
