module Admin
  # Where every devlogged hour went, as a Sankey. The figures cover all time,
  # so they are cached for an hour and refreshed on demand.
  class HourFunnelController < Admin::ApplicationController
    CACHE_KEY = "admin_hour_funnel".freeze
    CACHE_TTL = 1.hour

    def show
      authorize :hour_funnel

      @funnel = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { HourFunnel.new.to_h }
      @generated_at = Rails.cache.fetch("#{CACHE_KEY}/generated_at", expires_in: CACHE_TTL) { Time.current }
    end

    def refresh
      authorize :hour_funnel

      Rails.cache.delete(CACHE_KEY)
      Rails.cache.delete("#{CACHE_KEY}/generated_at")
      redirect_to admin_hour_funnel_path, notice: "Hour funnel recomputed."
    end
  end
end
