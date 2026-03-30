# frozen_string_literal: true

require 'legion/extensions/github/version'
require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/app/runners/auth'
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
require 'legion/extensions/github/client'

module Legion
  module Extensions
    module Github
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core, false
    end
  end
end
