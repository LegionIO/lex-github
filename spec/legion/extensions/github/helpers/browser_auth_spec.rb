# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Helpers::BrowserAuth do
  let(:oauth_runner) { Object.new.extend(Legion::Extensions::Github::OAuth::Runners::Auth) }
  let(:auth) { described_class.new(client_id: 'Iv1.abc', client_secret: 'secret', auth: oauth_runner) }

  describe '#gui_available?' do
    it 'returns true on macOS' do
      allow(auth).to receive(:host_os).and_return('darwin23')
      expect(auth.gui_available?).to be true
    end

    it 'returns false on headless linux without DISPLAY' do
      allow(auth).to receive(:host_os).and_return('linux-gnu')
      allow(ENV).to receive(:[]).with('DISPLAY').and_return(nil)
      allow(ENV).to receive(:[]).with('WAYLAND_DISPLAY').and_return(nil)
      expect(auth.gui_available?).to be false
    end
  end

  describe '#authenticate' do
    context 'without GUI' do
      before do
        allow(auth).to receive(:gui_available?).and_return(false)
      end

      it 'falls back to device code flow' do
        expect(oauth_runner).to receive(:request_device_code).and_return(
          result: { 'device_code' => 'dc', 'user_code' => 'ABCD',
                    'verification_uri' => 'https://github.com/login/device',
                    'expires_in' => 900, 'interval' => 5 }
        )
        expect(oauth_runner).to receive(:poll_device_code).and_return(
          result: { 'access_token' => 'ghu_device' }
        )
        result = auth.authenticate
        expect(result[:result]['access_token']).to eq('ghu_device')
      end
    end
  end
end
