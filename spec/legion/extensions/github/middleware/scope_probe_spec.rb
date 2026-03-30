# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Middleware::ScopeProbe do
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

  describe '403 response' do
    it 'calls on_scope_denied on the handler' do
      stubs.get('/repos/OrgZ/repo1') do
        [403, { 'Content-Type' => 'application/json' },
         { 'message' => 'Resource not accessible by integration' }]
      end
      expect(handler).to receive(:on_scope_denied).with(
        hash_including(status: 403, url: anything)
      )
      conn.get('/repos/OrgZ/repo1')
    end
  end

  describe '2xx response' do
    it 'calls on_scope_authorized on the handler' do
      stubs.get('/repos/OrgZ/repo1') do
        [200, { 'Content-Type' => 'application/json' }, { 'name' => 'repo1' }]
      end
      expect(handler).to receive(:on_scope_authorized).with(
        hash_including(status: 200, url: anything)
      )
      conn.get('/repos/OrgZ/repo1')
    end
  end

  describe '404 response' do
    it 'calls on_scope_denied (repo not visible = not authorized)' do
      stubs.get('/repos/OrgZ/private-repo') do
        [404, { 'Content-Type' => 'application/json' },
         { 'message' => 'Not Found' }]
      end
      expect(handler).to receive(:on_scope_denied).with(
        hash_including(status: 404)
      )
      conn.get('/repos/OrgZ/private-repo')
    end
  end

  describe 'non-repo path' do
    it 'does not call scope handlers for global endpoints' do
      stubs.get('/user') do
        [200, { 'Content-Type' => 'application/json' }, { 'login' => 'test' }]
      end
      expect(handler).not_to receive(:on_scope_denied)
      expect(handler).not_to receive(:on_scope_authorized)
      conn.get('/user')
    end
  end
end
