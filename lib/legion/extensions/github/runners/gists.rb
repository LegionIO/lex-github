# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Gists
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_gists(per_page: 30, page: 1, **)
            cred = resolve_credential
            fp = cred&.dig(:metadata, :credential_fingerprint) || 'anonymous'
            { result: cached_get("github:user:gists:#{fp}:#{page}:#{per_page}") { connection(**).get('/gists', per_page: per_page, page: page).body } }
          end

          def get_gist(gist_id:, **)
            { result: cached_get("github:gist:#{gist_id}") { connection(**).get("/gists/#{gist_id}").body } }
          end

          def create_gist(files:, description: nil, public: false, **)
            payload = { files: files, description: description, public: public }
            response = connection(**).post('/gists', payload)
            cache_write("github:gist:#{response.body['id']}", response.body) if response.body['id']
            { result: response.body }
          end

          def update_gist(gist_id:, files: nil, description: nil, **)
            payload = { files: files, description: description }.compact
            response = connection(**).patch("/gists/#{gist_id}", payload)
            cache_write("github:gist:#{gist_id}", response.body) if response.body['id']
            { result: response.body }
          end

          def delete_gist(gist_id:, **)
            response = connection(**).delete("/gists/#{gist_id}")
            cache_invalidate("github:gist:#{gist_id}") if response.status == 204
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
