# frozen_string_literal: true

require 'faraday'

module Legion
  module Extensions
    module Github
      module Middleware
        class ScopeProbe < ::Faraday::Middleware
          REPO_PATH_PATTERN = %r{^/repos/([^/]+)/([^/]+)}.freeze

          def initialize(app, handler: nil)
            super(app)
            @handler = handler
          end

          def on_complete(env)
            return unless @handler
            return unless env.url.path.match?(REPO_PATH_PATTERN)

            info = { status: env.status, url: env.url.to_s, path: env.url.path }

            if env.status == 403 || env.status == 404
              @handler.on_scope_denied(info) if @handler.respond_to?(:on_scope_denied)
            elsif env.status >= 200 && env.status < 300
              @handler.on_scope_authorized(info) if @handler.respond_to?(:on_scope_authorized)
            end
          end
        end
      end
    end
  end
end

::Faraday::Response.register_middleware(
  github_scope_probe: Legion::Extensions::Github::Middleware::ScopeProbe
)
