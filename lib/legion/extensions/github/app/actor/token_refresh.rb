# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Actor
          class TokenRefresh < Legion::Extensions::Actors::Every # rubocop:disable Legion/Extension/SelfContainedActorRunnerClass,Legion/Extension/EveryActorRequiresTime
            def use_runner?    = false
            def check_subtask? = false
            def generate_task? = false

            def time
              45 * 60
            end

            # rubocop:disable Legion/Extension/ActorEnabledSideEffects
            def enabled?
              defined?(Legion::Extensions::Github::Helpers::TokenCache)
            rescue StandardError => _e
              false
            end
            # rubocop:enable Legion/Extension/ActorEnabledSideEffects

            def manual
              log.info('App::Actor::TokenRefresh: refreshing installation token')
              settings = github_app_settings
              return unless settings[:app_id] && settings[:private_key] && settings[:installation_id]

              auth = Legion::Extensions::Github::App::Runners::Auth
              jwt_result = auth.generate_jwt(app_id: settings[:app_id], private_key: settings[:private_key])
              return unless jwt_result[:result]

              token_result = auth.create_installation_token(
                jwt:             jwt_result[:result],
                installation_id: settings[:installation_id]
              )
              return unless token_result.dig(:result, 'token')

              token_cache.store_token(
                token:      token_result[:result]['token'],
                auth_type:  :app_installation,
                expires_at: Time.parse(token_result[:result]['expires_at'])
              )
              log.info('App::Actor::TokenRefresh: installation token refreshed')
            rescue StandardError => e
              log.error("App::Actor::TokenRefresh: #{e.message}")
            end

            private

            def github_app_settings
              return {} unless defined?(Legion::Settings)

              Legion::Settings[:github]&.dig(:app) || {}
            rescue StandardError => _e
              {}
            end

            def token_cache
              Object.new.extend(Legion::Extensions::Github::Helpers::TokenCache)
            end
          end
        end
      end
    end
  end
end
