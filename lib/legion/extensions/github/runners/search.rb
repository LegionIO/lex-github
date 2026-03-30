# frozen_string_literal: true

require 'digest'
require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Search
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def search_repositories(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            cache_key = "github:search:repositories:#{Digest::MD5.hexdigest(params.sort.to_s)}"
            { result: cached_get(cache_key) { connection(**).get('/search/repositories', params).body } }
          end

          def search_issues(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            cache_key = "github:search:issues:#{Digest::MD5.hexdigest(params.sort.to_s)}"
            { result: cached_get(cache_key) { connection(**).get('/search/issues', params).body } }
          end

          def search_users(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            cache_key = "github:search:users:#{Digest::MD5.hexdigest(params.sort.to_s)}"
            { result: cached_get(cache_key) { connection(**).get('/search/users', params).body } }
          end

          def search_code(query:, sort: nil, order: 'desc', per_page: 30, page: 1, **)
            params = { q: query, sort: sort, order: order, per_page: per_page, page: page }.compact
            cache_key = "github:search:code:#{Digest::MD5.hexdigest(params.sort.to_s)}"
            { result: cached_get(cache_key) { connection(**).get('/search/code', params).body } }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
