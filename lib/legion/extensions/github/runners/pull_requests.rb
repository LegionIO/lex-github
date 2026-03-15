# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module PullRequests
          include Legion::Extensions::Github::Helpers::Client

          def list_pull_requests(owner:, repo:, state: 'open', per_page: 30, page: 1, **)
            params = { state: state, per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/pulls", params)
            { result: response.body }
          end

          def get_pull_request(owner:, repo:, pull_number:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}")
            { result: response.body }
          end

          def create_pull_request(owner:, repo:, title:, head:, base:, body: nil, draft: false, **)
            payload = { title: title, head: head, base: base, body: body, draft: draft }
            response = connection(**).post("/repos/#{owner}/#{repo}/pulls", payload)
            { result: response.body }
          end

          def update_pull_request(owner:, repo:, pull_number:, **opts)
            payload = opts.slice(:title, :body, :state, :base)
            response = connection(**opts).patch("/repos/#{owner}/#{repo}/pulls/#{pull_number}", payload)
            { result: response.body }
          end

          def merge_pull_request(owner:, repo:, pull_number:, commit_title: nil, merge_method: 'merge', **)
            payload = { commit_title: commit_title, merge_method: merge_method }.compact
            response = connection(**).put("/repos/#{owner}/#{repo}/pulls/#{pull_number}/merge", payload)
            { result: response.body }
          end

          def list_pull_request_commits(owner:, repo:, pull_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}/commits", params)
            { result: response.body }
          end

          def list_pull_request_files(owner:, repo:, pull_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}/files", params)
            { result: response.body }
          end

          def list_pull_request_reviews(owner:, repo:, pull_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/pulls/#{pull_number}/reviews", params)
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
