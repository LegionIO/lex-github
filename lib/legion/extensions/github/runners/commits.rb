# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Commits
          include Legion::Extensions::Github::Helpers::Client

          def list_commits(owner:, repo:, sha: nil, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            params[:sha] = sha if sha
            response = connection(**).get("/repos/#{owner}/#{repo}/commits", params)
            { result: response.body }
          end

          def get_commit(owner:, repo:, ref:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/commits/#{ref}")
            { result: response.body }
          end

          def compare_commits(owner:, repo:, base:, head:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/compare/#{base}...#{head}", params)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
