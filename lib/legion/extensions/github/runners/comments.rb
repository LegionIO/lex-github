# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Comments
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_comments(owner:, repo:, issue_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:issues:#{issue_number}:comments:#{page}:#{per_page}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", params).body
            end }
          end

          def get_comment(owner:, repo:, comment_id:, **)
            { result: cached_get("github:repo:#{owner}/#{repo}:comments:#{comment_id}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/issues/comments/#{comment_id}").body
            end }
          end

          def create_comment(owner:, repo:, issue_number:, body:, **)
            response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", { body: body })
            { result: response.body }
          end

          def update_comment(owner:, repo:, comment_id:, body:, **)
            response = connection(owner: owner, repo: repo, **).patch("/repos/#{owner}/#{repo}/issues/comments/#{comment_id}", { body: body })
            cache_write("github:repo:#{owner}/#{repo}:comments:#{comment_id}", response.body) if response.body['id']
            { result: response.body }
          end

          def delete_comment(owner:, repo:, comment_id:, **)
            response = connection(owner: owner, repo: repo, **).delete("/repos/#{owner}/#{repo}/issues/comments/#{comment_id}")
            cache_invalidate("github:repo:#{owner}/#{repo}:comments:#{comment_id}") if response.status == 204
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
