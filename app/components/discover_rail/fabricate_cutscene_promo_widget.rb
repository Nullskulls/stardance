# frozen_string_literal: true

module DiscoverRail
  # Fabricate's ad as a minute-long, fullscreen, unskippable cinematic. Shares the card and the
  # blast door with FabricatePromoWidget, and only plays the cutscene first.
  class FabricateCutscenePromoWidget < FabricatePromoWidget
    register_as :fabricate_cutscene_promo

    def render?
      helpers.platform_ads_enabled?(user) && Flipper.enabled?(:"fabricate-cutscene-promo", user)
    end

    def cutscene?
      true
    end
  end
end
