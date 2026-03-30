# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::App::Runners::Webhooks do
  let(:runner) { Object.new.extend(described_class) }
  let(:webhook_secret) { 'test-webhook-secret' }
  let(:payload) { '{"action":"opened","number":1}' }
  let(:valid_signature) { "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, payload)}" }

  describe '#verify_signature' do
    it 'returns true for a valid signature' do
      result = runner.verify_signature(payload: payload, signature: valid_signature, secret: webhook_secret)
      expect(result[:result]).to be true
    end

    it 'returns false for an invalid signature' do
      result = runner.verify_signature(payload: payload, signature: 'sha256=invalid', secret: webhook_secret)
      expect(result[:result]).to be false
    end

    it 'returns false for a nil signature' do
      result = runner.verify_signature(payload: payload, signature: nil, secret: webhook_secret)
      expect(result[:result]).to be false
    end
  end

  describe '#parse_event' do
    it 'parses a webhook payload with event metadata' do
      result = runner.parse_event(
        payload:     payload,
        event_type:  'pull_request',
        delivery_id: 'abc-123'
      )
      expect(result[:result][:event_type]).to eq('pull_request')
      expect(result[:result][:delivery_id]).to eq('abc-123')
      expect(result[:result][:payload]['action']).to eq('opened')
    end
  end

  describe '#receive_event' do
    it 'verifies signature and parses event in one call' do
      result = runner.receive_event(
        payload:     payload,
        signature:   valid_signature,
        secret:      webhook_secret,
        event_type:  'issues',
        delivery_id: 'def-456'
      )
      expect(result[:result][:verified]).to be true
      expect(result[:result][:event_type]).to eq('issues')
      expect(result[:result][:payload]['action']).to eq('opened')
    end

    it 'rejects events with invalid signatures' do
      result = runner.receive_event(
        payload:     payload,
        signature:   'sha256=bad',
        secret:      webhook_secret,
        event_type:  'issues',
        delivery_id: 'def-456'
      )
      expect(result[:result][:verified]).to be false
      expect(result[:result][:payload]).to be_nil
    end
  end
end
