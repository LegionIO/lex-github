# frozen_string_literal: true

require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/callback_server'
require 'legion/extensions/github/app/runners/manifest'
require 'legion/extensions/github/app/runners/credential_store'

module Legion
  module Extensions
    module Github
      module CLI
        module App
          include Helpers::Client
          include Github::App::Runners::Manifest
          include Github::App::Runners::CredentialStore

          def setup(name:, url:, webhook_url:, org: nil, **)
            server = Helpers::CallbackServer.new
            server.start
            callback_url = server.redirect_uri

            manifest = generate_manifest(
              name: name, url: url,
              webhook_url: webhook_url,
              callback_url: callback_url
            )[:result]

            url_result = manifest_url(manifest: manifest, org: org)[:result]

            { result: { manifest_url: url_result, callback_port: server.port,
                        message: 'Open the manifest URL in your browser to create the GitHub App' } }
          ensure
            server&.shutdown
          end

          def complete_setup(code:, **)
            result = exchange_manifest_code(code: code)[:result]
            return { error: 'exchange_failed' } unless result&.dig('id')

            if respond_to?(:store_app_credentials, true)
              store_app_credentials(
                app_id:         result['id'].to_s,
                private_key:    result['pem'],
                client_id:      result['client_id'],
                client_secret:  result['client_secret'],
                webhook_secret: result['webhook_secret']
              )
            end

            { result: result }
          end
        end
      end
    end
  end
end
