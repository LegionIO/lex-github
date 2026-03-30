# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module RepositoryWebhooks
          include Legion::Extensions::Github::Helpers::Client

          def list_webhooks(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/hooks", per_page: per_page, page: page
            )
            { result: response.body }
          end

          def get_webhook(owner:, repo:, hook_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/hooks/#{hook_id}"
            )
            { result: response.body }
          end

          def create_webhook(owner:, repo:, config:, events: ['push'], active: true, **)
            payload = { config: config, events: events, active: active }
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/hooks", payload
            )
            { result: response.body }
          end

          def update_webhook(owner:, repo:, hook_id:, **opts)
            payload = opts.slice(:config, :events, :active, :add_events, :remove_events)
            response = connection(owner: owner, repo: repo, **opts).patch(
              "/repos/#{owner}/#{repo}/hooks/#{hook_id}", payload
            )
            { result: response.body }
          end

          def delete_webhook(owner:, repo:, hook_id:, **)
            response = connection(owner: owner, repo: repo, **).delete(
              "/repos/#{owner}/#{repo}/hooks/#{hook_id}"
            )
            { result: response.status == 204 }
          end

          def ping_webhook(owner:, repo:, hook_id:, **)
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/hooks/#{hook_id}/pings"
            )
            { result: response.status == 204 }
          end

          def test_webhook(owner:, repo:, hook_id:, **)
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/hooks/#{hook_id}/tests"
            )
            { result: response.status == 204 }
          end

          def list_webhook_deliveries(owner:, repo:, hook_id:, per_page: 30, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/hooks/#{hook_id}/deliveries", per_page: per_page
            )
            { result: response.body }
          end
        end
      end
    end
  end
end
