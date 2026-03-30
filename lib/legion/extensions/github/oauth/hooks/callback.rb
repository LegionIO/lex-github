# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module OAuth
        module Hooks
          class Callback < Legion::Extensions::Hooks::Base # rubocop:disable Legion/Extension/HookMissingRunnerClass
            mount '/callback'

            def self.runner_class
              'Legion::Extensions::Github::OAuth::Runners::Auth'
            end
          end
        end
      end
    end
  end
end
