# spec/absorbers/webhook_setup_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Stub runners for isolated testing
module Legion
  module Extensions
    module Github
      module Runners
        module RepositoryWebhooks
          def create_webhook(events:, **)
            { result: { 'id' => 12_345, 'active' => true, 'events' => events } }
          end

          def list_webhooks(**)
            { result: [] }
          end
        end

        module Labels
          def create_label(name:, **)
            { result: { 'id' => 1, 'name' => name } }
          end
        end
      end
    end
  end
end

require 'legion/extensions/github/absorbers/webhook_setup'

RSpec.describe Legion::Extensions::Github::Absorbers::WebhookSetup do
  let(:test_class) do
    Class.new do
      include Legion::Extensions::Github::Runners::RepositoryWebhooks
      include Legion::Extensions::Github::Runners::Labels
      include Legion::Extensions::Github::Absorbers::WebhookSetup
    end
  end
  let(:instance) { test_class.new }

  describe '#setup_fleet_webhook' do
    let(:params) do
      { owner: 'LegionIO', repo: 'lex-exec', webhook_url: 'https://fleet.example.com/webhook' }
    end

    it 'creates a webhook for issues events' do
      result = instance.setup_fleet_webhook(**params)
      expect(result[:success]).to be true
    end

    it 'returns the webhook id' do
      result = instance.setup_fleet_webhook(**params)
      expect(result[:webhook_id]).to eq(12_345)
    end

    it 'creates fleet labels on the repo' do
      result = instance.setup_fleet_webhook(**params)
      expect(result[:labels_created]).to be_a(Array)
    end

    context 'when webhook already exists' do
      before do
        allow(instance).to receive(:list_webhooks).and_return({
                                                                result: [
                                                                  { 'config' => { 'url' => 'https://fleet.example.com/webhook' }, 'id' => 99 }
                                                                ]
                                                              })
      end

      it 'returns already_exists' do
        result = instance.setup_fleet_webhook(**params)
        expect(result[:success]).to be true
        expect(result[:existing]).to be true
      end
    end

    context 'when webhook creation returns no id' do
      before do
        allow(instance).to receive(:create_webhook).and_return({ result: {} })
      end

      it 'returns success: false' do
        result = instance.setup_fleet_webhook(**params)
        expect(result[:success]).to be false
      end
    end
  end

  describe '#fleet_label_definitions' do
    it 'returns 4 fleet labels' do
      labels = instance.fleet_label_definitions
      expect(labels.size).to eq(4)
    end

    it 'includes fleet:received' do
      labels = instance.fleet_label_definitions
      names = labels.map { |l| l[:name] }
      expect(names).to include('fleet:received')
    end

    it 'includes fleet:implementing' do
      labels = instance.fleet_label_definitions
      names = labels.map { |l| l[:name] }
      expect(names).to include('fleet:implementing')
    end

    it 'includes fleet:pr-open' do
      labels = instance.fleet_label_definitions
      names = labels.map { |l| l[:name] }
      expect(names).to include('fleet:pr-open')
    end

    it 'includes fleet:escalated' do
      labels = instance.fleet_label_definitions
      names = labels.map { |l| l[:name] }
      expect(names).to include('fleet:escalated')
    end
  end
end
