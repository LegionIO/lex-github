# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Issues
          include Legion::Extensions::Github::Helpers::Client

          def list_issues(owner:, repo:, state: 'open', per_page: 30, page: 1, **opts)
            params = { state: state, per_page: per_page, page: page }
            response = connection(**opts).get("/repos/#{owner}/#{repo}/issues", params)
            { result: response.body }
          end

          def get_issue(owner:, repo:, issue_number:, **opts)
            response = connection(**opts).get("/repos/#{owner}/#{repo}/issues/#{issue_number}")
            { result: response.body }
          end

          def create_issue(owner:, repo:, title:, body: nil, labels: [], assignees: [], **opts)
            payload = { title: title, body: body, labels: labels, assignees: assignees }
            response = connection(**opts).post("/repos/#{owner}/#{repo}/issues", payload)
            { result: response.body }
          end

          def update_issue(owner:, repo:, issue_number:, **opts)
            payload = opts.slice(:title, :body, :state, :labels, :assignees)
            response = connection(**opts).patch("/repos/#{owner}/#{repo}/issues/#{issue_number}", payload)
            { result: response.body }
          end

          def list_issue_comments(owner:, repo:, issue_number:, per_page: 30, page: 1, **opts)
            params = { per_page: per_page, page: page }
            response = connection(**opts).get("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", params)
            { result: response.body }
          end

          def create_issue_comment(owner:, repo:, issue_number:, body:, **opts)
            response = connection(**opts).post("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", { body: body })
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
