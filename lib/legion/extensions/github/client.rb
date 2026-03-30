# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'
require 'legion/extensions/github/runners/repositories'
require 'legion/extensions/github/runners/issues'
require 'legion/extensions/github/runners/pull_requests'
require 'legion/extensions/github/runners/users'
require 'legion/extensions/github/runners/organizations'
require 'legion/extensions/github/runners/gists'
require 'legion/extensions/github/runners/search'
require 'legion/extensions/github/runners/commits'
require 'legion/extensions/github/runners/labels'
require 'legion/extensions/github/runners/comments'
require 'legion/extensions/github/runners/branches'
require 'legion/extensions/github/runners/contents'
require 'legion/extensions/github/app/runners/auth'
require 'legion/extensions/github/app/runners/webhooks'
require 'legion/extensions/github/app/runners/manifest'
require 'legion/extensions/github/app/runners/installations'
require 'legion/extensions/github/app/runners/credential_store'
require 'legion/extensions/github/oauth/runners/auth'

module Legion
  module Extensions
    module Github
      class Client
        include Helpers::Client
        include Helpers::Cache
        include Runners::Repositories
        include Runners::Issues
        include Runners::PullRequests
        include Runners::Users
        include Runners::Organizations
        include Runners::Gists
        include Runners::Search
        include Runners::Commits
        include Runners::Labels
        include Runners::Comments
        include Runners::Branches
        include Runners::Contents
        include App::Runners::Auth
        include App::Runners::Webhooks
        include App::Runners::Manifest
        include App::Runners::Installations
        include App::Runners::CredentialStore
        include OAuth::Runners::Auth

        attr_reader :opts

        def initialize(token: nil, api_url: 'https://api.github.com', **extra)
          @opts = { token: token, api_url: api_url, **extra }
        end

        def connection(**override)
          super(**@opts.merge(override))
        end
      end
    end
  end
end
