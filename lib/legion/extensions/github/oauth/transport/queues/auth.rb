# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module OAuth
        module Transport
          module Queues
            class Auth < Legion::Transport::Queue
              def queue_name    = 'lex.github.oauth.runners.auth'
              def queue_options = { auto_delete: false }
            end
          end
        end
      end
    end
  end
end
