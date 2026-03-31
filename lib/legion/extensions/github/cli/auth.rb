# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/browser_auth'

module Legion
  module Extensions
    module Github
      module CLI
        module Auth
          include Helpers::Client

          def login(client_id: nil, client_secret: nil, scopes: nil, **)
            cid = client_id || settings_client_id
            csec = client_secret || settings_client_secret
            sc = scopes || settings_scopes

            unless cid
              return { error:       'missing_config',
                       description: 'Set github.oauth.client_id or github.app.client_id in settings' }
            end

            browser = Helpers::BrowserAuth.new(client_id: cid, client_secret: csec, scopes: sc)
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
              user_info = {}
              scopes = nil
            end

            { result: { authenticated: true, auth_type: cred[:auth_type],
                        user: user_info['login'], scopes: scopes } }
          end

          private

          def current_user(token:)
            connection(token: token).get('/user').body['login']
          end

          def settings_client_id
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :oauth, :client_id) ||
              Legion::Settings.dig(:github, :app, :client_id)
          rescue StandardError => _e
            nil
          end

          def settings_client_secret
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :app, :client_secret)
          rescue StandardError => _e
            nil
          end

          def settings_scopes
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :oauth, :scopes)
          rescue StandardError => _e
            nil
          end
        end
      end
    end
  end
end
