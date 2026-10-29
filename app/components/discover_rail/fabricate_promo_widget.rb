# frozen_string_literal: true

module DiscoverRail
  class FabricatePromoWidget < BaseWidget
    register_as :fabricate_promo

    def render?
      helpers.platform_ads_enabled?(user) && Flipper.enabled?(:"fabricate-promo", user)
    end

    # Slams the blast door and opens it on Fabricate. The cutscene edition overrides this.
    def cutscene?
      false
    end

    URL = "https://fabricate.hackclub.com/home?utm_source=stardance&utm_medium=discover_rail"
    # Ahoy event recorded by PromosController#fabricate on every click.
    CLICK_EVENT = "fabricate_promo_clicked"
  end
end
