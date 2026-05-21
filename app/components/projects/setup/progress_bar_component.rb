module Projects
  module Setup
    class ProgressBarComponent < ViewComponent::Base
      STEPS = %i[idea details link].freeze
      STEP_FRACTIONS = STEPS.each_with_index.to_h { |slug, i| [ slug, (i + 1).to_f / STEPS.size ] }.freeze

      # Per-action mapping into the visible 3-phase progress.
      ACTION_TO_STEP = {
        idea:     :idea,
        name:     :details,
        missions: :details,
        link:     :link
      }.freeze

      attr_reader :action

      def initialize(action:)
        @action = action.to_sym
        raise ArgumentError, "Unknown setup progress action: #{action.inspect}" unless ACTION_TO_STEP.key?(@action)
      end

      def step
        ACTION_TO_STEP.fetch(action)
      end

      def fill_percentage
        (STEP_FRACTIONS.fetch(step, 0) * 100).round
      end

      def previous_fill_percentage
        idx = STEPS.index(step)
        return 0 if idx.nil?

        prev_idx = going_back? ? idx + 1 : idx - 1
        return 0 if prev_idx.negative?
        return 100 if prev_idx >= STEPS.size

        (STEP_FRACTIONS.fetch(STEPS[prev_idx], 0) * 100).round
      end

      def first_appearance?
        action == :idea && !going_back?
      end

      def back_path
        case action
        when :idea, :link
          append_back_param(helpers.back_path)
        when :name, :missions
          helpers.projects_setup_path(back: 1)
        end
      end

      def going_back?
        helpers.params[:back].to_s == "1"
      end

      private

      def append_back_param(path)
        return path if path.blank?
        separator = path.include?("?") ? "&" : "?"
        "#{path}#{separator}back=1"
      end
    end
  end
end
