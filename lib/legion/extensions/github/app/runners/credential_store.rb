# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module CredentialStore
            def store_app_credentials(app_id:, private_key:, client_id:, client_secret:, webhook_secret:, **)
              vault_set('github/app/app_id', app_id)
              vault_set('github/app/private_key', private_key)
              vault_set('github/app/client_id', client_id)
              vault_set('github/app/client_secret', client_secret)
              vault_set('github/app/webhook_secret', webhook_secret)
              { result: true }
            end

            def store_oauth_token(user:, access_token:, refresh_token:, expires_in: nil, scope: nil, **)
              data = { 'access_token' => access_token, 'refresh_token' => refresh_token,
                       'expires_in' => expires_in, 'scope' => scope,
                       'stored_at' => Time.now.iso8601 }.compact
              vault_set("github/oauth/#{user}/token", data)
              { result: true }
            end

            def load_oauth_token(user:, **)
              data = begin
                vault_get("github/oauth/#{user}/token")
              rescue StandardError
                nil
              end
              { result: data }
            end
          end
        end
      end
    end
  end
end
