# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Actions
          include Legion::Extensions::Github::Helpers::Client

          def list_workflows(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/actions/workflows", per_page: per_page, page: page
            )
            { result: response.body }
          end

          def get_workflow(owner:, repo:, workflow_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}"
            )
            { result: response.body }
          end

          def list_workflow_runs(owner:, repo:, workflow_id:, status: nil, branch: nil,
                                 per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page, status: status, branch: branch }.compact
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/runs", params
            )
            { result: response.body }
          end

          def get_workflow_run(owner:, repo:, run_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/actions/runs/#{run_id}"
            )
            { result: response.body }
          end

          def trigger_workflow(owner:, repo:, workflow_id:, ref:, inputs: {}, **)
            payload = { ref: ref, inputs: inputs }
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/actions/workflows/#{workflow_id}/dispatches", payload
            )
            { result: response.status == 204 }
          end

          def cancel_workflow_run(owner:, repo:, run_id:, **)
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/cancel"
            )
            { result: [202, 204].include?(response.status) }
          end

          def rerun_workflow(owner:, repo:, run_id:, **)
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun"
            )
            { result: [201, 204].include?(response.status) }
          end

          def rerun_failed_jobs(owner:, repo:, run_id:, **)
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun-failed-jobs"
            )
            { result: [201, 204].include?(response.status) }
          end

          def list_workflow_run_jobs(owner:, repo:, run_id:, filter: 'latest', per_page: 30, page: 1, **)
            params = { filter: filter, per_page: per_page, page: page }
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/jobs", params
            )
            { result: response.body }
          end

          def download_workflow_run_logs(owner:, repo:, run_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/logs"
            )
            { result: { status: response.status, headers: response.headers.to_h, body: response.body } }
          end

          def list_workflow_run_artifacts(owner:, repo:, run_id:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/artifacts", params
            )
            { result: response.body }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
