# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'

module Legion
  module Extensions
    module Github
      module Runners
        module Labels
          include Legion::Extensions::Github::Helpers::Client
          include Legion::Extensions::Github::Helpers::Cache

          def list_labels(owner:, repo:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            { result: cached_get("github:repo:#{owner}/#{repo}:labels:#{page}") { connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/labels", params).body } }
          end

          def get_label(owner:, repo:, name:, **)
            { result: cached_get("github:repo:#{owner}/#{repo}:labels:#{name}") { connection(owner: owner, repo: repo, **).get("/repos/#{owner}/#{repo}/labels/#{name}").body } }
          end

          def create_label(owner:, repo:, name:, color:, description: nil, **)
            payload = { name: name, color: color, description: description }.compact
            response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/labels", payload)
            cache_write("github:repo:#{owner}/#{repo}:labels:#{name}", response.body) if response.body['id']
            { result: response.body }
          end

          def update_label(owner:, repo:, name:, new_name: nil, color: nil, description: nil, **)
            payload = { new_name: new_name, color: color, description: description }.compact
            response = connection(owner: owner, repo: repo, **).patch("/repos/#{owner}/#{repo}/labels/#{name}", payload)
            cache_write("github:repo:#{owner}/#{repo}:labels:#{name}", response.body) if response.body['id']
            { result: response.body }
          end

          def delete_label(owner:, repo:, name:, **)
            response = connection(owner: owner, repo: repo, **).delete("/repos/#{owner}/#{repo}/labels/#{name}")
            cache_invalidate("github:repo:#{owner}/#{repo}:labels:#{name}") if response.status == 204
            { result: response.status == 204 }
          end

          def add_labels_to_issue(owner:, repo:, issue_number:, labels:, **)
            response = connection(owner: owner, repo: repo, **).post("/repos/#{owner}/#{repo}/issues/#{issue_number}/labels", { labels: labels })
            { result: response.body }
          end

          def remove_label_from_issue(owner:, repo:, issue_number:, name:, **)
            response = connection(owner: owner, repo: repo, **).delete("/repos/#{owner}/#{repo}/issues/#{issue_number}/labels/#{name}")
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
