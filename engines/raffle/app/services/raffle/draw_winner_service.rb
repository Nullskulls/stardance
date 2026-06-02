module Raffle
  # Picks a winner for a week, weighted by each participant's ticket count for
  # that week. Records the winner on the week. Re-running re-draws. Returns the
  # winning Raffle::Participant, or nil if the week had no tickets.
  class DrawWinnerService
    def self.run(week)
      new(week).run
    end

    def initialize(week)
      @week = week
    end

    def run
      @week.with_lock do
        standings = @week.standings
        total_tickets = standings.values.sum
        return if total_tickets.zero?

        winning_ticket = rand(total_tickets) + 1
        running_total = 0
        winner_id, = standings.find do |_participant_id, tickets|
          running_total += tickets
          running_total >= winning_ticket
        end

        @week.paper_trail_event = "draw_winner"
        @week.update!(winner_participant_id: winner_id)
        Raffle::Participant.find(winner_id)
      end
    end
  end
end
