# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Deployments
          include Legion::Extensions::Github::Helpers::Client

          def list_deployments(owner:, repo:, environment: nil, ref: nil, per_page: 30, page: 1, **)
            params = { environment: environment, ref: ref,
                       per_page: per_page, page: page }.compact
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/deployments", params
            )
            { result: response.body }
          end

          def get_deployment(owner:, repo:, deployment_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/deployments/#{deployment_id}"
            )
            { result: response.body }
          end

          def create_deployment(owner:, repo:, ref:, environment: 'production',
                                description: nil, auto_merge: true, required_contexts: nil, **)
            payload = { ref: ref, environment: environment, description: description,
                        auto_merge: auto_merge, required_contexts: required_contexts }.compact
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/deployments", payload
            )
            { result: response.body }
          end

          def delete_deployment(owner:, repo:, deployment_id:, **)
            response = connection(owner: owner, repo: repo, **).delete(
              "/repos/#{owner}/#{repo}/deployments/#{deployment_id}"
            )
            { result: response.status == 204 }
          end

          def list_deployment_statuses(owner:, repo:, deployment_id:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/deployments/#{deployment_id}/statuses", params
            )
            { result: response.body }
          end

          def create_deployment_status(owner:, repo:, deployment_id:, state:,
                                       description: nil, environment_url: nil, log_url: nil, **)
            payload = { state: state, description: description,
                        environment_url: environment_url, log_url: log_url }.compact
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/deployments/#{deployment_id}/statuses", payload
            )
            { result: response.body }
          end

          def get_deployment_status(owner:, repo:, deployment_id:, status_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/deployments/#{deployment_id}/statuses/#{status_id}"
            )
            { result: response.body }
          end
        end
      end
    end
  end
end
