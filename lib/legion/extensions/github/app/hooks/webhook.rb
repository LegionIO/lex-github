# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Hooks
          class Webhook < Legion::Extensions::Hooks::Base
            mount '/webhook'

            def self.runner_class
              'Legion::Extensions::Github::App::Runners::Webhooks'
            end
          end
        end
      end
    end
  end
end
