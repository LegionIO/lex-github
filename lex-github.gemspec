# frozen_string_literal: true

require_relative 'lib/legion/extensions/github/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-github'
  spec.version       = Legion::Extensions::Github::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']

  spec.summary       = 'LEX Github'
  spec.description   = 'Connects LegionIO to GitHub'
  spec.homepage      = 'https://github.com/LegionIO/lex-github'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/LegionIO/lex-github'
  spec.metadata['documentation_uri'] = 'https://github.com/LegionIO/lex-github'
  spec.metadata['changelog_uri'] = 'https://github.com/LegionIO/lex-github'
  spec.metadata['bug_tracker_uri'] = 'https://github.com/LegionIO/lex-github/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.require_paths = ['lib']

  spec.add_dependency 'base64', '>= 0.1'
  spec.add_dependency 'faraday', '>= 2.0'
  spec.add_dependency 'jwt', '~> 2.7'
  spec.add_dependency 'legion-cache',     '>= 1.3.11'
  spec.add_dependency 'legion-crypt',     '>= 1.4.9'
  spec.add_dependency 'legion-data',      '>= 1.4.17'
  spec.add_dependency 'legion-json',      '>= 1.2.1'
  spec.add_dependency 'legion-logging',   '>= 1.3.2'
  spec.add_dependency 'legion-settings',  '>= 1.3.14'
  spec.add_dependency 'legion-transport', '>= 1.3.9'
end
