# frozen_string_literal: true

require 'digest'

module Legion
  module Extensions
    module Github
      module Helpers
        module ScopeRegistry
          def credential_fingerprint(auth_type:, identifier:)
            Digest::SHA256.hexdigest("#{auth_type}:#{identifier}")[0, 16]
          end

          def scope_status(fingerprint:, owner:, repo: nil)
            if repo
              status = scope_cache_get("github:scope:#{fingerprint}:#{owner}/#{repo}")
              return status if status
            end

            scope_cache_get("github:scope:#{fingerprint}:#{owner}") || :unknown
          end

          def register_scope(fingerprint:, owner:, status:, repo: nil)
            key = repo ? "github:scope:#{fingerprint}:#{owner}/#{repo}" : "github:scope:#{fingerprint}:#{owner}"
            ttl = if status == :denied
                    scope_denied_ttl
                  else
                    (repo ? scope_repo_ttl : scope_org_ttl)
                  end
            cache_set(key, status, ttl: ttl) if cache_connected?
            local_cache_set(key, status, ttl: ttl) if local_cache_connected?
          end

          def rate_limited?(fingerprint:)
            entry = scope_cache_get("github:rate_limit:#{fingerprint}")
            return false unless entry

            entry[:reset_at] > Time.now
          end

          def mark_rate_limited(fingerprint:, reset_at:)
            ttl = [(reset_at - Time.now).ceil, 1].max
            value = { reset_at: reset_at, remaining: 0 }
            cache_set("github:rate_limit:#{fingerprint}", value, ttl: ttl) if cache_connected?
            local_cache_set("github:rate_limit:#{fingerprint}", value, ttl: ttl) if local_cache_connected?
          end

          def invalidate_scope(fingerprint:, owner:, repo: nil)
            key = repo ? "github:scope:#{fingerprint}:#{owner}/#{repo}" : "github:scope:#{fingerprint}:#{owner}"
            cache_delete(key) if cache_connected?
            local_cache_delete(key) if local_cache_connected?
          end

          private

          def scope_cache_get(key)
            if cache_connected?
              result = cache_get(key)
              return result if result
            end
            local_cache_get(key) if local_cache_connected?
          end

          def scope_org_ttl
            return 3600 unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :scope_registry, :org_ttl) || 3600
          rescue StandardError => _e
            3600
          end

          def scope_repo_ttl
            return 300 unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :scope_registry, :repo_ttl) || 300
          rescue StandardError => _e
            300
          end

          def scope_denied_ttl
            return 300 unless defined?(Legion::Settings)

            Legion::Settings.dig(:github, :scope_registry, :denied_ttl) || 300
          rescue StandardError => _e
            300
          end
        end
      end
    end
  end
end
