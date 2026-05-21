module Onboarding
  class ChoiceCardComponent < ViewComponent::Base
    VARIANTS = %i[pair stacked].freeze

    attr_reader :name, :value, :variant

    def initialize(name:, value:, variant: :pair)
      raise ArgumentError, "variant must be one of #{VARIANTS.inspect}, got #{variant.inspect}" unless VARIANTS.include?(variant)

      @name = name
      @value = value
      @variant = variant
    end

    def modifier_class
      "onboarding-choice-card--#{variant}"
    end
  end
end
