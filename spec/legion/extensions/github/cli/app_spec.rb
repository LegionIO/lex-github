# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::CLI::App do
  let(:cli) { Object.new.extend(described_class) }
  let(:server) { instance_double(Legion::Extensions::Github::Helpers::CallbackServer) }

  before do
    allow(Legion::Extensions::Github::Helpers::CallbackServer).to receive(:new).and_return(server)
    allow(server).to receive(:start)
    allow(server).to receive(:shutdown)
    allow(server).to receive(:port).and_return(12_345)
    allow(server).to receive(:redirect_uri).and_return('http://127.0.0.1:12345/callback')
  end

  describe '#setup' do
    it 'generates manifest and returns manifest URL' do
      result = cli.setup(
        name:        'LegionIO Bot',
        url:         'https://legionio.dev',
        webhook_url: 'https://legion.example.com/api/hooks/lex/github/app/webhook'
      )
      expect(result[:result][:manifest_url]).to include('github.com/settings/apps/new')
    end

    it 'supports org-scoped setup' do
      result = cli.setup(
        name:        'LegionIO Bot',
        url:         'https://legionio.dev',
        webhook_url: 'https://legion.example.com/webhook',
        org:         'LegionIO'
      )
      expect(result[:result][:manifest_url]).to include('/organizations/LegionIO/')
    end
  end

  describe '#complete_setup' do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:test_connection) do
      Faraday.new(url: 'https://api.github.com') do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.adapter :test, stubs
      end
    end

    before { allow(cli).to receive(:connection).and_return(test_connection) }

    it 'exchanges manifest code and stores credentials' do
      stubs.post('/app-manifests/test-code/conversions') do
        [201, { 'Content-Type' => 'application/json' },
         { 'id' => 12_345, 'pem' => '-----BEGIN RSA...', 'client_id' => 'Iv1.abc',
           'client_secret' => 'secret', 'webhook_secret' => 'whsec' }]
      end
      allow(cli).to receive(:store_app_credentials)

      result = cli.complete_setup(code: 'test-code')
      expect(result[:result]['id']).to eq(12_345)
    end
  end
end
