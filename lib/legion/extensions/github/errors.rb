# frozen_string_literal: true

module Legion
  module Extensions
    module Github
      class Error < StandardError; end

      class RateLimitError < Error
        attr_reader :reset_at, :credential_fingerprint

        def initialize(message = 'GitHub API rate limit exceeded', reset_at: nil, credential_fingerprint: nil)
          @reset_at = reset_at
          @credential_fingerprint = credential_fingerprint
          super(message)
        end
      end

      class AuthorizationError < Error
        attr_reader :owner, :repo, :attempted_sources

        def initialize(message = 'No authorized credential available', owner: nil, repo: nil,
                       attempted_sources: [])
          @owner = owner
          @repo = repo
          @attempted_sources = attempted_sources
          super(message)
        end
      end

      class ScopeDeniedError < Error
        attr_reader :owner, :repo, :credential_fingerprint, :auth_type

        def initialize(message = 'Credential not authorized for this scope',
                       owner: nil, repo: nil, credential_fingerprint: nil, auth_type: nil)
          @owner = owner
          @repo = repo
          @credential_fingerprint = credential_fingerprint
          @auth_type = auth_type
          super(message)
        end
      end
    end
  end
end
