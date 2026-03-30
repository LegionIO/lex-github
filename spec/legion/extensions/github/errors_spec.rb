# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github::RateLimitError do
  it 'stores reset_at timestamp' do
    reset_at = Time.now + 300
    error = described_class.new('rate limited', reset_at: reset_at)
    expect(error.reset_at).to eq(reset_at)
    expect(error.message).to eq('rate limited')
  end

  it 'stores credential_fingerprint' do
    error = described_class.new('rate limited', reset_at: Time.now, credential_fingerprint: 'fp1')
    expect(error.credential_fingerprint).to eq('fp1')
  end
end

RSpec.describe Legion::Extensions::Github::AuthorizationError do
  it 'stores owner and repo context' do
    error = described_class.new('no credential for OrgZ/repo1', owner: 'OrgZ', repo: 'repo1')
    expect(error.owner).to eq('OrgZ')
    expect(error.repo).to eq('repo1')
    expect(error.message).to eq('no credential for OrgZ/repo1')
  end

  it 'stores attempted_sources list' do
    error = described_class.new('exhausted', owner:             'OrgZ',
                                             attempted_sources: %i[oauth_user app_installation pat])
    expect(error.attempted_sources).to eq(%i[oauth_user app_installation pat])
  end
end

RSpec.describe Legion::Extensions::Github::ScopeDeniedError do
  it 'stores credential and scope context' do
    error = described_class.new('forbidden', owner: 'OrgZ', repo: 'repo1',
                                             credential_fingerprint: 'fp1', auth_type: :oauth_user)
    expect(error.owner).to eq('OrgZ')
    expect(error.credential_fingerprint).to eq('fp1')
    expect(error.auth_type).to eq(:oauth_user)
  end
end
