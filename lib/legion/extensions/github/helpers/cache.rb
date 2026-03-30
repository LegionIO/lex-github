# frozen_string_literal: true

require 'legion/cache/helper'

module Legion
  module Extensions
    module Github
      module Helpers
        module Cache
          include Legion::Cache::Helper

          DEFAULT_TTLS = {
            repo: 600, issue: 120, pull_request: 60, commit: 86_400,
            branch: 120, user: 3600, org: 3600, search: 60
          }.freeze

          DEFAULT_TTL = 300

          def cached_get(cache_key, ttl: nil, &block)
            if cache_connected?
              result = cache_get(cache_key)
              return result if result
            end

            if local_cache_connected?
              result = local_cache_get(cache_key)
              return result if result
            end

            result = yield
            effective_ttl = ttl || github_ttl_for(cache_key)
            cache_set(cache_key, result, ttl: effective_ttl) if cache_connected?
            local_cache_set(cache_key, result, ttl: effective_ttl) if local_cache_connected?
            result
          end

          def cache_write(cache_key, value, ttl: nil)
            effective_ttl = ttl || github_ttl_for(cache_key)
            cache_set(cache_key, value, ttl: effective_ttl) if cache_connected?
            local_cache_set(cache_key, value, ttl: effective_ttl) if local_cache_connected?
          end

          def cache_invalidate(cache_key)
            cache_delete(cache_key) if cache_connected?
            local_cache_delete(cache_key) if local_cache_connected?
          end

          def github_ttl_for(cache_key)
            configured_ttls = github_cache_ttls
            case cache_key
            when /:commits:/ then configured_ttls[:commit]
            when /:pulls:/   then configured_ttls[:pull_request]
            when /:issues:/  then configured_ttls[:issue]
            when /:branches:/ then configured_ttls[:branch]
            when /\Agithub:user:/ then configured_ttls[:user]
            when /\Agithub:org:/  then configured_ttls[:org]
            when /\Agithub:repo:[^:]+\z/ then configured_ttls[:repo]
            when /:search:/  then configured_ttls[:search]
            else configured_ttls.fetch(:default, DEFAULT_TTL)
            end
          end

          def cache_connected?
            ::Legion::Cache.connected?
          rescue StandardError
            false
          end

          def local_cache_connected?
            false
          end

          def local_cache_get(_key)
            nil
          end

          def local_cache_set(_key, _value, ttl: nil) # rubocop:disable Lint/UnusedMethodArgument
            nil
          end

          def local_cache_delete(_key)
            nil
          end

          private

          def github_cache_ttls
            return DEFAULT_TTLS.merge(default: DEFAULT_TTL) unless defined?(Legion::Settings)

            overrides = Legion::Settings.dig(:github, :cache, :ttls) || {}
            DEFAULT_TTLS.merge(default: DEFAULT_TTL).merge(overrides.transform_keys(&:to_sym))
          rescue StandardError
            DEFAULT_TTLS.merge(default: DEFAULT_TTL)
          end
        end
      end
    end
  end
end
