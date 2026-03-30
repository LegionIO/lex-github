# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Labels
          include Legion::Extensions::Github::Helpers::Client

          def list_labels(owner:, repo:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(**).get("/repos/#{owner}/#{repo}/labels", params)
            { result: response.body }
          end

          def get_label(owner:, repo:, name:, **)
            response = connection(**).get("/repos/#{owner}/#{repo}/labels/#{name}")
            { result: response.body }
          end

          def create_label(owner:, repo:, name:, color:, description: nil, **)
            payload = { name: name, color: color, description: description }.compact
            response = connection(**).post("/repos/#{owner}/#{repo}/labels", payload)
            { result: response.body }
          end

          def update_label(owner:, repo:, name:, new_name: nil, color: nil, description: nil, **)
            payload = { new_name: new_name, color: color, description: description }.compact
            response = connection(**).patch("/repos/#{owner}/#{repo}/labels/#{name}", payload)
            { result: response.body }
          end

          def delete_label(owner:, repo:, name:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}/labels/#{name}")
            { result: response.status == 204 }
          end

          def add_labels_to_issue(owner:, repo:, issue_number:, labels:, **)
            response = connection(**).post("/repos/#{owner}/#{repo}/issues/#{issue_number}/labels", { labels: labels })
            { result: response.body }
          end

          def remove_label_from_issue(owner:, repo:, issue_number:, name:, **)
            response = connection(**).delete("/repos/#{owner}/#{repo}/issues/#{issue_number}/labels/#{name}")
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
