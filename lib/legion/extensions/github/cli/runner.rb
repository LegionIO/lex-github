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
            http.read_timeout = 300
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
            if result.is_a?(Hash) && (result[:error] || result.dig(:error, :code))
              warn "Error: #{result[:error] || result.dig(:error, :message)}"
              warn "  #{result[:description]}" if result[:description]
            else
              puts ::JSON.pretty_generate(result)
            end
          end

          def prompt(label, default: nil)
            if default
              $stderr.print "#{label} [#{default}]: "
            else
              $stderr.print "#{label}: "
            end
            input = $stdin.gets&.chomp
            input.nil? || input.empty? ? default : input
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
            warn 'GitHub App Setup — the daemon will start a local callback server and open your browser.'
            warn ''

            name        = prompt('App name')
            url         = prompt('App homepage URL (e.g. https://your-domain.com)')
            webhook_url = prompt('Webhook URL (e.g. https://your-domain.com/webhooks/github)')
            org         = prompt('GitHub org (leave blank for personal account)', default: nil)

            body = { name: name, url: url, webhook_url: webhook_url }
            body[:org] = org if org && !org.empty?

            warn ''
            warn 'Sending setup request to daemon...'

            result = api_post('/api/extensions/github/runners/app/setup', body)

            if result[:error] || result.dig(:error, :code)
              print_json(result)
              return
            end

            manifest_url = result.dig(:result, :manifest_url)
            if manifest_url
              warn "Opening browser: #{manifest_url}"
              open_browser(manifest_url)
              warn 'Waiting for GitHub callback (daemon is listening)...'
            end

            print_json(result)
          end

          def complete_setup
            code = prompt('Authorization code from GitHub callback')
            print_json(api_post('/api/extensions/github/runners/app/complete_setup', { code: code }))
          end
        end
      end
    end
  end
end
