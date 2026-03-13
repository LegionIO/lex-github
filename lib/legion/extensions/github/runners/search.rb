# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Search
          include Legion::Extensions::Github::Helpers::Client

          def search_repositories(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            response = connection(**).get('/search/repositories', params)
            { result: response.body }
          end

          def search_issues(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            response = connection(**).get('/search/issues', params)
            { result: response.body }
          end

          def search_users(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            response = connection(**).get('/search/users', params)
            { result: response.body }
          end

          def search_code(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            response = connection(**).get('/search/code', params)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
