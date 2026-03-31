# frozen_string_literal: true

require 'json'
require 'legion/extensions/github/cli/auth'
require 'legion/extensions/github/cli/app'
require 'legion/extensions/github/app/runners/credential_store'

module Legion
  module Extensions
    module Github
      module CLI
        module RunnerOutput
          private

          def print_result(result)
            if result.is_a?(Hash) && result[:error]
              warn "Error: #{result[:error]}"
              warn "  #{result[:description]}" if result[:description]
            elsif result.is_a?(Hash)
              puts ::JSON.pretty_generate(deep_stringify(result))
            else
              puts result.inspect
            end
          end

          def deep_stringify(obj)
            case obj
            when Hash  then obj.transform_keys(&:to_s).transform_values { |v| deep_stringify(v) }
            when Array then obj.map { |v| deep_stringify(v) }
            else obj
            end
          end
        end

        module GhCli
          def gh_available?
            return @gh_available unless @gh_available.nil?

            @gh_available = begin
              system('gh auth status', out: ::File::NULL, err: ::File::NULL)
            rescue StandardError => _e
              false
            end
          end

          def gh_token
            output = `gh auth token 2>/dev/null`.strip
            return nil unless $CHILD_STATUS&.success? && !output.empty?

            output
          rescue StandardError => _e
            nil
          end

          def gh_user
            output = `gh api user --jq .login 2>/dev/null`.strip
            return output unless output.empty?

            nil
          rescue StandardError => _e
            nil
          end

          def gh_login_interactive
            warn 'Launching GitHub authentication via gh CLI...'
            system('gh', 'auth', 'login', '--web', '--scopes', 'repo,read:org,read:user')
            $CHILD_STATUS&.success?
          rescue StandardError => _e
            false
          end
        end

        class AuthRunner
          include Legion::Logging::Helper if defined?(Legion::Logging::Helper)
          include Github::CLI::Auth
          include Github::App::Runners::CredentialStore
          include RunnerOutput
          include GhCli

          def status(**)
            # Try gh CLI first for zero-config status
            token = gh_token
            if token
              user = gh_user
              print_result({ result: { authenticated: true, auth_type: :gh_cli, user: user } })
              return
            end

            # Try the full credential chain
            cred = resolve_credential
            if cred
              print_result(auth_status_from_credential(cred))
            else
              print_result({ result: { authenticated: false,
                                       hint:          'Run `legionio lex exec github auth login` or install gh CLI' } })
            end
          end

          def login(**)
            # Try gh CLI first — zero config needed
            if gh_available?
              print_result({ result: { authenticated: true, auth_type: :gh_cli, user: gh_user,
                                       message: 'Already authenticated via gh CLI' } })
              return
            end

            # gh CLI installed but not authenticated — use its interactive flow
            if gh_installed?
              if gh_login_interactive
                print_result({ result: { authenticated: true, auth_type: :gh_cli, user: gh_user,
                                         message: 'Authenticated via gh CLI' } })
              else
                print_result({ error: 'gh_auth_failed', description: 'gh auth login did not complete' })
              end
              return
            end

            # No gh CLI — fall back to OAuth flow (needs client_id/secret)
            result = super
            print_result(result)
          end

          def credential_fingerprint(auth_type:, identifier:)
            "#{auth_type}:#{identifier}"
          end

          def vault_get(path)
            return nil unless defined?(Legion::Crypt)

            ::Legion::Crypt.get(path)
          rescue StandardError => e
            log.warn("[lex-github] vault_get failed: #{e.message}")
            nil
          end

          def cache_connected?
            defined?(Legion::Cache) && ::Legion::Cache.connected?
          rescue StandardError => e
            log.debug("[lex-github] cache_connected? check failed: #{e.message}")
            false
          end

          def local_cache_connected?
            defined?(Legion::Cache::Local) && ::Legion::Cache::Local.connected?
          rescue StandardError => e
            log.debug("[lex-github] local_cache_connected? check failed: #{e.message}")
            false
          end

          def cache_get(key)
            ::Legion::Cache.get(key)
          rescue StandardError => e
            log.debug("[lex-github] cache_get failed: #{e.message}")
            nil
          end

          def local_cache_get(key)
            ::Legion::Cache::Local.get(key)
          rescue StandardError => e
            log.debug("[lex-github] local_cache_get failed: #{e.message}")
            nil
          end

          def cache_set(key, value, ttl: 300)
            ::Legion::Cache.set(key, value, ttl)
          rescue StandardError => e
            log.debug("[lex-github] cache_set failed: #{e.message}")
            nil
          end

          def local_cache_set(key, value, ttl: 300)
            ::Legion::Cache::Local.set(key, value, ttl)
          rescue StandardError => e
            log.debug("[lex-github] local_cache_set failed: #{e.message}")
            nil
          end

          private

          def gh_installed?
            system('which gh', out: ::File::NULL, err: ::File::NULL)
          rescue StandardError => _e
            false
          end

          def auth_status_from_credential(cred)
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
        end

        class AppRunner
          include Legion::Logging::Helper if defined?(Legion::Logging::Helper)
          include Github::CLI::App
          include Github::App::Runners::CredentialStore
          include RunnerOutput

          def setup(**)
            print_result(super)
          end

          def complete_setup(**)
            print_result(super)
          end

          def credential_fingerprint(auth_type:, identifier:)
            "#{auth_type}:#{identifier}"
          end

          def vault_get(path)
            return nil unless defined?(Legion::Crypt)

            ::Legion::Crypt.get(path)
          rescue StandardError => e
            log.warn("[lex-github] vault_get failed: #{e.message}")
            nil
          end
        end
      end
    end
  end
end
