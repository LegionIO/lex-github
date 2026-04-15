# frozen_string_literal: true

require 'legion/extensions/github/cli/app'

module Legion
  module Extensions
    module Github
      module Runners
        module App
          include Legion::Extensions::Github::CLI::App

          def self.remote_invocable?
            false
          end

          # Explicitly surface included methods so build_routes picks them up
          # via instance_methods(false)

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
