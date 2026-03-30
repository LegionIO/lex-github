# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Transport
          module Exchanges
            class App < Legion::Transport::Exchange
              def exchange_name = 'lex.github.app'
            end
          end
        end
      end
    end
  end
end
