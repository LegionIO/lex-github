# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      module App
        module Transport
          module Messages
            class Event < Legion::Transport::Message
              def routing_key = 'lex.github.app.runners.webhooks'
              def exchange    = Legion::Extensions::Github::App::Transport::Exchanges::App
            end
          end
        end
      end
    end
  end
end
