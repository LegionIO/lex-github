# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module OAuth
        module Transport
          module Exchanges
            class Oauth < Legion::Transport::Exchange
              def exchange_name = 'lex.github.oauth'
            end
          end
        end
      end
    end
  end
end
