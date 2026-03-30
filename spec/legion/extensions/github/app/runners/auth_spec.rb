# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Auth do
  let(:runner) { Object.new.extend(described_class) }
  let(:test_connection) do
    Faraday.new(url: 'https://api.github.com') do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/
      conn.adapter :test, stubs
    end
  end
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }

  before { allow(runner).to receive(:connection).and_return(test_connection) }

  describe '#generate_jwt' do
    it 'generates a valid RS256 JWT with app_id as issuer' do
      result = runner.generate_jwt(app_id: '12345', private_key: private_key.to_pem)
      expect(result[:result]).to be_a(String)

      decoded = JWT.decode(result[:result], private_key.public_key, true, algorithm: 'RS256')
      expect(decoded.first['iss']).to eq('12345')
    end

    it 'sets iat to 60 seconds in the past' do
      result = runner.generate_jwt(app_id: '12345', private_key: private_key.to_pem)
      decoded = JWT.decode(result[:result], private_key.public_key, true, algorithm: 'RS256')
      expect(decoded.first['iat']).to be_within(5).of(Time.now.to_i - 60)
    end

    it 'sets exp to 10 minutes from now' do
      result = runner.generate_jwt(app_id: '12345', private_key: private_key.to_pem)
      decoded = JWT.decode(result[:result], private_key.public_key, true, algorithm: 'RS256')
      expect(decoded.first['exp']).to be_within(5).of(Time.now.to_i + 600)
    end
  end

  describe '#create_installation_token' do
    it 'exchanges a JWT for an installation access token' do
      stubs.post('/app/installations/67890/access_tokens') do
        [201, { 'Content-Type' => 'application/json' },
         { 'token' => 'ghs_test123', 'expires_at' => '2026-03-30T12:00:00Z' }]
      end

      result = runner.create_installation_token(jwt: 'fake-jwt', installation_id: '67890')
      expect(result[:result]['token']).to eq('ghs_test123')
      expect(result[:result]['expires_at']).to eq('2026-03-30T12:00:00Z')
    end
  end

  describe '#list_installations' do
    it 'lists installations for the authenticated app' do
      stubs.get('/app/installations') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 67890, 'account' => { 'login' => 'LegionIO' } }]]
      end

      result = runner.list_installations(jwt: 'fake-jwt')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].first['id']).to eq(67890)
    end
  end

  describe '#get_installation' do
    it 'returns a single installation' do
      stubs.get('/app/installations/67890') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 67890, 'account' => { 'login' => 'LegionIO' } }]
      end

      result = runner.get_installation(jwt: 'fake-jwt', installation_id: '67890')
      expect(result[:result]['id']).to eq(67890)
    end
  end
end
