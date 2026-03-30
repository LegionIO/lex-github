# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Organizations
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_user_orgs(username:, per_page: 30, page: 1, **)
            { result: cached_get("github:user:#{username}:orgs:#{page}:#{per_page}") { connection(**).get("/users/#{username}/orgs", per_page: per_page, page: page).body } }
          end

          def get_org(org:, **)
            { result: cached_get("github:org:#{org}") { connection(owner: org, **).get("/orgs/#{org}").body } }
          end

          def list_org_repos(org:, type: 'all', per_page: 30, page: 1, **)
            params = { type: type, per_page: per_page, page: page }
            { result: cached_get("github:org:#{org}:repos:#{page}") { connection(owner: org, **).get("/orgs/#{org}/repos", params).body } }
          end

          def list_org_members(org:, per_page: 30, page: 1, **)
            { result: cached_get("github:org:#{org}:members:#{page}") { connection(owner: org, **).get("/orgs/#{org}/members", per_page: per_page, page: page).body } }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
