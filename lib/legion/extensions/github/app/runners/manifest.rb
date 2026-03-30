# frozen_string_literal: true

require 'uri'
require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Manifest
            include Legion::Extensions::Github::Helpers::Client

            DEFAULT_PERMISSIONS = {
              contents: 'write', issues: 'write', pull_requests: 'write',
              metadata: 'read', administration: 'write', members: 'read',
              checks: 'write', statuses: 'write', actions: 'read',
              workflows: 'write', webhooks: 'write', repository_hooks: 'write'
            }.freeze

            DEFAULT_EVENTS = %w[
              push pull_request pull_request_review issues issue_comment
              create delete check_run check_suite status workflow_run
              repository installation
            ].freeze

            def generate_manifest(name:, url:, webhook_url:, callback_url:,
                                  permissions: DEFAULT_PERMISSIONS, events: DEFAULT_EVENTS,
                                  public: true, **)
              manifest = {
                name: name, url: url, public: public,
                hook_attributes: { url: webhook_url, active: true },
                setup_url: callback_url,
                redirect_url: callback_url,
                default_permissions: permissions,
                default_events: events
              }
              { result: manifest }
            end

            def exchange_manifest_code(code:, **)
              conn = connection(**)
              response = conn.post("/app-manifests/#{code}/conversions")
              { result: response.body }
            end

            def manifest_url(manifest:, org: nil, **)
              base = if org
                       "https://github.com/organizations/#{org}/settings/apps/new"
                     else
                       'https://github.com/settings/apps/new'
                     end
              { result: "#{base}?manifest=#{URI.encode_www_form_component(Legion::JSON.dump(manifest))}" }
            end
          end
        end
      end
    end
  end
end
