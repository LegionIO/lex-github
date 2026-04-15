# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::Runners::App do
  let(:runner) { Object.new.extend(described_class) }

  it 'includes CLI::App methods' do
    expect(described_class.instance_methods).to include(:setup, :complete_setup)
  end

  it 'is not remote invocable' do
    expect(described_class.remote_invocable?).to be false
  end

  describe '#setup' do
    let(:server) { instance_double(Legion::Extensions::Github::Helpers::CallbackServer) }

    before do
      allow(Legion::Extensions::Github::Helpers::CallbackServer).to receive(:new).and_return(server)
      allow(server).to receive(:start)
      allow(server).to receive(:shutdown)
      allow(server).to receive(:port).and_return(12_345)
      allow(server).to receive(:redirect_uri).and_return('http://127.0.0.1:12345/callback')
      allow(server).to receive(:wait_for_callback).and_return({ code: 'manifest-code', state: nil })
    end

    it 'returns a manifest URL and callback result' do
      result = runner.setup(
        name:        'LegionIO Bot',
        url:         'https://legionio.dev',
        webhook_url: 'https://legion.example.com/webhooks/github'
      )
      expect(result[:result]).to include(:manifest_url, :callback)
    end
  end
end
