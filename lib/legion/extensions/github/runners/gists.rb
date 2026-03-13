# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Gists
          include Legion::Extensions::Github::Helpers::Client

          def list_gists(per_page: 30, page: 1, **opts)
            response = connection(**opts).get('/gists', per_page: per_page, page: page)
            { result: response.body }
          end

          def get_gist(gist_id:, **opts)
            response = connection(**opts).get("/gists/#{gist_id}")
            { result: response.body }
          end

          def create_gist(files:, description: nil, public: false, **opts)
            payload = { files: files, description: description, public: public }
            response = connection(**opts).post('/gists', payload)
            { result: response.body }
          end

          def update_gist(gist_id:, files: nil, description: nil, **opts)
            payload = { files: files, description: description }.compact
            response = connection(**opts).patch("/gists/#{gist_id}", payload)
            { result: response.body }
          end

          def delete_gist(gist_id:, **opts)
            response = connection(**opts).delete("/gists/#{gist_id}")
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
