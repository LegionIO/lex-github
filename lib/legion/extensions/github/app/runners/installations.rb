# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Installations
            include Legion::Extensions::Github::Helpers::Client

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

            def list_installation_repos(per_page: 30, page: 1, **)
              response = connection(**).get('/installation/repositories',
                                           per_page: per_page, page: page)
              { result: response.body }
            end

            def suspend_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.put("/app/installations/#{installation_id}/suspended")
              { result: response.status == 204 }
            end

            def unsuspend_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.delete("/app/installations/#{installation_id}/suspended")
              { result: response.status == 204 }
            end

            def delete_installation(jwt:, installation_id:, **)
              conn = connection(token: jwt, **)
              response = conn.delete("/app/installations/#{installation_id}")
              { result: response.status == 204 }
            end
          end
        end
      end
    end
  end
end
