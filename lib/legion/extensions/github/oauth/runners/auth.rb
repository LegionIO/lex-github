# frozen_string_literal: true

require 'base64'
require 'openssl'
require 'securerandom'
require 'uri'
require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module OAuth
        module Runners
          module Auth
            include Legion::Extensions::Github::Helpers::Client

            def generate_pkce(**)
              verifier = SecureRandom.urlsafe_base64(32)
              challenge = ::Base64.urlsafe_encode64(
                OpenSSL::Digest::SHA256.digest(verifier), padding: false
              )
              { result: { verifier: verifier, challenge: challenge, challenge_method: 'S256' } }
            end

            def authorize_url(client_id:, redirect_uri:, scope:, state:,
                              code_challenge:, code_challenge_method: 'S256', **)
              params = URI.encode_www_form(
                client_id: client_id, redirect_uri: redirect_uri,
                scope: scope, state: state,
                code_challenge: code_challenge,
                code_challenge_method: code_challenge_method
              )
              { result: "https://github.com/login/oauth/authorize?#{params}" }
            end

            def exchange_code(client_id:, client_secret:, code:, redirect_uri:, code_verifier:, **)
              response = oauth_connection.post('/login/oauth/access_token', {
                                                 client_id: client_id, client_secret: client_secret,
                                                code: code, redirect_uri: redirect_uri,
                                                code_verifier: code_verifier
                                               })
              { result: response.body }
            end

            def refresh_token(client_id:, client_secret:, refresh_token:, **)
              response = oauth_connection.post('/login/oauth/access_token', {
                                                 client_id: client_id, client_secret: client_secret,
                                                refresh_token: refresh_token,
                                                grant_type: 'refresh_token'
                                               })
              { result: response.body }
            end

            def request_device_code(client_id:, scope: 'repo', **)
              response = oauth_connection.post('/login/device/code', {
                                                 client_id: client_id, scope: scope
                                               })
              { result: response.body }
            end

            def poll_device_code(client_id:, device_code:, interval: 5, timeout: 300, **)
              deadline = Time.now + timeout
              current_interval = interval

              loop do
                response = oauth_connection.post('/login/oauth/access_token', {
                                                   client_id:   client_id,
                                                   device_code: device_code,
                                                   grant_type:  'urn:ietf:params:oauth:grant-type:device_code'
                                                 })
                body = response.body
                return { result: body } if body[:access_token]

                error_key = body[:error]
                case error_key
                when 'authorization_pending'
                  return { error: 'timeout', description: "Device code flow timed out after #{timeout}s" } if Time.now > deadline

                  sleep(current_interval) unless current_interval.zero?
                when 'slow_down'
                  current_interval += 5
                  sleep(current_interval) unless current_interval.zero?
                else
                  return { error: error_key, description: body[:error_description] }
                end
              end
            end

            def revoke_token(client_id:, client_secret:, access_token:, **)
              conn = oauth_connection(client_id: client_id, client_secret: client_secret)
              response = conn.delete("/applications/#{client_id}/token", { access_token: access_token })
              { result: response.status == 204 }
            end

            def oauth_connection(**)
              Faraday.new(url: 'https://github.com') do |conn|
                conn.request :json
                conn.response :json, content_type: /\bjson$/
                conn.headers['Accept'] = 'application/json'
              end
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
