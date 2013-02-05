require 'bundler/deployment'
require 'capistrano'
require 'capistrano/recipes/deploy/strategy/copy'

module Capistrano
  module Deploy
    module Strategy

      class CopyBundled < Copy

        def initialize(config = {})
          super(config)

          #Initialize with default bundler/capistrano tasks (bundle:install)
          configuration.set :rake, lambda { "#{configuration.fetch(:bundle_cmd, "bundle")} exec rake" }
          Bundler::Deployment.define_task(configuration, :task, :except => { :no_release => true })
        end

        def deploy!
          logger.info "running :copy_bundled strategy"

          copy_cache ? run_copy_cache_strategy : run_copy_strategy

          create_revision_file

          configuration.trigger('strategy:before:bundle')
          #Bundle all gems
          bundle!
          configuration.trigger('strategy:after:bundle')

          logger.info "compressing repository"
          configuration.trigger('strategy:before:compression')
          compress_repository
          configuration.trigger('strategy:after:compression')


          logger.info "distributing packaged repository"

          configuration.trigger('strategy:before:distribute')
          distribute!
          configuration.trigger('strategy:after:distribute')
        ensure
          rollback_changes
        end

        private

        def bundle!
          bundle_cmd      = configuration.fetch(:bundle_cmd, "bundle")
          bundle_gemfile  = configuration.fetch(:bundle_gemfile, "Gemfile")
          bundle_flags    = configuration.fetch(:bundle_flags, "--quiet")
          bundle_without = [*configuration.fetch(:bundle_without, [:development, :test])].compact

          args = ["--gemfile #{File.join(destination, bundle_gemfile)}"]
          args << "--standalone --binstubs"
          args << bundle_flags.to_s
          args << "--without #{bundle_without.join(" ")}" unless bundle_without.empty?

          Bundler.with_clean_env do
            logger.info "installing standalone bundle package (no bundle exec required) : #{destination}..."
            run_locally "cd #{destination} && #{bundle_cmd} install #{args.join(' ').strip}"
          end
        end
      end

    end
  end
end
