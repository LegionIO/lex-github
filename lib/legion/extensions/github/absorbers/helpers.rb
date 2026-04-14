# lib/legion/extensions/github/absorbers/helpers.rb
# frozen_string_literal: true

require 'digest'
require 'securerandom'

module Legion
  module Extensions
    module Github
      module Absorbers
        module Helpers
          FLEET_LABELS = %w[
            fleet:received fleet:implementing fleet:pr-open fleet:escalated
          ].freeze

          IGNORED_ACTIONS = %w[
            closed transferred deleted pinned unpinned milestoned demilestoned
          ].freeze

          BOT_PATTERNS = /\[bot\]\z/i

          def bot_generated?(payload)
            sender = payload['sender'] || payload[:sender]
            return false unless sender

            login = sender['login'] || sender[:login] || ''
            type = sender['type'] || sender[:type] || ''

            type.downcase == 'bot' || login.match?(BOT_PATTERNS)
          end

          def has_fleet_label?(payload) # rubocop:disable Naming/PredicatePrefix
            issue = payload['issue'] || payload[:issue]
            return false unless issue

            labels = issue['labels'] || issue[:labels] || []
            labels.any? do |label|
              name = label['name'] || label[:name]
              FLEET_LABELS.include?(name)
            end
          end

          def ignored?(payload)
            action = payload['action'] || payload[:action]
            IGNORED_ACTIONS.include?(action.to_s)
          end

          def work_item_fingerprint(source:, ref:, title:)
            input = "#{source}:#{ref}:#{title}"
            Digest::SHA256.hexdigest(input)
          end

          def generate_work_item_id
            SecureRandom.uuid
          end

          def transport_connected?
            return false unless defined?(Legion::Settings)

            !!Legion::Settings.dig(:transport, :connected)
          rescue StandardError => _e
            false
          end
        end
      end
    end
  end
end
