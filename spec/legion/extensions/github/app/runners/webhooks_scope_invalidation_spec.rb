# frozen_string_literal: true

RSpec.describe 'Webhook scope invalidation' do
  let(:runner) { Object.new.extend(Legion::Extensions::Github::App::Runners::Webhooks) }

  before do
    allow(runner).to receive(:cache_connected?).and_return(true)
    allow(runner).to receive(:local_cache_connected?).and_return(true)
    allow(runner).to receive(:cache_delete)
    allow(runner).to receive(:local_cache_delete)
  end

  describe '#invalidate_scopes_for_event' do
    it 'invalidates org scope on installation.created' do
      payload = {
        'action'       => 'created',
        'installation' => {
          'id'      => 12_345,
          'account' => { 'login' => 'OrgZ', 'type' => 'Organization' }
        }
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation', payload: payload)
    end

    it 'invalidates org scope on installation.deleted' do
      payload = {
        'action'       => 'deleted',
        'installation' => {
          'id'      => 12_345,
          'account' => { 'login' => 'OrgZ', 'type' => 'Organization' }
        }
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation', payload: payload)
    end

    it 'invalidates repo scopes on installation_repositories.added' do
      payload = {
        'action'             => 'added',
        'installation'       => {
          'id'      => 12_345,
          'account' => { 'login' => 'OrgZ' }
        },
        'repositories_added' => [
          { 'full_name' => 'OrgZ/repo1' },
          { 'full_name' => 'OrgZ/repo2' }
        ]
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation_repositories', payload: payload)
    end

    it 'invalidates repo scopes on installation_repositories.removed' do
      payload = {
        'action'               => 'removed',
        'installation'         => {
          'id'      => 12_345,
          'account' => { 'login' => 'OrgZ' }
        },
        'repositories_removed' => [
          { 'full_name' => 'OrgZ/repo1' }
        ]
      }
      expect(runner).to receive(:invalidate_all_scopes_for_owner).with(owner: 'OrgZ')
      runner.invalidate_scopes_for_event(event_type: 'installation_repositories', payload: payload)
    end

    it 'does nothing for unrelated events' do
      expect(runner).not_to receive(:invalidate_all_scopes_for_owner)
      runner.invalidate_scopes_for_event(event_type: 'push', payload: { 'ref' => 'refs/heads/main' })
    end
  end
end
