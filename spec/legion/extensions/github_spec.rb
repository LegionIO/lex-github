# frozen_string_literal: true

RSpec.describe Legion::Extensions::Github do
  it 'has a version number' do
    expect(Legion::Extensions::Github::VERSION).not_to be_nil
  end

  it 'defines the Client class' do
    expect(Legion::Extensions::Github::Client).to be_a(Class)
  end
end
