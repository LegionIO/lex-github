# frozen_string_literal: true

require 'jwt'
require 'openssl'
require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Auth
            include Legion::Extensions::Github::Helpers::Client

            def generate_jwt(app_id:, private_key:, **)
              key = OpenSSL::PKey::RSA.new(private_key)
              now = Time.now.to_i
              payload = { iat: now - 60, exp: now + (10 * 60), iss: app_id.to_s }
              token = JWT.encode(payload, key, 'RS256')
              { result: token }
            end

            def create_installation_token(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.post("/app/installations/#{installation_id}/access_tokens")
              { result: response.body }
            end

            def list_installations(jwt:, per_page: 30, page: 1, **)
              conn = connection(token: jwt, **)
              response = conn.get('/app/installations', per_page: per_page, page: page)
              { result: response.body }
            end

            def get_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.get("/app/installations/#{installation_id}")
              { result: response.body }
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
