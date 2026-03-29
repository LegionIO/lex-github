# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Branches
          include Legion::Extensions::Github::Helpers::Client

          def create_branch(owner:, repo:, branch:, from_ref: 'main', **)
            ref_response = connection(**).get("/repos/#{owner}/#{repo}/git/ref/heads/#{from_ref}")
            sha = ref_response.body.dig('object', 'sha')

            create_response = connection(**).post("/repos/#{owner}/#{repo}/git/refs",
                                                  { ref: "refs/heads/#{branch}", sha: sha })

            { success: true, ref: create_response.body['ref'], sha: sha }
          rescue StandardError => e
            log.warn(e.message) if respond_to?(:log, true)
            { success: false, error: e.message }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
