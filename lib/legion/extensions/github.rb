# frozen_string_literal: true

require 'legion/extensions/github/version'
require 'legion/extensions/github/errors'
require 'legion/extensions/github/middleware/rate_limit'
require 'legion/extensions/github/middleware/scope_probe'
require 'legion/extensions/github/middleware/credential_fallback'
require 'legion/extensions/github/helpers/client'
require 'legion/extensions/github/helpers/cache'
require 'legion/extensions/github/helpers/token_cache'
require 'legion/extensions/github/helpers/scope_registry'
require 'legion/extensions/github/app/runners/auth'
require 'legion/extensions/github/app/runners/webhooks'
require 'legion/extensions/github/app/runners/manifest'
require 'legion/extensions/github/app/runners/installations'
require 'legion/extensions/github/app/runners/credential_store'
require 'legion/extensions/github/oauth/runners/auth'
require 'legion/extensions/github/helpers/callback_server'
require 'legion/extensions/github/helpers/browser_auth'
require 'legion/extensions/github/cli/auth'
require 'legion/extensions/github/cli/app'
require 'legion/extensions/github/runners/repositories'
require 'legion/extensions/github/runners/issues'
require 'legion/extensions/github/runners/pull_requests'
require 'legion/extensions/github/runners/users'
require 'legion/extensions/github/runners/organizations'
require 'legion/extensions/github/runners/gists'
require 'legion/extensions/github/runners/search'
require 'legion/extensions/github/runners/commits'
require 'legion/extensions/github/runners/labels'
require 'legion/extensions/github/runners/comments'
require 'legion/extensions/github/runners/branches'
require 'legion/extensions/github/runners/contents'
require 'legion/extensions/github/runners/actions'
require 'legion/extensions/github/runners/checks'
require 'legion/extensions/github/runners/releases'
require 'legion/extensions/github/runners/deployments'
require 'legion/extensions/github/runners/repository_webhooks'
require 'legion/extensions/github/client'
require 'legion/extensions/github/cli/runner'

module Legion
  module Extensions
    module Github
      extend Legion::Extensions::Core if Legion::Extensions.const_defined? :Core, false

      CLI_COMMANDS = {
        'auth' => {
          class_name: 'Legion::Extensions::Github::CLI::AuthRunner',
          methods:    {
            'login'  => { desc: 'Authenticate with GitHub via OAuth browser flow', args: '' },
            'status' => { desc: 'Show current GitHub authentication status', args: '' }
          }
        },
        'app'  => {
          class_name: 'Legion::Extensions::Github::CLI::AppRunner',
          methods:    {
            'setup'          => { desc: 'Create a new GitHub App via manifest flow', args: '' },
            'complete_setup' => { desc: 'Complete GitHub App setup with authorization code', args: '' }
          }
        }
      }.freeze

      begin
        manifest_dir = ::File.expand_path('~/.legionio/cache/cli')
        manifest_path = ::File.join(manifest_dir, 'lex-github.json')
        unless ::File.exist?(manifest_path) && ::File.read(manifest_path).include?(VERSION)
          require 'fileutils'
          ::FileUtils.mkdir_p(manifest_dir)
          serialized = CLI_COMMANDS.transform_values do |cmd|
            { 'class'   => cmd[:class_name],
              'methods' => cmd[:methods].transform_values { |m| { 'desc' => m[:desc], 'args' => m[:args] } } }
          end
          ::File.write(manifest_path, ::JSON.pretty_generate(
                                        'gem' => 'lex-github', 'version' => VERSION,
                                        'alias' => 'github', 'commands' => serialized
                                      ))
        end
      rescue StandardError => e
        warn "[lex-github] CLI manifest write skipped: #{e.message}" if ENV['LEGION_DEBUG']
      end
    end
  end
end
