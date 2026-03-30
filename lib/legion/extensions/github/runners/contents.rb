# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Contents
          include Legion::Extensions::Github::Helpers::Client

          def commit_files(owner:, repo:, branch:, files:, message:, **)
            conn = connection(**)

            ref = conn.get("/repos/#{owner}/#{repo}/git/ref/heads/#{branch}")
            commit_sha = ref.body.dig('object', 'sha')

            commit = conn.get("/repos/#{owner}/#{repo}/git/commits/#{commit_sha}")
            base_tree_sha = commit.body.dig('tree', 'sha')

            tree_items = files.map do |f|
              { path: f[:path], mode: '100644', type: 'blob', content: f[:content] }
            end

            new_tree = conn.post("/repos/#{owner}/#{repo}/git/trees",
                                 { base_tree: base_tree_sha, tree: tree_items })

            new_commit = conn.post("/repos/#{owner}/#{repo}/git/commits",
                                   { message: message, tree: new_tree.body['sha'], parents: [commit_sha] })

            conn.patch("/repos/#{owner}/#{repo}/git/refs/heads/#{branch}",
                       { sha: new_commit.body['sha'] })

            { success: true, commit_sha: new_commit.body['sha'], tree_sha: new_tree.body['sha'] }
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
