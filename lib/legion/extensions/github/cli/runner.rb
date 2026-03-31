# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'rbconfig'

module Legion
  module Extensions
    module Github
      module CLI
        DAEMON_URL = ENV.fetch('LEGION_API_URL', 'http://127.0.0.1:4567')

        module DaemonApi
          private

          def api_post(path, body = {})
            uri = URI("#{DAEMON_URL}#{path}")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 5
            http.read_timeout = 30
            request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
            request.body = ::JSON.generate(body)
            parse_response(http.request(request))
          rescue Errno::ECONNREFUSED, Errno::ECONNRESET => _e
            { error: 'daemon_unavailable', description: "Legion daemon not running at #{DAEMON_URL}. Start it with: legionio start" }
          end

          def api_get(path)
            uri = URI("#{DAEMON_URL}#{path}")
            parse_response(Net::HTTP.get_response(uri))
          rescue Errno::ECONNREFUSED, Errno::ECONNRESET => _e
            { error: 'daemon_unavailable', description: "Legion daemon not running at #{DAEMON_URL}. Start it with: legionio start" }
          end

          def parse_response(response)
            ::JSON.parse(response.body, symbolize_names: true)
          rescue ::JSON::ParserError => _e
            { error: "http_#{response.code}", description: response.body&.strip }
          end

          def print_json(result)
            if result.is_a?(Hash) && result[:error]
              warn "Error: #{result[:error]}"
              warn "  #{result[:description]}" if result[:description]
            else
              puts ::JSON.pretty_generate(result)
            end
          end

          def open_browser(url)
            cmd = case RbConfig::CONFIG['host_os']
                  when /darwin/      then 'open'
                  when /linux/       then 'xdg-open'
                  when /mswin|mingw/ then 'start'
                  end
            system(cmd, url) if cmd
          end
        end

        class AuthRunner
          include DaemonApi

          def status
            print_json(api_post('/api/extensions/github/runners/auth/status'))
          end

          def login
            print_json(api_post('/api/extensions/github/runners/auth/login'))
          end
        end

        class AppRunner
          include DaemonApi

          def setup
            result = api_post('/api/extensions/github/cli/app/setup')

            if result[:error]
              print_json(result)
              return
            end

            url = result.dig(:data, :manifest_url)
            if url
              warn 'Opening browser to create GitHub App...'
              open_browser(url)
              warn 'Waiting for callback...'
              poll = api_post('/api/extensions/github/cli/app/await_callback',
                              { timeout: 300 })
              print_json(poll)
            else
              print_json(result)
            end
          end

          def complete_setup
            print_json(api_post('/api/extensions/github/cli/app/complete_setup'))
          end
        end
      end
    end
  end
end
