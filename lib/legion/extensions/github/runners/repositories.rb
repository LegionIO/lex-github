# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Repositories
          include Legion::Extensions::Github::Helpers::Client

          def list_repos(username:, per_page: 30, page: 1, **)
            response = connection(**).get("/users/#{username}/repos", per_page: per_page, page: page)
            { result: response.body }
          end

          def get_repo(owner:, repo:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}")
            { result: response.body }
          end

          def create_repo(name:, description: nil, private: false, **)
            body = { name: name, description: description, private: private }
            response = connection(**).post('/user/repos', body)
            { result: response.body }
          end

          def update_repo(owner:, repo:, **opts)
            body = opts.slice(:name, :description, :homepage, :private, :default_branch)
            response = connection(**opts).patch("/repos/#{owner}/#{repo}", body)
            { result: response.body }
          end

          def delete_repo(owner:, repo:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}")
            { result: response.status == 204 }
          end

          def list_branches(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/branches", per_page: per_page, page: page)
            { result: response.body }
          end

          def list_tags(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/tags", per_page: per_page, page: page)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
