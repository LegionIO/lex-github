# spec/absorbers/actor_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Stub the actor base class for isolated testing
module Legion
  module Extensions
    unless defined?(Legion::Extensions::Actors::Subscription)
      module Actors
        class Subscription
          def self.pattern(_routing_key); end
          def initialize(**); end
        end
      end
    end
  end
end

require 'legion/extensions/github/absorbers/actor'

RSpec.describe Legion::Extensions::Github::Absorbers::IssuesActor do
  describe '#runner_class' do
    it 'returns the Issues absorber module' do
      expect(described_class.new.runner_class).to eq(Legion::Extensions::Github::Absorbers::Issues)
    end
  end

  describe '#runner_function' do
    it 'returns absorb' do
      expect(described_class.new.runner_function).to eq('absorb')
    end
  end

  describe '#use_runner?' do
    it 'returns false' do
      expect(described_class.new.use_runner?).to be false
    end
  end

  describe '#check_subtask?' do
    it 'returns false' do
      expect(described_class.new.check_subtask?).to be false
    end
  end

  describe '#generate_task?' do
    it 'returns false' do
      expect(described_class.new.generate_task?).to be false
    end
  end

  describe '#absorb' do
    let(:actor) { described_class.new }
    let(:payload) { { 'action' => 'opened', 'sender' => { 'login' => 'test', 'type' => 'User' } } }

    before do
      allow(Legion::Extensions::Github::Absorbers::Issues).to receive(:absorb)
        .and_return({ absorbed: true, work_item_id: 'test-uuid' })
    end

    it 'delegates to Issues.absorb with payload keyword' do
      expect(Legion::Extensions::Github::Absorbers::Issues).to receive(:absorb)
        .with(payload: payload)
      actor.absorb(payload: payload)
    end

    it 'returns the absorb result' do
      result = actor.absorb(payload: payload)
      expect(result[:absorbed]).to be true
    end
  end
end
