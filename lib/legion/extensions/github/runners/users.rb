# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Users
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def get_authenticated_user(**)
            cred = resolve_credential
            fp = cred&.dig(:metadata, :credential_fingerprint) || 'anonymous'
            { result: cached_get("github:user:authenticated:#{fp}") { connection(**).get('/user').body } }
          end

          def get_user(username:, **)
            { result: cached_get("github:user:#{username}") { connection(**).get("/users/#{username}").body } }
          end

          def list_followers(username:, per_page: 30, page: 1, **)
            { result: cached_get("github:user:#{username}:followers:#{page}:#{per_page}") do
              connection(**).get("/users/#{username}/followers", per_page: per_page, page: page).body
            end }
          end

          def list_following(username:, per_page: 30, page: 1, **)
            { result: cached_get("github:user:#{username}:following:#{page}:#{per_page}") do
              connection(**).get("/users/#{username}/following", per_page: per_page, page: page).body
            end }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
