# frozen_string_literal: true

require 'faraday'

module Legion
  module Extensions
    module Github
      module Middleware
        class RateLimit < ::Faraday::Middleware
          def initialize(app, handler: nil)
            super(app)
            @handler = handler
          end

          def on_complete(env)
            remaining = env.response_headers['x-ratelimit-remaining']
            reset = env.response_headers['x-ratelimit-reset']
            return unless remaining

            remaining_int = remaining.to_i
            return unless remaining_int.zero? || env.status == 429
            return unless @handler.respond_to?(:on_rate_limit)

            reset_at = reset ? Time.at(reset.to_i) : Time.now + 60
            @handler.on_rate_limit(
              remaining: remaining_int,
              reset_at:  reset_at,
              status:    env.status,
              url:       env.url.to_s
            )
          end
        end
      end
    end
  end
end

Faraday::Response.register_middleware(
  github_rate_limit: Legion::Extensions::Github::Middleware::RateLimit
)
