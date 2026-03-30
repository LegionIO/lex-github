# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module PullRequests
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_pull_requests(owner:, repo:, state: 'open', per_page: 30, page: 1, **)
            params = { state: state, per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:pulls:#{page}:#{per_page}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/pulls", params).body
            end }
          end

          def get_pull_request(owner:, repo:, pull_number:, **)
            { result: cached_get("github:repo:#{owner}/#{repo}:pulls:#{pull_number}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}").body
            end }
          end

          def create_pull_request(owner:, repo:, title:, head:, base:, body: nil, draft: false, **)
            payload = { title: title, head: head, base: base, body: body, draft: draft }
            response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/pulls", payload)
            cache_write("github:repo:#{owner}/#{repo}:pulls:#{response.body['number']}", response.body) if response.body['id']
            { result: response.body }
          end

          def update_pull_request(owner:, repo:, pull_number:, **opts)
            payload = opts.slice(:title, :body, :state, :base)
            response = connection(owner: owner, repo: repo, **opts).patch("/repos/#{owner}/#{repo}/pulls/#{pull_number}", payload)
            cache_write("github:repo:#{owner}/#{repo}:pulls:#{pull_number}", response.body) if response.body['id']
            { result: response.body }
          end

          def merge_pull_request(owner:, repo:, pull_number:, commit_title: nil, merge_method: 'merge', **)
            payload = { commit_title: commit_title, merge_method: merge_method }.compact
            response = connection(owner: owner, repo: repo, **).put("/repos/#{owner}/#{repo}/pulls/#{pull_number}/merge", payload)
            cache_invalidate("github:repo:#{owner}/#{repo}:pulls:#{pull_number}")
            { result: response.body }
          end

          def list_pull_request_commits(owner:, repo:, pull_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:pulls:#{pull_number}:commits:#{page}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}/commits", params).body
            end }
          end

          def list_pull_request_files(owner:, repo:, pull_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:pulls:#{pull_number}:files:#{page}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}/files", params).body
            end }
          end

          def list_pull_request_reviews(owner:, repo:, pull_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:pulls:#{pull_number}:reviews:#{page}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}/reviews", params).body
            end }
          end

          def create_review(owner:, repo:, pull_number:, body:, comments: [], event: 'COMMENT', **)
            payload = { event: event, body: body, comments: comments }
            response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/pulls/#{pull_number}/reviews", payload)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
