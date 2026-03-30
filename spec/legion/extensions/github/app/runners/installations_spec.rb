# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Installations do
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

  describe '#list_installations' do
    it 'lists all installations for the app' do
      stubs.get('/app/installations') do
        [200, { 'Content-Type' => 'application/json' },
         [{ 'id' => 1, 'account' => { 'login' => 'LegionIO' } },
          { 'id' => 2, 'account' => { 'login' => 'other-org' } }]]
      end
      result = runner.list_installations(jwt: 'fake-jwt')
      expect(result[:result]).to be_an(Array)
      expect(result[:result].length).to eq(2)
    end
  end

  describe '#get_installation' do
    it 'returns a single installation' do
      stubs.get('/app/installations/12345') do
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => 12_345, 'account' => { 'login' => 'LegionIO' },
           'permissions' => { 'contents' => 'write' } }]
      end
      result = runner.get_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]['id']).to eq(12_345)
    end
  end

  describe '#list_installation_repos' do
    it 'lists repos accessible to an installation' do
      stubs.get('/installation/repositories') do
        [200, { 'Content-Type' => 'application/json' },
         { 'total_count' => 1, 'repositories' => [{ 'full_name' => 'LegionIO/lex-github' }] }]
      end
      result = runner.list_installation_repos(token: 'ghs_test')
      expect(result[:result]['repositories'].first['full_name']).to eq('LegionIO/lex-github')
    end
  end

  describe '#suspend_installation' do
    it 'suspends an installation' do
      stubs.put('/app/installations/12345/suspended') { [204, {}, ''] }
      result = runner.suspend_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]).to be true
    end
  end

  describe '#unsuspend_installation' do
    it 'unsuspends an installation' do
      stubs.delete('/app/installations/12345/suspended') { [204, {}, ''] }
      result = runner.unsuspend_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]).to be true
    end
  end

  describe '#delete_installation' do
    it 'deletes an installation' do
      stubs.delete('/app/installations/12345') { [204, {}, ''] }
      result = runner.delete_installation(jwt: 'fake-jwt', installation_id: '12345')
      expect(result[:result]).to be true
    end
  end
end
