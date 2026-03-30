# frozen_string_literal: true

require 'time'
require 'legion/cache/helper'

module Legion
  module Extensions
    module Github
      module Helpers
        module TokenCache
          include Legion::Cache::Helper

          TOKEN_BUFFER_SECONDS = 300

          def store_token(token:, auth_type:, expires_at:, installation_id: nil, metadata: {}, **)
            entry = { token: token, auth_type: auth_type,
                      expires_at: expires_at.respond_to?(:iso8601) ? expires_at.iso8601 : expires_at,
                      installation_id: installation_id, metadata: metadata }
            ttl = [(expires_at.respond_to?(:to_i) ? expires_at.to_i - Time.now.to_i : 3600), 60].max
            key = token_cache_key(auth_type, installation_id)
            cache_set(key, entry, ttl: ttl) if cache_connected?
            local_cache_set(key, entry, ttl: ttl) if local_cache_connected?
          end

          def fetch_token(auth_type:, installation_id: nil, **)
            key = token_cache_key(auth_type, installation_id)
            entry = token_cache_read(key)

            if entry.nil? && installation_id
              entry = token_cache_read(token_cache_key(auth_type, nil))
            end

            return nil unless entry

            expires = begin
              Time.parse(entry[:expires_at].to_s)
            rescue StandardError
              nil
            end
            return nil if expires && expires < Time.now + TOKEN_BUFFER_SECONDS

            entry
          end

          def mark_rate_limited(auth_type:, reset_at:, **)
            entry = { reset_at: reset_at.respond_to?(:iso8601) ? reset_at.iso8601 : reset_at }
            ttl = [(reset_at.respond_to?(:to_i) ? reset_at.to_i - Time.now.to_i : 300), 10].max
            key = "github:rate_limit:#{auth_type}"
            cache_set(key, entry, ttl: ttl) if cache_connected?
            local_cache_set(key, entry, ttl: ttl) if local_cache_connected?
          end

          def rate_limited?(auth_type:, **)
            key = "github:rate_limit:#{auth_type}"
            entry = if cache_connected?
                      cache_get(key)
                    elsif local_cache_connected?
                      local_cache_get(key)
                    end
            return false unless entry

            reset = begin
              Time.parse(entry[:reset_at].to_s)
            rescue StandardError
              nil
            end
            reset.nil? || reset > Time.now
          end

          private

          def token_cache_key(auth_type, installation_id)
            base = "github:token:#{auth_type}"
            installation_id ? "#{base}:#{installation_id}" : base
          end

          def token_cache_read(key)
            if cache_connected?
              cache_get(key)
            elsif local_cache_connected?
              local_cache_get(key)
            end
          end
        end
      end
    end
  end
end
