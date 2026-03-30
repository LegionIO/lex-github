# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Checks
          include Legion::Extensions::Github::Helpers::Client

          def create_check_run(owner:, repo:, name:, head_sha:, status: nil, # rubocop:disable Metrics/ParameterLists
                               conclusion: nil, output: nil, details_url: nil, **)
            payload = { name: name, head_sha: head_sha, status: status,
                        conclusion: conclusion, output: output, details_url: details_url }.compact
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/check-runs", payload
            )
            { result: response.body }
          end

          def update_check_run(owner:, repo:, check_run_id:, **opts)
            payload = opts.slice(:name, :status, :conclusion, :output, :details_url,
                                 :started_at, :completed_at)
            response = connection(owner: owner, repo: repo, **opts).patch(
              "/repos/#{owner}/#{repo}/check-runs/#{check_run_id}", payload
            )
            { result: response.body }
          end

          def get_check_run(owner:, repo:, check_run_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/check-runs/#{check_run_id}"
            )
            { result: response.body }
          end

          def list_check_runs_for_ref(owner:, repo:, ref:, check_name: nil, status: nil,
                                      per_page: 30, page: 1, **)
            params = { check_name: check_name, status: status,
                       per_page: per_page, page: page }.compact
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/commits/#{ref}/check-runs", params
            )
            { result: response.body }
          end

          def list_check_suites_for_ref(owner:, repo:, ref:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/commits/#{ref}/check-suites", params
            )
            { result: response.body }
          end

          def get_check_suite(owner:, repo:, check_suite_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/check-suites/#{check_suite_id}"
            )
            { result: response.body }
          end

          def rerequest_check_suite(owner:, repo:, check_suite_id:, **)
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/check-suites/#{check_suite_id}/rerequest"
            )
            { result: [201, 204].include?(response.status) }
          end

          def list_check_run_annotations(owner:, repo:, check_run_id:, per_page: 30, page: 1, **)
            params = { per_page: per_page, page: page }
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/check-runs/#{check_run_id}/annotations", params
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
