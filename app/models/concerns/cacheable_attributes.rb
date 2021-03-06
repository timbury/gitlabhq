module CacheableAttributes
  extend ActiveSupport::Concern

  included do
    after_commit { self.class.expire }
  end

  class_methods do
    def cache_key
      "#{name}:#{Gitlab::VERSION}:#{Gitlab.migrations_hash}:#{Rails.version}".freeze
    end

    # Can be overriden
    def current_without_cache
      last
    end

    # Can be overriden
    def defaults
      {}
    end

    def build_from_defaults(attributes = {})
      new(defaults.merge(attributes))
    end

    def cached
      if RequestStore.active?
        RequestStore[:"#{name}_cached_attributes"] ||= retrieve_from_cache
      else
        retrieve_from_cache
      end
    end

    def retrieve_from_cache
      record = Rails.cache.read(cache_key)
      ensure_cache_setup if record.present?

      record
    end

    def current
      cached_record = cached
      return cached_record if cached_record.present?

      current_without_cache.tap { |current_record| current_record&.cache! }
    rescue => e
      if Rails.env.production?
        Rails.logger.warn("Cached record for #{name} couldn't be loaded, falling back to uncached record: #{e}")
      else
        raise e
      end
      # Fall back to an uncached value if there are any problems (e.g. Redis down)
      current_without_cache
    end

    def expire
      Rails.cache.delete(cache_key)
    rescue
      # Gracefully handle when Redis is not available. For example,
      # omnibus may fail here during gitlab:assets:compile.
    end

    def ensure_cache_setup
      # This is a workaround for a Rails bug that causes attribute methods not
      # to be loaded when read from cache: https://github.com/rails/rails/issues/27348
      define_attribute_methods
    end
  end

  def cache!
    Rails.cache.write(self.class.cache_key, self)
  end
end
