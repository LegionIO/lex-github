# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/browser_auth'
require 'legion/extensions/github/app/runners/auth'
require 'legion/extensions/github/app/runners/credential_store'
require 'legion/extensions/github/oauth/runners/auth'

module Legion
  module Extensions
    module Github
      module Runners
        module Auth
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::App::Runners::Auth
          include Legion::Extensions::Github::App::Runners::CredentialStore
          include Legion::Extensions::Github::OAuth::Runners::Auth

          def self.remote_invocable?
            false
          end

          def status(**)
            cred = resolve_credential
            return { result: { authenticated: false } } unless cred

            user_info = {}
            scopes = nil
            begin
              response = connection(token: cred[:token]).get('/user')
              user_info = response.body || {}
              headers = response.respond_to?(:headers) ? response.headers : {}
              scopes_header = headers['X-OAuth-Scopes'] || headers['x-oauth-scopes']
              scopes = scopes_header&.split(',')&.map(&:strip)
            rescue StandardError => _e
              # token may be invalid
            end

            { result: { authenticated: true, auth_type: cred[:auth_type],
                        user: user_info['login'], scopes: scopes } }
          end

          def login(client_id: nil, scopes: nil, **)
            cid = client_id || settings_client_id
            return { error: 'missing_config', description: 'Set github.app.client_id in settings' } unless cid

            sc = scopes || settings_scopes
            browser = Helpers::BrowserAuth.new(client_id: cid, scopes: sc)
            result = browser.authenticate

            if result[:result]&.dig('access_token') && respond_to?(:store_oauth_token, true)
              user = begin
                current_user(token: result[:result]['access_token'])
              rescue StandardError => _e
                'default'
              end
              store_oauth_token(
                user:          user,
                access_token:  result[:result]['access_token'],
                refresh_token: result[:result]['refresh_token'],
                expires_in:    result[:result]['expires_in']
              )
            end

            result
          end

          def installations(**)
            list_installations(**)
          end

          private

          def current_user(token:)
            connection(token: token).get('/user').body['login']
          end

          def settings_client_id
            defined?(Legion::Settings) &&
              (Legion::Settings.dig(:github, :oauth, :client_id) ||
               Legion::Settings.dig(:github, :app, :client_id))
          rescue StandardError => _e
            nil
          end

          def settings_scopes
            defined?(Legion::Settings) && Legion::Settings.dig(:github, :oauth, :scopes)
          rescue StandardError => _e
            nil
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
