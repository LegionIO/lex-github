# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Repositories
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_repos(username:, per_page: 30, page: 1, **)
            { result: cached_get("github:user:#{username}:repos:#{page}:#{per_page}") { connection(**).get("/users/#{username}/repos", per_page: per_page, page: page).body } }
          end

          def get_repo(owner:, repo:, **)
            { result: cached_get("github:repo:#{owner}/#{repo}") { connection(**).get("/repos/#{owner}/#{repo}").body } }
          end

          def create_repo(name:, description: nil, private: false, **)
            body = { name: name, description: description, private: private }
            response = connection(**).post('/user/repos', body)
            cache_write("github:repo:#{response.body['full_name']}", response.body) if response.body['id']
            { result: response.body }
          end

          def update_repo(owner:, repo:, **opts)
            body = opts.slice(:name, :description, :homepage, :private, :default_branch)
            response = connection(**opts).patch("/repos/#{owner}/#{repo}", body)
            cache_write("github:repo:#{owner}/#{repo}", response.body) if response.body['id']
            { result: response.body }
          end

          def delete_repo(owner:, repo:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}")
            cache_invalidate("github:repo:#{owner}/#{repo}") if response.status == 204
            { result: response.status == 204 }
          end

          def list_branches(owner:, repo:, per_page: 30, page: 1, **)
            { result: cached_get("github:repo:#{owner}/#{repo}:branches:#{page}:#{per_page}") { connection(**).get("/repos/#{owner}/#{repo}/branches", per_page: per_page, page: page).body } }
          end

          def list_tags(owner:, repo:, per_page: 30, page: 1, **)
            { result: cached_get("github:repo:#{owner}/#{repo}:tags:#{page}:#{per_page}") { connection(**).get("/repos/#{owner}/#{repo}/tags", per_page: per_page, page: page).body } }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
