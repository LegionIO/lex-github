# lib/legion/extensions/github/absorbers/actor.rb
# frozen_string_literal: true

require_relative 'issues'

module Legion
  module Extensions
    module Github
      module Absorbers
        # Subscription actor that listens on the absorber queue and delegates
        # to the Issues absorber module.
        #
        # Queue: lex.github.absorbers.issues.absorb
        # Exchange: lex.github
        # Routing key: lex.github.absorbers.issues.absorb
        #
        # Per Wire Protocol section 17, absorber queues follow the pattern:
        #   lex.{lex_name}.absorbers.{absorber_name}.absorb
        class IssuesActor < Legion::Extensions::Actors::Subscription

          def absorb(payload:, **)
            Legion::Extensions::Github::Absorbers::Issues.absorb(payload: payload)
          end

          def runner_class
            Legion::Extensions::Github::Absorbers::Issues
          end

          def runner_function
            'absorb'
          end

          def use_runner?
            false
          end

          def check_subtask?
            false
          end

          def generate_task?
            false
          end
        end
      end
    end
  end
end
