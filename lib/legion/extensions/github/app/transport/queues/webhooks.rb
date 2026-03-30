# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Transport
          module Queues
            class Webhooks < Legion::Transport::Queue
              def queue_name    = 'lex.github.app.runners.webhooks'
              def queue_options = { auto_delete: false }
            end
          end
        end
      end
    end
  end
end
