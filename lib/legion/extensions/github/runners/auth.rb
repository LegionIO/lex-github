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
            unless cred
              log.warn('[lex-github] auth status: no credential found across all sources')
              return { result: { authenticated: false } }
            end

            log.info("[lex-github] auth status: credential found via #{cred[:auth_type]}")

            user_info = {}
            scopes = nil
            begin
              response = connection(token: cred[:token]).get('/user')
              user_info = response.body || {}
              headers = response.respond_to?(:headers) ? response.headers : {}
              scopes_header = headers['X-OAuth-Scopes'] || headers['x-oauth-scopes']
              scopes = scopes_header&.split(',')&.map(&:strip)
              log.info("[lex-github] auth status: authenticated as #{user_info['login']} (#{cred[:auth_type]})")
            rescue StandardError => e
              log.warn("[lex-github] auth status: credential found but /user request failed: #{e.message}")
            end

            { result: { authenticated: true, auth_type: cred[:auth_type],
                        user: user_info['login'], scopes: scopes } }
          end

          def login(client_id: nil, scopes: nil, **)
            cid = client_id || settings_client_id
            unless cid
              log.error('[lex-github] auth login: no client_id configured — set github.app.client_id in settings')
              return { error: 'missing_config', description: 'Set github.app.client_id in settings' }
            end

            log.info("[lex-github] auth login: starting OAuth flow with client_id=#{cid[0..7]}...")

            sc = scopes || settings_scopes
            browser = Helpers::BrowserAuth.new(client_id: cid, scopes: sc)
            result = browser.authenticate

            if result[:error]
              log.error("[lex-github] auth login failed: #{result[:error]} — #{result[:description]}")
              return { result: nil, error: result[:error], description: result[:description] }
            end

            if result[:result]&.dig('access_token')
              user = begin
                current_user(token: result[:result]['access_token'])
              rescue StandardError => e
                log.warn("[lex-github] auth login: token obtained but /user lookup failed: #{e.message}")
                'default'
              end

              log.info("[lex-github] auth login: authenticated as #{user}")

              if respond_to?(:store_oauth_token, true)
                store_oauth_token(
                  user:          user,
                  access_token:  result[:result]['access_token'],
                  refresh_token: result[:result]['refresh_token'],
                  expires_in:    result[:result]['expires_in']
                )
                log.info("[lex-github] auth login: token stored for user=#{user}")
              else
                log.warn('[lex-github] auth login: store_oauth_token not available — token not persisted')
              end
            else
              log.warn('[lex-github] auth login: OAuth completed but no access_token in response')
            end

            result
          end

          def installations(**)
            log.info('[lex-github] listing app installations')
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
