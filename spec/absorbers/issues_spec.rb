# spec/absorbers/issues_spec.rb
# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'securerandom'

# Minimal stubs for isolated testing
module Legion
  unless defined?(Legion::Cache)
    module Cache
      def self.get(key); end
      def self.set(key, value, ttl: nil); end
    end
  end

  unless defined?(Legion::JSON)
    module JSON
      def self.dump(obj)
        ::JSON.generate(obj)
      end
    end
  end

  unless defined?(Legion::Logging)
    module Logging
      def self.info(msg); end
      def self.warn(msg); end
      def self.debug(msg); end
    end
  end
end

require 'legion/extensions/github/absorbers/helpers'
require 'legion/extensions/github/absorbers/issues'

RSpec.describe Legion::Extensions::Github::Absorbers::Issues do
  let(:opened_payload) do
    {
      'action'     => 'opened',
      'issue'      => {
        'number' => 42,
        'title'  => 'Fix sandbox timeout on macOS',
        'body'   => 'The exec sandbox times out after 30s on macOS ARM64.',
        'labels' => [{ 'name' => 'bug' }],
        'user'   => { 'login' => 'matt-iverson', 'type' => 'User' }
      },
      'repository' => {
        'full_name'      => 'LegionIO/lex-exec',
        'name'           => 'lex-exec',
        'owner'          => { 'login' => 'LegionIO' },
        'default_branch' => 'main',
        'language'       => 'Ruby'
      },
      'sender'     => { 'login' => 'matt-iverson', 'type' => 'User' }
    }
  end

  let(:bot_payload) do
    opened_payload.merge(
      'sender' => { 'login' => 'dependabot[bot]', 'type' => 'Bot' }
    )
  end

  let(:labeled_payload) do
    opened_payload.merge(
      'action' => 'labeled',
      'issue'  => opened_payload['issue'].merge(
        'labels' => [{ 'name' => 'fleet:received' }]
      )
    )
  end

  let(:closed_payload) do
    opened_payload.merge('action' => 'closed')
  end

  before do
    allow(Legion::Cache).to receive(:get).and_return(nil)
    allow(Legion::Cache).to receive(:set)
  end

  describe '.absorb' do
    context 'with a valid opened issue' do
      it 'returns absorbed: true' do
        result = described_class.absorb(payload: opened_payload)
        expect(result[:absorbed]).to be true
      end

      it 'returns a work_item_id' do
        result = described_class.absorb(payload: opened_payload)
        expect(result[:work_item_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end

      it 'stores raw payload in cache' do
        expect(Legion::Cache).to receive(:set).with(
          /\Afleet:payload:/, anything, ttl: 86_400
        )
        described_class.absorb(payload: opened_payload)
      end
    end

    context 'with a bot-generated event' do
      it 'returns absorbed: false with reason :bot_generated' do
        result = described_class.absorb(payload: bot_payload)
        expect(result).to eq({ absorbed: false, reason: :bot_generated })
      end

      it 'does not store payload in cache' do
        expect(Legion::Cache).not_to receive(:set)
        described_class.absorb(payload: bot_payload)
      end
    end

    context 'with an already-claimed issue (has fleet label)' do
      it 'returns absorbed: false with reason :already_claimed' do
        result = described_class.absorb(payload: labeled_payload)
        expect(result).to eq({ absorbed: false, reason: :already_claimed })
      end
    end

    context 'with an ignored action' do
      it 'returns absorbed: false with reason :ignored' do
        result = described_class.absorb(payload: closed_payload)
        expect(result).to eq({ absorbed: false, reason: :ignored })
      end
    end

    context 'dedup boundary' do
      it 'does NOT call set_nx (dedup is the assessor responsibility, not the absorber)' do
        expect(Legion::Cache).not_to receive(:set_nx)
        described_class.absorb(payload: opened_payload)
      end
    end
  end

  describe '.normalize' do
    subject(:work_item) { described_class.normalize(opened_payload) }

    it 'sets source to github' do
      expect(work_item[:source]).to eq('github')
    end

    it 'sets source_ref as owner/repo#number' do
      expect(work_item[:source_ref]).to eq('LegionIO/lex-exec#42')
    end

    it 'sets source_event to issues.opened' do
      expect(work_item[:source_event]).to eq('issues.opened')
    end

    it 'sets title from issue' do
      expect(work_item[:title]).to eq('Fix sandbox timeout on macOS')
    end

    it 'sets description from issue body' do
      expect(work_item[:description]).to include('exec sandbox times out')
    end

    it 'truncates description to 32KB (configurable via fleet.work_item.description_max_bytes)' do
      long_body = 'x' * 50_000
      payload = opened_payload.merge(
        'issue' => opened_payload['issue'].merge('body' => long_body)
      )
      item = described_class.normalize(payload)
      expect(item[:description].length).to be <= 32_768
    end

    it 'populates repo context' do
      expect(work_item[:repo]).to eq({
                                       owner:          'LegionIO',
                                       name:           'lex-exec',
                                       default_branch: 'main',
                                       language:       'Ruby'
                                     })
    end

    it 'sets pipeline.stage to intake' do
      expect(work_item[:pipeline][:stage]).to eq('intake')
    end

    it 'initializes pipeline.attempt to 0' do
      expect(work_item[:pipeline][:attempt]).to eq(0)
    end

    it 'initializes pipeline.trace as empty array' do
      expect(work_item[:pipeline][:trace]).to eq([])
    end

    it 'initializes pipeline.feedback_history as empty array' do
      expect(work_item[:pipeline][:feedback_history]).to eq([])
    end

    it 'has a config section with defaults' do
      expect(work_item[:config]).to be_a(Hash)
      expect(work_item[:config][:priority]).to eq(:medium)
    end

    it 'generates a UUID work_item_id' do
      expect(work_item[:work_item_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'populates instructions as empty array' do
      expect(work_item[:instructions]).to eq([])
    end

    it 'populates context as empty array' do
      expect(work_item[:context]).to eq([])
    end
  end
end
