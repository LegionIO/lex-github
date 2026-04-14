# lib/legion/extensions/github/absorbers/webhook_setup.rb
# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module Absorbers
        # Mixin for auto-registering GitHub webhooks and fleet labels on a repo.
        # Used by `legionio fleet add github` to wire up the absorber source.
        #
        # Include this module in a class that also includes the GitHub runners
        # (RepositoryWebhooks, Labels).
        module WebhookSetup
          FLEET_WEBHOOK_EVENTS = %w[issues pull_request].freeze

          FLEET_LABELS = [
            { name: 'fleet:received', color: '6f42c1', description: 'Fleet pipeline has received this issue' },
            { name: 'fleet:implementing', color: '0e8a16', description: 'Fleet is implementing a fix' },
            { name: 'fleet:pr-open', color: '1d76db', description: 'Fleet has opened a PR for this issue' },
            { name: 'fleet:escalated', color: 'e4e669', description: 'Fleet escalated this issue to a human' }
          ].freeze

          # Set up fleet webhook and labels on a GitHub repo.
          #
          # @param owner [String] Repository owner/org
          # @param repo [String] Repository name
          # @param webhook_url [String] Callback URL for webhook delivery
          # @return [Hash] { success:, webhook_id:, labels_created: }
          def setup_fleet_webhook(owner:, repo:, webhook_url:, **)
            # Check if webhook already exists
            existing = list_webhooks(owner: owner, repo: repo)
            existing_hook = (existing[:result] || []).find do |hook|
              url = hook.is_a?(Hash) ? (hook.dig('config', 'url') || hook.dig(:config, :url)) : nil
              url == webhook_url
            end

            if existing_hook
              hook_id = existing_hook['id'] || existing_hook[:id]
              labels = ensure_fleet_labels(owner: owner, repo: repo)
              return { success: true, existing: true, webhook_id: hook_id, labels_created: labels }
            end

            # Create webhook
            config = {
              url:          webhook_url,
              content_type: 'json',
              insecure_ssl: '0'
            }

            result = create_webhook(
              owner:  owner,
              repo:   repo,
              config: config,
              events: FLEET_WEBHOOK_EVENTS,
              active: true
            )

            webhook_data = result[:result] || {}
            webhook_id = webhook_data['id'] || webhook_data[:id]

            return { success: false, error: 'webhook creation returned no id' } if webhook_id.nil?

            # Create fleet labels
            labels = ensure_fleet_labels(owner: owner, repo: repo)

            {
              success:        true,
              existing:       false,
              webhook_id:     webhook_id,
              webhook_url:    webhook_url,
              labels_created: labels
            }
          rescue StandardError => e
            { success: false, error: e.message }
          end

          def fleet_label_definitions
            FLEET_LABELS
          end

          private

          def ensure_fleet_labels(owner:, repo:)
            created = []
            FLEET_LABELS.each do |label_def|
              create_label(
                owner:       owner,
                repo:        repo,
                name:        label_def[:name],
                color:       label_def[:color],
                description: label_def[:description]
              )
              created << label_def[:name]
            end
            created
          end
        end
      end
    end
  end
end
