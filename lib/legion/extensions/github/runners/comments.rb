# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Comments
          include Legion::Extensions::Github::Helpers::Client

          def list_comments(owner:, repo:, issue_number:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", params)
            { result: response.body }
          end

          def get_comment(owner:, repo:, comment_id:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/issues/comments/#{comment_id}")
            { result: response.body }
          end

          def create_comment(owner:, repo:, issue_number:, body:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/issues/#{issue_number}/comments", { body: body })
            { result: response.body }
          end

          def update_comment(owner:, repo:, comment_id:, body:, **)
            response = connection(**).patch("/repos/#{owner}/#{repo}/issues/comments/#{comment_id}", { body: body })
            { result: response.body }
          end

          def delete_comment(owner:, repo:, comment_id:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}/issues/comments/#{comment_id}")
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex)
        end
      end
    end
  end
end
