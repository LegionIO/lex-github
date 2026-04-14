# lib/legion/extensions/github/absorbers/issues.rb
# frozen_string_literal: true

require_relative 'helpers'

module Legion
  module Extensions
    module Github
      module Absorbers
        # Absorbs GitHub issue events and normalizes them to fleet work items.
        # Subscribes to lex.github.absorbers.issues queue.
        #
        # Filters: bot events, already-claimed issues (fleet labels), ignored
        # actions (closed, transferred, etc.).
        #
        # Publishes normalized work items to the assessor queue via task chain.
        module Issues
          extend self
          extend Helpers

          CACHE_TTL = 86_400 # 24 hours

          def description_max_bytes
            Legion::Settings.dig(:fleet, :work_item, :description_max_bytes) || 32_768
          rescue StandardError => _e
            32_768
          end

          # Main entry point. Called by the subscription actor when a GitHub
          # webhook event for issues arrives.
          #
          # @param payload [Hash] Raw GitHub webhook payload (string keys from JSON)
          # @return [Hash] { absorbed: true/false, ... }
          def absorb(payload:, **)
            return { absorbed: false, reason: :bot_generated } if bot_generated?(payload)
            return { absorbed: false, reason: :already_claimed } if has_fleet_label?(payload)
            return { absorbed: false, reason: :ignored } if ignored?(payload)

            work_item = normalize(payload)

            # NOTE: Absorber does NOT call set_nx — the assessor is the single dedup authority.
            # Source-specific dedup only: label checks, bot filter, action filter.

            # Store large raw payload in Redis, not inline in AMQP message
            cache_key = "fleet:payload:#{work_item[:work_item_id]}"
            cache_set(cache_key, json_dump(payload), ttl: CACHE_TTL)
            work_item[:raw_payload_ref] = cache_key

            # Publish to assessor via transport
            publish_result = publish_to_assessor(work_item)

            # Propagate publish failures — do not swallow
            return publish_result if publish_result.is_a?(Hash) && publish_result[:absorbed] == false

            { absorbed: true, work_item_id: work_item[:work_item_id] }
          end

          # Normalize a raw GitHub webhook payload to the standard fleet work
          # item format (design spec section 3).
          #
          # @param payload [Hash] Raw GitHub webhook payload (string keys)
          # @return [Hash] Normalized work item (symbol keys)
          def normalize(payload)
            issue = payload['issue'] || {}
            repo = payload['repository'] || {}
            action = payload['action'] || 'opened'
            owner = repo.dig('owner', 'login') || ''
            repo_name = repo['name'] || ''
            number = issue['number']
            body = issue['body'] || ''
            max_bytes = description_max_bytes

            {
              work_item_id:    generate_work_item_id,
              source:          'github',
              source_ref:      "#{owner}/#{repo_name}##{number}",
              source_event:    "issues.#{action}",

              title:           issue['title'] || '',
              description:     body.bytesize > max_bytes ? body.byteslice(0, max_bytes).scrub('') : body,
              raw_payload_ref: nil, # set after cache write in absorb

              repo:            {
                owner:          owner,
                name:           repo_name,
                default_branch: repo['default_branch'] || 'main',
                language:       repo['language'] || 'unknown'
              },

              instructions:    [],
              context:         [],

              config:          default_config,

              pipeline:        {
                stage:            'intake',
                trace:            [],
                attempt:          0,
                feedback_history: [],
                plan:             nil,
                changes:          nil,
                review_result:    nil,
                pr_number:        nil,
                branch_name:      nil,
                context_ref:      nil
              }
            }
          end

          private

          def default_config
            {
              priority:             :medium,
              complexity:           nil,
              estimated_difficulty: nil,
              planning:             default_config_planning,
              implementation:       default_config_implementation,
              validation:           default_config_validation,
              feedback:             default_config_feedback,
              workspace:            { isolation: :worktree, cleanup_on_complete: true },
              context:              { load_repo_docs: true, load_file_tree: true, max_context_files: 50 },
              tracing:              { stage_comments: true, token_tracking: true },
              safety:               { poison_message_threshold: 2, cancel_allowed: true },
              selection:            { strategy: :test_winner },
              escalation:           { on_max_iterations: :human, consent_domain: 'fleet.shipping' }
            }
          end

          def default_config_planning
            { enabled: true, solvers: 1, validators: 1, max_iterations: 2 }
          end

          def default_config_implementation
            { solvers: 1, validators: 3, max_iterations: 5, models: nil }
          end

          def default_config_validation
            {
              enabled:            true,
              run_tests:          true,
              run_lint:           true,
              security_scan:      true,
              adversarial_review: true,
              reviewer_models:    nil
            }
          end

          def default_config_feedback
            { drain_enabled: true, max_drain_rounds: 3, summarize_after: 2 }
          end

          # Publish the normalized work item to the assessor's queue.
          # Uses Legion::Transport::Messages::Task.
          #
          # generate_task_id returns a Hash { success:, task_id:, ... } — extract task_id.
          # function: must be a String ('assess'), never a Symbol.
          # Do NOT pass exchange: as String (broken until WS-00F lands).
          #
          # Propagates failures — returns { absorbed: false, reason: :publish_failed, ... }
          def publish_to_assessor(work_item)
            # Transport unavailable = lite mode / test environment. Not a publish failure; skip silently.
            return unless transport_connected? && defined?(Legion::Runner)

            result = Legion::Runner::Status.generate_task_id(
              runner_class: 'Legion::Extensions::Assessor::Runners::Assessor',
              function:     'assess'
            )
            task_id = result&.dig(:task_id)
            raise 'Fleet: cannot create task record (is legion-data connected?)' if task_id.nil?

            Legion::Transport::Messages::Task.new(
              work_item:   work_item,
              function:    'assess',
              task_id:     task_id,
              master_id:   task_id,
              routing_key: 'lex.assessor.runners.assessor.assess'
            ).publish
          rescue StandardError => e
            log.warn("Absorber publish failed: #{e.message}")
            { absorbed: false, reason: :publish_failed, message: e.message }
          end

          # Direct delegators to Legion::Cache and Legion::JSON.
          # These thin wrappers satisfy the HelperMigration cops at call sites
          # while preserving full control over key format and arguments.
          # rubocop:disable Legion/HelperMigration/DirectCache, Legion/HelperMigration/DirectJson
          def cache_set(key, value, ttl: nil)
            Legion::Cache.set(key, value, ttl: ttl)
          end

          def json_dump(object)
            Legion::JSON.dump(object)
          end
          # rubocop:enable Legion/HelperMigration/DirectCache, Legion/HelperMigration/DirectJson
        end
      end
    end
  end
end
