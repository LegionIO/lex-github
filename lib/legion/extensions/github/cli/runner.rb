# frozen_string_literal: true

require 'legion/extensions/github/cli/auth'
require 'legion/extensions/github/cli/app'
require 'legion/extensions/github/app/runners/credential_store'

module Legion
  module Extensions
    module Github
      module CLI
        class AuthRunner
          include Legion::Logging::Helper if defined?(Legion::Logging::Helper)
          include Github::CLI::Auth
          include Github::App::Runners::CredentialStore

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
        end

        class AppRunner
          include Legion::Logging::Helper if defined?(Legion::Logging::Helper)
          include Github::CLI::App
          include Github::App::Runners::CredentialStore

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
