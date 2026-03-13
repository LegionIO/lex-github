# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Organizations
          include Legion::Extensions::Github::Helpers::Client

          def list_user_orgs(username:, per_page: 30, page: 1, **)
            response = connection(**).get("/users/#{username}/orgs", per_page: per_page, page: page)
            { result: response.body }
          end

          def get_org(org:, **)
            response = connection(**).get("/orgs/#{org}")
            { result: response.body }
          end

          def list_org_repos(org:, type: 'all', per_page: 30, page: 1, **)
            params = { type: type, per_page: per_page, page: page }
            response = connection(**).get("/orgs/#{org}/repos", params)
            { result: response.body }
          end

          def list_org_members(org:, per_page: 30, page: 1, **)
            response = connection(**).get("/orgs/#{org}/members", per_page: per_page, page: page)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
