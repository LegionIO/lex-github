# frozen_string_literal: true

require 'securerandom'
require 'rbconfig'
require 'legion/extensions/github/oauth/runners/auth'
require 'legion/extensions/github/helpers/callback_server'

module Legion
  module Extensions
    module Github
      module Helpers
        class BrowserAuth
          DEFAULT_SCOPES = 'repo admin:org admin:repo_hook read:user'

          attr_reader :client_id, :client_secret, :scopes

          def initialize(client_id:, client_secret:, scopes: DEFAULT_SCOPES, auth: nil, **)
            @client_id = client_id
            @client_secret = client_secret
            @scopes = scopes
            @auth = auth || Object.new.extend(OAuth::Runners::Auth)
          end

          def authenticate
            if gui_available?
              authenticate_browser
            else
              authenticate_device_code
            end
          end

          def gui_available?
            os = host_os
            return true if /darwin|mswin|mingw/.match?(os)

            !ENV['DISPLAY'].nil? || !ENV['WAYLAND_DISPLAY'].nil?
          end

          def open_browser(url)
            cmd = case host_os
                  when /darwin/      then 'open'
                  when /linux/       then 'xdg-open'
                  when /mswin|mingw/ then 'start'
                  end
            return false unless cmd

            system(cmd, url)
          end

          private

          def host_os
            RbConfig::CONFIG['host_os']
          end

          def authenticate_browser
            pkce = @auth.generate_pkce[:result]
            state = SecureRandom.hex(32)

            server = CallbackServer.new
            server.start
            callback_uri = server.redirect_uri

            url = @auth.authorize_url(
              client_id: client_id, redirect_uri: callback_uri,
              scope: scopes, state: state,
              code_challenge: pkce[:challenge],
              code_challenge_method: pkce[:challenge_method]
            )[:result]

            return authenticate_device_code unless open_browser(url)

            result = server.wait_for_callback(timeout: 120)

            return { error: 'timeout', description: 'No callback received within timeout' } unless result&.dig(:code)

            return { error: 'state_mismatch', description: 'CSRF state parameter mismatch' } unless result[:state] == state

            @auth.exchange_code(
              client_id: client_id, client_secret: client_secret,
              code: result[:code], redirect_uri: callback_uri,
              code_verifier: pkce[:verifier]
            )
          ensure
            server&.shutdown
          end

          def authenticate_device_code
            dc = @auth.request_device_code(client_id: client_id, scope: scopes)
            return { error: dc[:error], description: dc[:description] } if dc[:error]

            body = dc[:result]
            warn "Go to:  #{body[:verification_uri]}"
            warn "Code:   #{body[:user_code]}"
            open_browser(body[:verification_uri]) if gui_available?

            @auth.poll_device_code(
              client_id:   client_id,
              device_code: body[:device_code]
            )
          end
        end
      end
    end
  end
end
