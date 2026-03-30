# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::CLI::Auth do
  let(:cli) { Object.new.extend(described_class) }
  let(:browser_auth) { instance_double(Legion::Extensions::Github::Helpers::BrowserAuth) }

  before do
    allow(Legion::Extensions::Github::Helpers::BrowserAuth).to receive(:new).and_return(browser_auth)
  end

  describe '#login' do
    it 'authenticates and returns token result' do
      allow(browser_auth).to receive(:authenticate).and_return(
        result: { 'access_token' => 'ghu_test', 'refresh_token' => 'ghr_test' }
      )
      result = cli.login(client_id: 'Iv1.abc', client_secret: 'secret')
      expect(result[:result]['access_token']).to eq('ghu_test')
    end
  end

  describe '#status' do
    it 'returns current auth info when token available' do
      allow(cli).to receive(:resolve_credential).and_return(
        { token: 'ghp_test', auth_type: :pat }
      )
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get('/user') do
        [200, { 'Content-Type' => 'application/json' }, { 'login' => 'octocat' }]
      end
      conn = Faraday.new(url: 'https://api.github.com') do |f|
        f.response :json, content_type: /\bjson$/
        f.adapter :test, stubs
      end
      allow(cli).to receive(:connection).and_return(conn)

      result = cli.status
      expect(result[:result][:auth_type]).to eq(:pat)
      expect(result[:result][:user]).to eq('octocat')
    end

    it 'returns unauthenticated when no credentials' do
      allow(cli).to receive(:resolve_credential).and_return(nil)
      result = cli.status
      expect(result[:result][:authenticated]).to be false
    end
  end
end
