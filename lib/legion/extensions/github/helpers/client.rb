# frozen_string_literal: true

require 'faraday'

module Legion
  module Extensions
    module Github
      module Helpers
        module Client
          def connection(api_url: 'https://api.github.com', token: nil, **_opts)
            Faraday.new(url: api_url) do |conn|
              conn.request :json
              conn.response :json, content_type: /\bjson$/
              conn.headers['Accept'] = 'application/vnd.github+json'
              conn.headers['Authorization'] = "Bearer #{token}" if token
              conn.headers['X-GitHub-Api-Version'] = '2022-11-28'
            end
          end
        end
      end
    end
  end
end
