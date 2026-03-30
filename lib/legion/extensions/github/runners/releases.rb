# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module Runners
        module Releases
          include Legion::Extensions::Github::Helpers::Client

          def list_releases(owner:, repo:, per_page: 30, page: 1, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/releases", per_page: per_page, page: page
            )
            { result: response.body }
          end

          def get_release(owner:, repo:, release_id:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/releases/#{release_id}"
            )
            { result: response.body }
          end

          def get_latest_release(owner:, repo:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/releases/latest"
            )
            { result: response.body }
          end

          def get_release_by_tag(owner:, repo:, tag:, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/releases/tags/#{tag}"
            )
            { result: response.body }
          end

          def create_release(owner:, repo:, tag_name:, name: nil, body: nil, # rubocop:disable Metrics/ParameterLists
                             target_commitish: nil, draft: false, prerelease: false,
                             generate_release_notes: false, **)
            payload = { tag_name: tag_name, name: name, body: body,
                        target_commitish: target_commitish, draft: draft,
                        prerelease: prerelease,
                        generate_release_notes: generate_release_notes }.compact
            response = connection(owner: owner, repo: repo, **).post(
              "/repos/#{owner}/#{repo}/releases", payload
            )
            { result: response.body }
          end

          def update_release(owner:, repo:, release_id:, **opts)
            payload = opts.slice(:tag_name, :name, :body, :draft, :prerelease, :target_commitish)
            response = connection(owner: owner, repo: repo, **opts).patch(
              "/repos/#{owner}/#{repo}/releases/#{release_id}", payload
            )
            { result: response.body }
          end

          def delete_release(owner:, repo:, release_id:, **)
            response = connection(owner: owner, repo: repo, **).delete(
              "/repos/#{owner}/#{repo}/releases/#{release_id}"
            )
            { result: response.status == 204 }
          end

          def list_release_assets(owner:, repo:, release_id:, per_page: 30, page: 1, **)
            response = connection(owner: owner, repo: repo, **).get(
              "/repos/#{owner}/#{repo}/releases/#{release_id}/assets",
              per_page: per_page, page: page
            )
            { result: response.body }
          end

          def delete_release_asset(owner:, repo:, asset_id:, **)
            response = connection(owner: owner, repo: repo, **).delete(
              "/repos/#{owner}/#{repo}/releases/assets/#{asset_id}"
            )
            { result: response.status == 204 }
          end

          include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                      Legion::Extensions::Helpers.const_defined?(:Lex, false)
        end
      end
    end
  end
end
