# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Issues
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_issues(owner:, repo:, state: 'open', per_page: 30, page: 1, **)
            params = { state: state, per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:issues:#{page}:#{per_page}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/issues", params).body
            end }
          end

          def get_issue(owner:, repo:, issue_number:, **)
            { result: cached_get("github:repo:#{owner}/#{repo}:issues:#{issue_number}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/issues/#{issue_number}").body
            end }
          end

          def create_issue(owner:, repo:, title:, body: nil, labels: [], assignees: [], **)
            payload = { title: title, body: body, labels: labels, assignees: assignees }
            response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/issues", payload)
            cache_write("github:repo:#{owner}/#{repo}:issues:#{response.body['number']}", response.body) if response.body['id']
            { result: response.body }
          end

          def update_issue(owner:, repo:, issue_number:, **opts)
            payload = opts.slice(:title, :body, :state, :labels, :assignees)
            response = connection(owner: owner, repo: repo, **opts).patch("/repos/#{owner}/#{repo}/issues/#{issue_number}", payload)
            cache_write("github:repo:#{owner}/#{repo}:issues:#{issue_number}", response.body) if response.body['id']
            { result: response.body }
          end

          def list_issue_comments(owner:, repo:, issue_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:issues:#{issue_number}:comments:#{page}") do
              connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", params).body
            end }
          end

          def create_issue_comment(owner:, repo:, issue_number:, body:, **)
            response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", { body: body })
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
