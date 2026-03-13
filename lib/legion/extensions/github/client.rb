# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/runners/repositories'
require 'legion/extensions/github/runners/issues'
require 'legion/extensions/github/runners/pull_requests'
require 'legion/extensions/github/runners/users'
require 'legion/extensions/github/runners/organizations'
require 'legion/extensions/github/runners/gists'
require 'legion/extensions/github/runners/search'

module Legion
  module Extensions
    module Github
      class Client
        include Helpers::Client
        include Runners::Repositories
        include Runners::Issues
        include Runners::PullRequests
        include Runners::Users
        include Runners::Organizations
        include Runners::Gists
        include Runners::Search

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
