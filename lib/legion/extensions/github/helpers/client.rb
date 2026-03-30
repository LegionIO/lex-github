# frozen_string_literal: true

require 'faraday'
require 'legion/extensions/github/helpers/token_cache'
require 'legion/extensions/github/helpers/scope_registry'

module Legion
  module Extensions
    module Github
      module Helpers
        module Client
          include TokenCache
          include ScopeRegistry

          CREDENTIAL_RESOLVERS = %i[
            resolve_vault_delegated resolve_settings_delegated
            resolve_vault_app resolve_settings_app
            resolve_vault_pat resolve_settings_pat
            resolve_gh_cli resolve_env
          ].freeze

          def connection(owner: nil, repo: nil, api_url: 'https://api.github.com', token: nil, **_opts)
            resolved_token = token || resolve_credential(owner: owner, repo: repo)&.dig(:token)
            Faraday.new(url: api_url) do |conn|
              conn.request :json
              conn.response :json, content_type: /\bjson$/
              conn.headers['Accept'] = 'application/vnd.github+json'
              conn.headers['Authorization'] = "Bearer #{resolved_token}" if resolved_token
              conn.headers['X-GitHub-Api-Version'] = '2022-11-28'
            end
          end

          def resolve_credential(owner: nil, repo: nil)
            CREDENTIAL_RESOLVERS.each do |method|
              next unless respond_to?(method, true)

              result = send(method)
              next unless result

              fingerprint = result.dig(:metadata, :credential_fingerprint)

              next if fingerprint && rate_limited?(fingerprint: fingerprint)

              if owner && fingerprint
                scope = scope_status(fingerprint: fingerprint, owner: owner, repo: repo)
                next if scope == :denied
              end

              return result
            end
            nil
          end

          def resolve_vault_delegated
            return nil unless defined?(Legion::Crypt)

            token_data = vault_get('github/oauth/delegated/token')
            return nil unless token_data&.dig('access_token')

            fp = credential_fingerprint(auth_type: :oauth_user, identifier: 'vault_delegated')
            { token: token_data['access_token'], auth_type: :oauth_user,
              expires_at: token_data['expires_at'],
              metadata: { source: :vault, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_settings_delegated
            return nil unless defined?(Legion::Settings)

            token = Legion::Settings.dig(:github, :oauth, :access_token)
            return nil unless token

            fp = credential_fingerprint(auth_type: :oauth_user, identifier: 'settings_delegated')
            { token: token, auth_type: :oauth_user,
              metadata: { source: :settings, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_vault_app
            return nil unless defined?(Legion::Crypt)

            key_data = vault_get('github/app/private_key')
            return nil unless key_data

            app_id = vault_get('github/app/app_id')
            installation_id = vault_get('github/app/installation_id')
            return nil unless app_id && installation_id

            fp = credential_fingerprint(auth_type: :app_installation, identifier: "vault_app_#{app_id}")
            cached = fetch_token(auth_type: :app_installation)
            return cached.merge(metadata: { source: :vault, credential_fingerprint: fp }) if cached

            nil
          rescue StandardError
            nil
          end

          def resolve_settings_app
            return nil unless defined?(Legion::Settings)

            app_id = Legion::Settings.dig(:github, :app, :app_id)
            return nil unless app_id

            fp = credential_fingerprint(auth_type: :app_installation, identifier: "settings_app_#{app_id}")
            cached = fetch_token(auth_type: :app_installation)
            return cached.merge(metadata: { source: :settings, credential_fingerprint: fp }) if cached

            nil
          rescue StandardError
            nil
          end

          def resolve_vault_pat
            return nil unless defined?(Legion::Crypt)

            token = vault_get('github/token')
            return nil unless token

            fp = credential_fingerprint(auth_type: :pat, identifier: 'vault_pat')
            { token: token, auth_type: :pat, metadata: { source: :vault, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_settings_pat
            return nil unless defined?(Legion::Settings)

            token = Legion::Settings.dig(:github, :token)
            return nil unless token

            fp = credential_fingerprint(auth_type: :pat, identifier: 'settings_pat')
            { token: token, auth_type: :pat, metadata: { source: :settings, credential_fingerprint: fp } }
          rescue StandardError
            nil
          end

          def resolve_gh_cli
            if cache_connected? || local_cache_connected?
              cached = cache_connected? ? cache_get('github:cli_token') : local_cache_get('github:cli_token')
              return cached if cached
            end

            output = gh_cli_token_output
            return nil unless output

            fp = credential_fingerprint(auth_type: :cli, identifier: 'gh_cli')
            result = { token: output, auth_type: :cli, metadata: { source: :gh_cli, credential_fingerprint: fp } }
            cache_set('github:cli_token', result, ttl: 300) if cache_connected?
            local_cache_set('github:cli_token', result, ttl: 300) if local_cache_connected?
            result
          rescue StandardError
            nil
          end

          def gh_cli_token_output
            output = `gh auth token 2>/dev/null`.strip
            return nil unless $CHILD_STATUS&.success? && !output.empty?

            output
          rescue StandardError
            nil
          end

          def resolve_env
            token = ENV['GITHUB_TOKEN']
            return nil if token.nil? || token.empty?

            fp = credential_fingerprint(auth_type: :env, identifier: 'env')
            { token: token, auth_type: :env, metadata: { source: :env, credential_fingerprint: fp } }
          end

          private

          def credential_fallback?
            return true unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :credential_fallback) != false
          rescue StandardError
            true
          end
        end
      end
    end
  end
end
