require "test_helper"

class DiscoverRail::FabricatePromoWidgetTest < ViewComponent::TestCase
  setup do
    Flipper.enable(:platform_ads)
    Flipper.enable(:"fabricate-promo")
  end

  teardown do
    Flipper.disable(:"fabricate-promo")
    Flipper.disable(:platform_ads)
  end

  test "registers under the fabricate_promo slug" do
    assert_equal DiscoverRail::FabricatePromoWidget, DiscoverRail::BaseWidget.registry[:fabricate_promo]
  end

  test "renders the big red button as a tracked link to fabricate, with the blast door ready" do
    render_inline(DiscoverRail::FabricatePromoWidget.new)

    assert_selector "section.fabricate-promo[data-controller='fabricate-promo'][data-fabricate-promo-url-value='#{DiscoverRail::FabricatePromoWidget::URL}'][data-fabricate-promo-cutscene-value='false']"
    assert_selector "a.fabricate-promo__card[href='/promos/fabricate']" do
      assert_selector ".fabricate-promo__grid img.fabricate-promo__grid-image[alt='']"
      %w[default hover pressed].each do |state|
        assert_selector ".fabricate-promo__button img.fabricate-promo__button-state--#{state}[width='212'][height='154'][alt='']"
      end
      assert_selector ".fabricate-promo__title", text: "Fabricate"
      assert_selector ".fabricate-promo__pitch", text: "Design any hardware project and we'll pay for it."
      assert_no_selector ".fabricate-promo__runtime"
    end
    assert_match %r{<template data-fabricate-promo-target="door">.*fabricate-door__leaf--left.*fabricate-door__leaf--right.*</template>}m,
      rendered_content
  end

  test "is hidden while the fabricate promo flag is off" do
    Flipper.disable(:"fabricate-promo")

    render_inline(DiscoverRail::FabricatePromoWidget.new)

    assert_no_selector ".fabricate-promo"
  end

  test "the cutscene edition has its own flag and plays the cutscene" do
    assert_equal DiscoverRail::FabricateCutscenePromoWidget, DiscoverRail::BaseWidget.registry[:fabricate_cutscene_promo]

    render_inline(DiscoverRail::FabricateCutscenePromoWidget.new)
    assert_no_selector ".fabricate-promo"

    Flipper.enable(:"fabricate-cutscene-promo")
    render_inline(DiscoverRail::FabricateCutscenePromoWidget.new)
    assert_selector "section.fabricate-promo[data-fabricate-promo-cutscene-value='true']"
    assert_selector "a.fabricate-promo__card[href='/promos/fabricate'] .fabricate-promo__runtime", text: "unskippable"
  ensure
    Flipper.disable(:"fabricate-cutscene-promo")
  end
end
