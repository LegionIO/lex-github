# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module OAuth
        module Actor
          class TokenRefresh < Legion::Extensions::Actors::Every # rubocop:disable Legion/Extension/SelfContainedActorRunnerClass,Legion/Extension/EveryActorRequiresTime
            def use_runner?    = false
            def check_subtask? = false
            def generate_task? = false

            def time
              3 * 60 * 60
            end

            # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            def enabled?
              oauth_settings[:client_id] && oauth_settings[:client_secret]
            rescue StandardError => _e
              false
            end
            # rubocop:enable Legion/Extension/ActorEnabledSideEffects

            def manual
              settings = oauth_settings
              return unless settings[:client_id] && settings[:client_secret]

              token_entry = fetch_delegated_token
              return unless token_entry&.dig(:refresh_token)

              auth = Object.new.extend(Legion::Extensions::Github::OAuth::Runners::Auth)
              result = auth.refresh_token(
                client_id:     settings[:client_id],
                client_secret: settings[:client_secret],
                refresh_token: token_entry[:refresh_token]
              )
              return unless result.dig(:result, 'access_token')

              store_delegated_token(result[:result])
              log.info('OAuth::Actor::TokenRefresh: delegated token refreshed')
            rescue StandardError => e
              log.error("OAuth::Actor::TokenRefresh: #{e.message}")
            end

            private

            def oauth_settings
              return {} unless defined?(Legion::Settings)

              Legion::Settings[:github]&.dig(:oauth) || {}
            rescue StandardError => _e
              {}
            end

            def fetch_delegated_token
              return nil unless defined?(Legion::Crypt)

              vault_get('github/oauth/delegated/token')
            rescue StandardError => _e
              nil
            end

            def store_delegated_token(token_data)
              return unless defined?(Legion::Crypt)

              vault_write('github/oauth/delegated/token', token_data)
            rescue StandardError => e
              log.warn("OAuth::Actor::TokenRefresh#store_delegated_token: #{e.message}")
            end
          end
        end
      end
    end
  end
end
