# frozen_string_literal: true

require 'faraday'
require 'legion/extensions/github/helpers/token_cache'
require 'legion/extensions/github/helpers/scope_registry'
require 'legion/extensions/github/middleware/credential_fallback'

module Legion
  module Extensions
    module Github
      module Helpers
        module Client
          include TokenCache
          include ScopeRegistry

          CREDENTIAL_RESOLVERS = %i[
            resolve_vault_delegated resolve_settings_delegated
            resolve_broker_app
            resolve_vault_app resolve_settings_app
            resolve_vault_pat resolve_settings_pat
            resolve_gh_cli resolve_env
          ].freeze

          def connection(owner: nil, repo: nil, api_url: 'https://api.github.com', token: nil, **_opts)
            resolved = token ? { token: token } : resolve_credential(owner: owner, repo: repo)
            resolved_token = resolved&.dig(:token)
            @current_credential = resolved
            @skipped_fingerprints = []

            Faraday.new(url: api_url) do |conn|
              conn.use :github_credential_fallback, resolver: self
              conn.request :json
              conn.response :json, content_type: /\bjson$/
              conn.response :github_rate_limit, handler: self
              conn.response :github_scope_probe, handler: self
              conn.headers['Accept'] = 'application/vnd.github+json'
              conn.headers['Authorization'] = "Bearer #{resolved_token}" if resolved_token
              conn.headers['X-GitHub-Api-Version'] = '2022-11-28'
            end
          end

          def resolve_next_credential(owner: nil, repo: nil)
            fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
            @skipped_fingerprints ||= []
            @skipped_fingerprints << fingerprint if fingerprint

            CREDENTIAL_RESOLVERS.each do |method|
              next unless respond_to?(method, true)

              result = send(method)
              next unless result

              fp = result.dig(:metadata, :credential_fingerprint)
              next if fp && @skipped_fingerprints.include?(fp)
              next if fp && rate_limited?(fingerprint: fp)

              if owner && fp
                scope = scope_status(fingerprint: fp, owner: owner, repo: repo)
                next if scope == :denied
              end

              @current_credential = result
              return result
            end
            nil
          end

          def max_fallback_retries
            CREDENTIAL_RESOLVERS.size
          end

          def on_rate_limit(remaining:, reset_at:, status:, url:, **) # rubocop:disable Lint/UnusedMethodArgument
            fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
            return unless fingerprint

            mark_rate_limited(fingerprint: fingerprint, reset_at: reset_at)
          end

          def on_scope_denied(status:, url:, path:, **) # rubocop:disable Lint/UnusedMethodArgument
            fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
            owner, repo = extract_owner_repo(path)
            return unless fingerprint && owner

            register_scope(fingerprint: fingerprint, owner: owner, repo: repo, status: :denied)
          end

          def on_scope_authorized(status:, url:, path:, **) # rubocop:disable Lint/UnusedMethodArgument
            fingerprint = @current_credential&.dig(:metadata, :credential_fingerprint)
            owner, repo = extract_owner_repo(path)
            return unless fingerprint && owner

            register_scope(fingerprint: fingerprint, owner: owner, repo: repo, status: :authorized)
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
          rescue StandardError => _e
            nil
          end

          def resolve_settings_delegated
            return nil unless defined?(Legion::Settings)

            token = Legion::Settings.dig(:github, :oauth, :access_token)
            return nil unless token

            fp = credential_fingerprint(auth_type: :oauth_user, identifier: 'settings_delegated')
            { token: token, auth_type: :oauth_user,
              metadata: { source: :settings, credential_fingerprint: fp } }
          rescue StandardError => _e
            nil
          end

          def resolve_broker_app
            return nil unless defined?(Legion::Identity::Broker)

            token = Legion::Identity::Broker.token_for(:github)
            return nil unless token

            lease = Legion::Identity::Broker.lease_for(:github)
            installation_id = lease&.metadata&.dig(:installation_id) || 'unknown'
            fp = credential_fingerprint(auth_type:  :app_installation,
                                        identifier: "broker_app_#{installation_id}")
            { token: token, auth_type: :app_installation,
              metadata: { source: :broker, credential_type: :installation_token,
                          credential_fingerprint: fp } }
          rescue StandardError => _e
            nil
          end

          def resolve_vault_app
            return nil unless defined?(Legion::Crypt)

            private_key = begin
              vault_get('github/app/private_key')
            rescue StandardError => _e
              nil
            end
            return nil unless private_key

            app_id = begin
              vault_get('github/app/app_id')
            rescue StandardError => _e
              nil
            end
            installation_id = begin
              vault_get('github/app/installation_id')
            rescue StandardError => _e
              nil
            end
            return nil unless app_id && installation_id

            fp = credential_fingerprint(auth_type: :app_installation, identifier: "vault_app_#{app_id}")
            cached = fetch_token(auth_type: :app_installation, installation_id: installation_id)
            return cached.merge(metadata: { source: :vault, credential_fingerprint: fp }) if cached

            jwt = generate_jwt(app_id: app_id, private_key: private_key)[:result]
            token_data = create_installation_token(jwt: jwt, installation_id: installation_id)[:result]
            return nil unless token_data&.dig('token')

            expires_at = begin
              Time.parse(token_data['expires_at'])
            rescue StandardError => _e
              Time.now + 3600
            end
            result = { token: token_data['token'], auth_type: :app_installation,
                       expires_at: expires_at, installation_id: installation_id,
                       metadata: { source: :vault, installation_id: installation_id,
                                   credential_fingerprint: fp } }
            store_token(**result)
            result
          rescue StandardError => _e
            nil
          end

          def resolve_settings_app
            return nil unless defined?(Legion::Settings)

            app_id = begin
              Legion::Settings.dig(:github, :app, :app_id)
            rescue StandardError => _e
              nil
            end
            return nil unless app_id

            fp = credential_fingerprint(auth_type: :app_installation, identifier: "settings_app_#{app_id}")

            key_path = begin
              Legion::Settings.dig(:github, :app, :private_key_path)
            rescue StandardError => _e
              nil
            end
            installation_id = begin
              Legion::Settings.dig(:github, :app, :installation_id)
            rescue StandardError => _e
              nil
            end
            return nil unless key_path && installation_id

            cached = fetch_token(auth_type: :app_installation, installation_id: installation_id)
            return cached.merge(metadata: { source: :settings, credential_fingerprint: fp }) if cached

            private_key = ::File.read(key_path)
            jwt = generate_jwt(app_id: app_id, private_key: private_key)[:result]
            token_data = create_installation_token(jwt: jwt, installation_id: installation_id)[:result]
            return nil unless token_data&.dig('token')

            expires_at = begin
              Time.parse(token_data['expires_at'])
            rescue StandardError => _e
              Time.now + 3600
            end
            result = { token: token_data['token'], auth_type: :app_installation,
                       expires_at: expires_at, installation_id: installation_id,
                       metadata: { source: :settings, installation_id: installation_id,
                                   credential_fingerprint: fp } }
            store_token(**result)
            result
          rescue StandardError => _e
            nil
          end

          def resolve_vault_pat
            return nil unless defined?(Legion::Crypt)

            token = vault_get('github/token')
            return nil unless token

            fp = credential_fingerprint(auth_type: :pat, identifier: 'vault_pat')
            { token: token, auth_type: :pat, metadata: { source: :vault, credential_fingerprint: fp } }
          rescue StandardError => _e
            nil
          end

          def resolve_settings_pat
            return nil unless defined?(Legion::Settings)

            token = Legion::Settings.dig(:github, :token)
            return nil unless token

            fp = credential_fingerprint(auth_type: :pat, identifier: 'settings_pat')
            { token: token, auth_type: :pat, metadata: { source: :settings, credential_fingerprint: fp } }
          rescue StandardError => _e
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
          rescue StandardError => _e
            nil
          end

          def gh_cli_token_output
            output = `gh auth token 2>/dev/null`.strip
            return nil unless $?&.success? && !output.empty? # rubocop:disable Style/SpecialGlobalVars

            output
          rescue StandardError => _e
            nil
          end

          def resolve_env
            token = ENV.fetch('GITHUB_TOKEN', nil)
            return nil if token.nil? || token.empty?

            fp = credential_fingerprint(auth_type: :env, identifier: 'env')
            { token: token, auth_type: :env, metadata: { source: :env, credential_fingerprint: fp } }
          end

          private

          def extract_owner_repo(path)
            match = path.match(%r{^/repos/([^/]+)/([^/]+)})
            return [nil, nil] unless match

            [match[1], match[2]]
          end

          def credential_fallback?
            return true unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :credential_fallback) != false
          rescue StandardError => _e
            true
          end
        end
      end
    end
  end
end
