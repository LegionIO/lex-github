# frozen_string_literal: true

require 'json'
require 'openssl'
require 'legion/extensions/github/helpers/client'

module Legion
  module Extensions
    module Github
      module App
        module Runners
          module Webhooks
            include Legion::Extensions::Github::Helpers::Client

            def verify_signature(payload:, signature:, secret:, **)
              return { result: false } if signature.nil? || signature.empty?

              expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, payload)}"
              # Use constant-time comparison to prevent timing side-channel attacks.
              # Pad to equal length so fixed_length_secure_compare can be used safely.
              result = expected.length == signature.length &&
                       OpenSSL.fixed_length_secure_compare(expected, signature)
              { result: result }
            end

            def parse_event(payload:, event_type:, delivery_id:, **)
              parsed = payload.is_a?(String) ? ::JSON.parse(payload) : payload
              { result: { event_type: event_type, delivery_id: delivery_id, payload: parsed } }
            end

            def receive_event(payload:, signature:, secret:, event_type:, delivery_id:, **)
              verified = verify_signature(payload: payload, signature: signature, secret: secret)[:result]
              unless verified
                return { result: { verified: false, event_type: event_type, delivery_id: delivery_id,
                                   payload: nil } }
              end

              parsed = parse_event(payload: payload, event_type: event_type, delivery_id: delivery_id)[:result]
              invalidate_scopes_for_event(event_type: event_type, payload: parsed[:payload])
              { result: parsed.merge(verified: true) }
            end

            SCOPE_INVALIDATION_EVENTS = %w[installation installation_repositories].freeze

            def invalidate_scopes_for_event(event_type:, payload:, **)
              return unless SCOPE_INVALIDATION_EVENTS.include?(event_type.to_s)

              owner = payload&.dig('installation', 'account', 'login')
              return unless owner

              invalidate_all_scopes_for_owner(owner: owner)
            end

            def invalidate_all_scopes_for_owner(owner:)
              known_fingerprints = resolve_known_fingerprints
              known_fingerprints.each do |fp|
                invalidate_scope(fingerprint: fp, owner: owner)
              end
            end

            private

            def resolve_known_fingerprints
              fingerprints = []
              Legion::Extensions::Github::Helpers::Client::CREDENTIAL_RESOLVERS.each do |method|
                next unless respond_to?(method, true)

                result = send(method)
                next unless result

                fp = result.dig(:metadata, :credential_fingerprint)
                fingerprints << fp if fp
              end
              fingerprints.uniq
            rescue StandardError => _e
              []
            end

            include Legion::Extensions::Helpers::Lex if Legion::Extensions.const_defined?(:Helpers, false) &&
                                                        Legion::Extensions::Helpers.const_defined?(:Lex, false)
          end
        end
      end
    end
  end
end
