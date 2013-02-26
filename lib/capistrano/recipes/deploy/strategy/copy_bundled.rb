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
          configuration.set :rake, lambda { "#{configuration.fetch(:bundle_cmd, "bundle")} exec rake" } unless configuration.exists?(:rake)
          Bundler::Deployment.define_task(configuration, :task, :except => { :no_release => true })
        end

        def deploy!
          logger.info "running :copy_bundled strategy"

          if copy_cache
            run_copy_cache_strategy
            bundle!(:with_cache)
          else
            run_copy_strategy
            bundle!
          end

          create_revision_file

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

        def bundle!(with_cache = false)
          configuration.trigger('strategy:before:bundle')

          bundle_cmd        = configuration.fetch(:bundle_cmd, "bundle")
          bundle_gemfile    = configuration.fetch(:bundle_gemfile, "Gemfile")
          bundle_dir        = configuration.fetch(:bundle_dir, 'vendor/bundle')
          bundle_flags      = configuration.fetch(:bundle_flags, "--deployment --quiet")
          bundle_without    = [*configuration.fetch(:bundle_without, [:development, :test])].compact
          bundle_cache_dir  = with_cache ? copy_cache : destination

          args = ["--gemfile #{File.join(bundle_cache_dir, bundle_gemfile)}"]
          args << "--path #{bundle_dir}" unless bundle_dir.to_s.empty?
          args << bundle_flags.to_s unless bundle_flags.to_s.empty?
          args << "--without #{bundle_without.join(" ")}" unless bundle_without.empty?

          Bundler.with_clean_env do
            logger.info "bundling gems to directory : #{bundle_cache_dir}..."
            run_locally "cd #{bundle_cache_dir} && #{bundle_cmd} install #{args.join(' ').strip}"

            logger.info "packaging gems for bundler in #{bundle_cache_dir}..."
            run_locally "cd #{bundle_cache_dir} && #{bundle_cmd} package --all"
          end

          copy_bundled_cache! if with_cache

          configuration.trigger('strategy:after:bundle')
        end

        def copy_bundled_cache!
          execute "copying additional bundled cache to deployment staging area #{destination}" do
            ['.bundle', 'bin', 'vendor/bundle', 'vendor/cache'].each do |bundle_dir|
              next unless File.exists?(File.join(copy_cache, bundle_dir))
              logger.info "copying cached directory for -> '#{bundle_dir}'"
              Dir.chdir(copy_cache) { copy_directory(bundle_dir) }
            end
          end
        end
      end

    end
  end
end
