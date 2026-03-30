# frozen_string_literal: true

require 'faraday'

module Legion
  module Extensions
    module Github
      module Middleware
        class CredentialFallback < ::Faraday::Middleware
          RETRYABLE_STATUSES = [403, 429].freeze

          def initialize(app, resolver: nil)
            super(app)
            @resolver = resolver
          end

          def call(env)
            response = @app.call(env)
            return response unless should_retry?(response)

            retries = 0
            max = @resolver.respond_to?(:max_fallback_retries) ? @resolver.max_fallback_retries : 3

            while retries < max && should_retry?(response)
              notify_resolver(response)

              next_credential = @resolver&.resolve_next_credential
              break unless next_credential

              env[:request_headers]['Authorization'] = "Bearer #{next_credential[:token]}"

              response = @app.call(env)
              retries += 1
            end

            response
          end

          private

          def should_retry?(response)
            return false unless @resolver.respond_to?(:credential_fallback?)
            return false unless @resolver.credential_fallback?

            RETRYABLE_STATUSES.include?(response.status)
          end

          def notify_resolver(response)
            if response.status == 429 && @resolver.respond_to?(:on_rate_limit)
              reset = response.headers['x-ratelimit-reset']
              reset_at = reset ? Time.at(reset.to_i) : Time.now + 60
              @resolver.on_rate_limit(remaining: 0, reset_at: reset_at,
                                      status: 429, url: response.env.url.to_s)
            elsif response.status == 403 && @resolver.respond_to?(:on_scope_denied)
              @resolver.on_scope_denied(status: 403, url: response.env.url.to_s,
                                        path: response.env.url.path)
            end
          end
        end
      end
    end
  end
end

Faraday::Middleware.register_middleware(
  github_credential_fallback: Legion::Extensions::Github::Middleware::CredentialFallback
)
