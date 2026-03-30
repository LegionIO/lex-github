# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Manifest do
  let(:runner) { Object.new.extend(described_class) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end

  before { allow(runner).to receive(:connection).and_return(test_connection) }

  describe '#generate_manifest' do
    it 'builds a manifest hash with required fields' do
      result = runner.generate_manifest(
        name:         'LegionIO Bot',
        url:          'https://legionio.dev',
        webhook_url:  'https://legion.example.com/api/hooks/lex/github/app/webhook',
        callback_url: 'https://legion.example.com/api/hooks/lex/github/app/setup/callback'
      )
      manifest = result[:result]
      expect(manifest[:name]).to eq('LegionIO Bot')
      expect(manifest[:url]).to eq('https://legionio.dev')
      expect(manifest[:hook_attributes][:url]).to eq('https://legion.example.com/api/hooks/lex/github/app/webhook')
      expect(manifest[:setup_url]).to include('setup/callback')
      expect(manifest[:default_permissions]).to be_a(Hash)
      expect(manifest[:default_events]).to be_an(Array)
    end
  end

  describe '#exchange_manifest_code' do
    it 'converts a manifest code into app credentials' do
      stubs.post('/app-manifests/test-code/conversions') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 12_345, 'client_id' => 'Iv1.abc', 'client_secret' => 'secret',
           'pem' => '-----BEGIN RSA PRIVATE KEY-----...', 'webhook_secret' => 'whsec' }]
      end

      result = runner.exchange_manifest_code(code: 'test-code')
      expect(result[:result]['id']).to eq(12_345)
      expect(result[:result]['pem']).to start_with('-----BEGIN')
    end
  end

  describe '#manifest_url' do
    it 'returns the GitHub manifest creation URL' do
      result = runner.generate_manifest(
        name: 'Test', url: 'https://test.com',
        webhook_url: 'https://test.com/webhook',
        callback_url: 'https://test.com/callback'
      )
      url = runner.manifest_url(manifest: result[:result])
      expect(url[:result]).to start_with('https://github.com/settings/apps/new')
    end

    it 'supports org-scoped manifest URL' do
      result = runner.generate_manifest(
        name: 'Test', url: 'https://test.com',
        webhook_url: 'https://test.com/webhook',
        callback_url: 'https://test.com/callback'
      )
      url = runner.manifest_url(manifest: result[:result], org: 'LegionIO')
      expect(url[:result]).to include('/organizations/LegionIO/settings/apps/new')
    end
  end
end
