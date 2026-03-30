# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Actor
          class WebhookPoller < Legion::Extensions::Actors::Poll # rubocop:disable Legion/Extension/SelfContainedActorRunnerClass,Legion/Extension/EveryActorRequiresTime
            def use_runner?    = false
            def check_subtask? = false
            def generate_task? = false

            def time
              60
            end

            # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            def enabled?
              github_poll_settings[:owner] && github_poll_settings[:repo]
            rescue StandardError => _e
              false
            end
            # rubocop:enable Legion/Extension/ActorEnabledSideEffects

            def manual
              settings = github_poll_settings
              owner = settings[:owner]
              repo = settings[:repo]
              return unless owner && repo

              client = Legion::Extensions::Github::Client.new
              result = client.list_events(owner: owner, repo: repo)
              events = result[:result]
              return unless events.is_a?(Array)

              events.each do |event|
                publish_event(event)
              end
            rescue StandardError => e
              log.error("App::Actor::WebhookPoller: #{e.message}")
            end

            private

            def github_poll_settings
              return {} unless defined?(Legion::Settings)

              Legion::Settings[:github]&.dig(:webhook_poller) || {}
            rescue StandardError => _e
              {}
            end

            def publish_event(event)
              Legion::Extensions::Github::App::Transport::Messages::Event.new(event).publish
            rescue StandardError => e
              log.warn("WebhookPoller#publish_event: #{e.message}")
            end
          end
        end
      end
    end
  end
end
