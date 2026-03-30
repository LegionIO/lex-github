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
              { result: expected == signature }
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
              { result: parsed.merge(verified: true) }
            end
          end
        end
      end
    end
  end
end
