# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Commits
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_commits(owner:, repo:, sha: nil, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            params[:sha] = sha if sha
            { result: cached_get("github:repo:#{owner}/#{repo}:commits:#{page}") { connection(**).get("/repos/#{owner}/#{repo}/commits", params).body } }
          end

          def get_commit(owner:, repo:, ref:, **)
            { result: cached_get("github:repo:#{owner}/#{repo}:commits:#{ref}") { connection(**).get("/repos/#{owner}/#{repo}/commits/#{ref}").body } }
          end

          def compare_commits(owner:, repo:, base:, head:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:commits:compare:#{base}...#{head}:#{page}") { connection(**).get("/repos/#{owner}/#{repo}/compare/#{base}...#{head}", params).body } }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
