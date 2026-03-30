# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Branches
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def create_branch(owner:, repo:, branch:, from_ref: 'main', **)
            ref_response = connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/git/ref/heads/#{from_ref}")
            sha = ref_response.body.dig('object', 'sha')

            create_response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/git/refs",
                                                                            { ref: "refs/heads/#{branch}", sha: sha })

            { success: true, ref: create_response.body['ref'], sha: sha }
          rescue StandardError => e
            log.warn(e.message)
            { success: false, error: e.message }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
