# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Hooks
          class Setup < Legion::Extensions::Hooks::Base # rubocop:disable Legion/Extension/HookMissingRunnerClass
            mount '/setup/callback'

            def self.runner_class
              'Legion::Extensions::Github::App::Runners::Manifest'
            end
          end
        end
      end
    end
  end
end
