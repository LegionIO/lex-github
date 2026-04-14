# spec/absorbers/helpers_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Minimal stubs for isolated testing
module Legion
  unless defined?(Legion::Cache)
    module Cache
      def self.get(key); end
      def self.set(key, value, ttl: nil); end
    end
  end
end

require 'legion/extensions/github/absorbers/helpers'

RSpec.describe Legion::Extensions::Github::Absorbers::Helpers do
  let(:test_class) { Class.new { include Legion::Extensions::Github::Absorbers::Helpers } }
  let(:instance) { test_class.new }

  describe '#bot_generated?' do
    it 'returns true for events from [bot] users' do
      payload = { 'sender' => { 'login' => 'dependabot[bot]', 'type' => 'Bot' } }
      expect(instance.bot_generated?(payload)).to be true
    end

    it 'returns true for events from users with type Bot' do
      payload = { 'sender' => { 'login' => 'renovate', 'type' => 'Bot' } }
      expect(instance.bot_generated?(payload)).to be true
    end

    it 'returns false for human users' do
      payload = { 'sender' => { 'login' => 'matt-iverson', 'type' => 'User' } }
      expect(instance.bot_generated?(payload)).to be false
    end

    it 'returns false for missing sender' do
      payload = {}
      expect(instance.bot_generated?(payload)).to be false
    end

    it 'returns true for known bot patterns' do
      %w[github-actions[bot] codecov[bot] snyk-bot legion-fleet[bot]].each do |login|
        payload = { 'sender' => { 'login' => login, 'type' => 'Bot' } }
        expect(instance.bot_generated?(payload)).to be(true), "Expected #{login} to be detected as bot"
      end
    end
  end

  describe '#has_fleet_label?' do
    it 'returns true when issue has fleet:received label' do
      payload = { 'issue' => { 'labels' => [{ 'name' => 'fleet:received' }] } }
      expect(instance.has_fleet_label?(payload)).to be true
    end

    it 'returns true when issue has fleet:implementing label' do
      payload = { 'issue' => { 'labels' => [{ 'name' => 'fleet:implementing' }] } }
      expect(instance.has_fleet_label?(payload)).to be true
    end

    it 'returns true when issue has fleet:pr-open label' do
      payload = { 'issue' => { 'labels' => [{ 'name' => 'fleet:pr-open' }] } }
      expect(instance.has_fleet_label?(payload)).to be true
    end

    it 'returns true when issue has fleet:escalated label' do
      payload = { 'issue' => { 'labels' => [{ 'name' => 'fleet:escalated' }] } }
      expect(instance.has_fleet_label?(payload)).to be true
    end

    it 'returns false when issue has no fleet labels' do
      payload = { 'issue' => { 'labels' => [{ 'name' => 'bug' }, { 'name' => 'help wanted' }] } }
      expect(instance.has_fleet_label?(payload)).to be false
    end

    it 'returns false when issue has no labels' do
      payload = { 'issue' => { 'labels' => [] } }
      expect(instance.has_fleet_label?(payload)).to be false
    end
  end

  describe '#ignored?' do
    it 'returns true for closed events' do
      payload = { 'action' => 'closed' }
      expect(instance.ignored?(payload)).to be true
    end

    it 'returns true for transferred events' do
      payload = { 'action' => 'transferred' }
      expect(instance.ignored?(payload)).to be true
    end

    it 'returns true for deleted events' do
      payload = { 'action' => 'deleted' }
      expect(instance.ignored?(payload)).to be true
    end

    it 'returns false for opened events' do
      payload = { 'action' => 'opened' }
      expect(instance.ignored?(payload)).to be false
    end

    it 'returns false for labeled events' do
      payload = { 'action' => 'labeled' }
      expect(instance.ignored?(payload)).to be false
    end
  end

  describe '#work_item_fingerprint' do
    it 'returns a SHA256 hex digest' do
      result = instance.work_item_fingerprint(source: 'github', ref: 'LegionIO/lex-exec#42', title: 'Fix bug')
      expect(result).to match(/\A[a-f0-9]{64}\z/)
    end

    it 'returns different fingerprints for different inputs' do
      fp1 = instance.work_item_fingerprint(source: 'github', ref: 'repo#1', title: 'Fix A')
      fp2 = instance.work_item_fingerprint(source: 'github', ref: 'repo#2', title: 'Fix B')
      expect(fp1).not_to eq(fp2)
    end

    it 'returns same fingerprint for same inputs' do
      fp1 = instance.work_item_fingerprint(source: 'github', ref: 'repo#1', title: 'Fix A')
      fp2 = instance.work_item_fingerprint(source: 'github', ref: 'repo#1', title: 'Fix A')
      expect(fp1).to eq(fp2)
    end
  end

  describe '#generate_work_item_id' do
    it 'returns a UUID-formatted string' do
      expect(instance.generate_work_item_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'returns a unique value on each call' do
      expect(instance.generate_work_item_id).not_to eq(instance.generate_work_item_id)
    end
  end
end
