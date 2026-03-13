# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Users
          include Legion::Extensions::Github::Helpers::Client

          def get_authenticated_user(**opts)
            response = connection(**opts).get('/user')
            { result: response.body }
          end

          def get_user(username:, **opts)
            response = connection(**opts).get("/users/#{username}")
            { result: response.body }
          end

          def list_followers(username:, per_page: 30, page: 1, **opts)
            response = connection(**opts).get("/users/#{username}/followers", per_page: per_page, page: page)
            { result: response.body }
          end

          def list_following(username:, per_page: 30, page: 1, **opts)
            response = connection(**opts).get("/users/#{username}/following", per_page: per_page, page: page)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
