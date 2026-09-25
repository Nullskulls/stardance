module Admin
  # Where every devlogged hour went: deleted, never shipped, or shipped and
  # then through ship certification, the YSWS review, the integrity check
  # and the Airtable sync. Built as Sankey nodes and links in two units, hours
  # and ships, so the same graph reads as "how much time" or "how many ships".
  #
  # All time, software only. Hardware pays for build time after a funding
  # cutoff and skips integrity, so it needs its own funnel.
  #
  # Every ship is in exactly one state at a time, so the ship unit only flows
  # through nodes that take a whole ship out of the funnel. A markdown or a
  # deduction removes hours but the ship carries on, so those nodes carry a
  # ships_affected count instead of a ship flow.
  class HourFunnel
    Node = Data.define(:key, :label, :stage, :kind, :partial)

    # Order matters twice: it is the vertical order inside a Sankey column,
    # and the kept node of each stage comes first so the main flow stays on
    # top. kind is what the chart colours: kept (flows on), held (waiting on
    # someone), lost (never comes back).
    NODES = [
      Node.new("devlogged", "Devlogged", "devlogged", "kept", false),
      Node.new("shipped", "Shipped", "shipped", "kept", false),
      Node.new("unshipped", "Not shipped yet", "shipped", "held", false),
      Node.new("deleted", "Devlog deleted", "shipped", "lost", false),
      Node.new("project_gone", "Project deleted or banned", "shipped", "lost", false),
      Node.new("ship_approved", "Ship approved", "ship_cert", "kept", false),
      Node.new("ship_approved_after_return", "Ship approved after a return", "ship_cert", "kept", false),
      Node.new("ship_pending", "Ship cert pending", "ship_cert", "held", false),
      Node.new("ship_resubmitted", "Resubmitted, pending again", "ship_cert", "held", false),
      Node.new("ship_returned", "Returned, waiting on builder", "ship_cert", "held", false),
      Node.new("ship_withdrawn", "Withdrawn by undo", "ship_cert", "held", false),
      Node.new("ship_rejected", "Ship rejected", "ship_cert", "lost", false),
      Node.new("ysws_approved", "YSWS approved", "ysws", "kept", false),
      Node.new("ysws_pending", "YSWS review pending", "ysws", "held", false),
      Node.new("ysws_marked_down", "Marked down by YSWS", "ysws", "lost", true),
      Node.new("ysws_rejected", "Devlogs rejected by YSWS", "ysws", "lost", true),
      Node.new("ysws_under_minimum", "Review rejected (under 6 min)", "ysws", "lost", false),
      Node.new("integrity_passed", "Integrity passed", "integrity", "kept", false),
      Node.new("integrity_pending", "Integrity pending", "integrity", "held", false),
      Node.new("integrity_deducted", "Deducted by integrity", "integrity", "lost", true),
      Node.new("integrity_banned", "Banned by integrity", "integrity", "lost", false),
      Node.new("airtable_synced", "In Airtable", "airtable", "kept", false),
      Node.new("airtable_unsynced", "Awaiting Airtable sync", "airtable", "held", false),
      Node.new("payout_basis", "Within 10h/devlog payout cap", "payout_cap", "kept", false),
      Node.new("over_payout_cap", "Over 10h/devlog payout cap", "payout_cap", "lost", true)
    ].freeze

    NODES_BY_KEY = NODES.index_by(&:key).freeze

    PAYOUT_CAP_HOURS = ::Post::ShipEvent::MAX_PAYOUT_HOURS_PER_DEVLOG

    AUTO_REJECT_JUSTIFICATIONS = ::Certification::YswsReviewRejector::JUSTIFICATIONS.values.freeze

    SHIP_STATUSES = ::Certification::Ship.statuses.invert.freeze
    INTEGRITY_STATUSES = ::Certification::Integrity.statuses.invert.freeze
    INTEGRITY_PASSED = %w[auto_passed manually_passed].freeze

    ShipRow = Struct.new(
      :ship_event_id, :project_deleted, :certification_status, :review_status, :recert_from_ysws, :bounced,
      :ysws_reviewed, :ysws_returned, :approved_minutes_all, :airtable_synced, :in_unified_db,
      :integrity_status, :deduction_minutes,
      :hours, :devlogs, :raw_over_cap_hours, :over_cap_devlogs, :rejected_hours, :auto_rejected_hours,
      :approved_hours, :marked_down_hours, :unreviewed_hours, :certified_over_cap_hours,
      keyword_init: true
    )

    def to_h
      @hours = Hash.new(0.0)
      @ships = Hash.new(0)
      @ships_affected = Hash.new(0)
      @links = Hash.new { |h, k| h[k] = { hours: 0.0, ships: 0 } }
      @details = Hash.new(0)

      add_devlog_stage
      ship_rows.each { |row| add_ship(row) }

      {
        unit_labels: { hours: "hours", ships: "ships" },
        nodes: NODES.map { |node| node_payload(node) },
        links: @links.map { |(source, target), value| { source: source, target: target, hours: round(value[:hours]), ships: value[:ships] } },
        details: @details.transform_values { |value| value.is_a?(Float) ? round(value) : value }
      }
    end

    private

    def node_payload(node)
      {
        key: node.key, label: node.label, stage: node.stage, kind: node.kind, partial: node.partial,
        hours: round(@hours[node.key]),
        ships: node.partial ? nil : @ships[node.key],
        ships_affected: node.partial ? @ships_affected[node.key] : nil
      }
    end

    def round(value) = value.to_f.round(1)

    # ---- stage A/B: every devlog, deleted or not ---------------------------

    def add_devlog_stage
      row = ::ActiveRecord::Base.connection.select_one(devlog_stage_sql)

      @hours["devlogged"] = row["gross"].to_f
      flow("devlogged", "deleted", hours: row["deleted_before_ship"].to_f + row["deleted_after_ship"].to_f)
      flow("devlogged", "project_gone", hours: row["banned"].to_f + row["project_deleted"].to_f)
      flow("devlogged", "unshipped", hours: row["unshipped_never"].to_f + row["unshipped_after_ship"].to_f)
      flow("devlogged", "shipped", hours: row["shipped"].to_f)

      %w[deleted_before_ship deleted_after_ship banned project_deleted unshipped_never unshipped_after_ship].each do |key|
        @details["#{key}_hours"] = row[key].to_f
      end
      @details["devlogs"] = row["devlogs"].to_i
    end

    # ---- stages C..F: one ship at a time -----------------------------------

    def add_ship(row)
      if row.project_deleted
        @ships["project_gone"] += 1
        return
      end

      @ships["shipped"] += 1
      record_payout_cap(row)

      ship_node = ship_cert_node(row)
      flow("shipped", ship_node, hours: row.hours, ships: 1)
      @details["recert_from_ysws_hours"] += row.hours if row.recert_from_ysws
      @details["recert_from_ysws_ships"] += 1 if row.recert_from_ysws
      return unless ship_node.start_with?("ship_approved")

      approved = add_ysws(row, ship_node)
      return if approved.nil?

      net = add_integrity(row, approved)
      return if net.nil?

      add_airtable(row, net)
    end

    # A rejected ship event is an admin forcing the project state, so it wins
    # over whatever the latest review row says. Without a review row (ships
    # older than the review queue) the ship event's own status stands in.
    def ship_cert_node(row)
      return "ship_rejected" if row.certification_status == "rejected"

      case row.review_status
      when nil
        { "approved" => "ship_approved", "returned" => "ship_returned" }.fetch(row.certification_status, "ship_pending")
      when "pending" then row.bounced ? "ship_resubmitted" : "ship_pending"
      when "approved" then row.bounced ? "ship_approved_after_return" : "ship_approved"
      when "returned" then "ship_returned"
      when "withdrawn" then "ship_withdrawn"
      else "ship_pending"
      end
    end

    # Returns the approved hours that carry on to integrity, or nil when the
    # ship stops here.
    def add_ysws(row, from)
      unless row.ysws_reviewed && !row.ysws_returned
        flow(from, "ysws_pending", hours: row.hours, ships: 1)
        return nil
      end

      flow(from, "ysws_pending", hours: row.unreviewed_hours) if row.unreviewed_hours.positive?
      flow(from, "ysws_rejected", hours: row.rejected_hours, affected: 1) if row.rejected_hours.positive?
      flow(from, "ysws_marked_down", hours: row.marked_down_hours, affected: 1) if row.marked_down_hours.positive?
      @details["auto_rejected_hours"] += row.auto_rejected_hours

      if row.approved_minutes_all < ::Certification::Ysws::MIN_APPROVED_MINUTES
        flow(from, "ysws_under_minimum", hours: row.approved_hours, ships: 1)
        return nil
      end

      flow(from, "ysws_approved", hours: row.approved_hours, ships: 1)
      row.approved_hours
    end

    def add_integrity(row, approved)
      case row.integrity_status
      when *INTEGRITY_PASSED
        flow("ysws_approved", "integrity_passed", hours: approved, ships: 1)
        approved
      when "banned"
        flow("ysws_approved", "integrity_banned", hours: approved, ships: 1)
        nil
      when "deducted"
        deducted = [ row.deduction_minutes.to_i / 60.0, approved ].min
        flow("ysws_approved", "integrity_deducted", hours: deducted, affected: 1)
        flow("ysws_approved", "integrity_passed", hours: approved - deducted, ships: 1)
        approved - deducted
      else
        flow("ysws_approved", "integrity_pending", hours: approved, ships: 1)
        nil
      end
    end

    def add_airtable(row, net)
      unless row.airtable_synced
        flow("integrity_passed", "airtable_unsynced", hours: net, ships: 1)
        return
      end

      flow("integrity_passed", "airtable_synced", hours: net, ships: 1)
      if row.in_unified_db
        @details["unified_db_hours"] += net
        @details["unified_db_ships"] += 1
      end

      over_cap = [ row.certified_over_cap_hours, net ].min
      flow("airtable_synced", "over_payout_cap", hours: over_cap, affected: 1) if over_cap.positive?
      flow("airtable_synced", "payout_basis", hours: net - over_cap)
    end

    # The raw cap figure: time above ten hours on any single devlog inside a
    # shipped window. Certification does not cap, payout does, so this is what
    # the payout curve will never see whatever the reviewers approve.
    def record_payout_cap(row)
      return unless row.raw_over_cap_hours.positive?

      @details["raw_over_cap_hours"] += row.raw_over_cap_hours
      @details["raw_over_cap_devlogs"] += row.over_cap_devlogs
      @details["raw_over_cap_ships"] += 1
    end

    def flow(source, target, hours:, ships: 0, affected: 0)
      @hours[target] += hours
      @ships[target] += ships
      @ships_affected[target] += affected
      link = @links[[ source, target ]]
      link[:hours] += hours
      link[:ships] += ships
    end

    # ---- SQL ---------------------------------------------------------------

    def ship_rows
      ::ActiveRecord::Base.connection.select_all(ship_rows_sql).map do |row|
        ShipRow.new(
          ship_event_id: row["ship_event_id"],
          project_deleted: row["project_deleted_at"].present?,
          certification_status: row["certification_status"],
          review_status: row["review_status"] && SHIP_STATUSES[row["review_status"]],
          recert_from_ysws: row["recert_from_ysws"],
          bounced: row["bounced"],
          ysws_reviewed: row["reviewed_at"].present?,
          ysws_returned: row["returned_at"].present?,
          approved_minutes_all: row["approved_minutes_all"].to_i,
          airtable_synced: row["airtable_synced_at"].present?,
          in_unified_db: row["in_unified_db"].present?,
          integrity_status: row["integrity_status"] && INTEGRITY_STATUSES[row["integrity_status"]],
          deduction_minutes: row["deduction_minutes"],
          hours: row["hours"].to_f,
          devlogs: row["devlogs"].to_i,
          raw_over_cap_hours: row["raw_over_cap_hours"].to_f,
          over_cap_devlogs: row["over_cap_devlogs"].to_i,
          rejected_hours: row["rejected_hours"].to_f,
          auto_rejected_hours: row["auto_rejected_hours"].to_f,
          approved_hours: row["approved_hours"].to_f,
          marked_down_hours: row["marked_down_hours"].to_f,
          unreviewed_hours: row["unreviewed_hours"].to_f,
          certified_over_cap_hours: row["certified_over_cap_hours"].to_f
        )
      end
    end

    # Every software devlog, deleted or not, with the ship event whose window
    # it falls in: the earliest ship posted at or after the devlog, which is
    # exactly Post::ShipEvent#window_devlogs read from the other side.
    def devlog_base_sql
      <<~SQL
        WITH software_projects AS (
          SELECT id, deleted_at FROM projects WHERE hardware_stage IS NULL
        ),
        ship_posts AS (
          SELECT p.postable_id AS ship_event_id, p.project_id, p.created_at AS shipped_at
          FROM posts p
          JOIN software_projects pr ON pr.id = p.project_id
          WHERE p.postable_type = 'Post::ShipEvent'
        ),
        devlogs AS (
          SELECT d.id AS devlog_id,
                 COALESCE(d.duration_seconds, 0) / 3600.0 AS hours,
                 d.deleted_at,
                 pr.deleted_at AS project_deleted_at,
                 COALESCE(u.banned, FALSE) AS author_banned,
                 ship.ship_event_id,
                 ship.shipped_at,
                 EXISTS (SELECT 1 FROM ship_posts sp WHERE sp.project_id = p.project_id) AS project_has_ship
          FROM post_devlogs d
          JOIN posts p ON p.postable_type = 'Post::Devlog' AND p.postable_id = d.id
          JOIN software_projects pr ON pr.id = p.project_id
          LEFT JOIN users u ON u.id = p.user_id
          LEFT JOIN LATERAL (
            SELECT sp.ship_event_id, sp.shipped_at
            FROM ship_posts sp
            WHERE sp.project_id = p.project_id AND sp.shipped_at >= p.created_at
            ORDER BY sp.shipped_at
            LIMIT 1
          ) ship ON TRUE
        )
      SQL
    end

    def devlog_stage_sql
      <<~SQL
        #{devlog_base_sql}
        SELECT
          COUNT(*) AS devlogs,
          COALESCE(SUM(hours), 0) AS gross,
          COALESCE(SUM(hours) FILTER (WHERE project_deleted_at IS NOT NULL AND author_banned), 0) AS banned,
          COALESCE(SUM(hours) FILTER (WHERE project_deleted_at IS NOT NULL AND NOT author_banned), 0) AS project_deleted,
          COALESCE(SUM(hours) FILTER (WHERE project_deleted_at IS NULL AND deleted_at IS NOT NULL
                                        AND (shipped_at IS NULL OR deleted_at <= shipped_at)), 0) AS deleted_before_ship,
          COALESCE(SUM(hours) FILTER (WHERE project_deleted_at IS NULL AND deleted_at IS NOT NULL
                                        AND shipped_at IS NOT NULL AND deleted_at > shipped_at), 0) AS deleted_after_ship,
          COALESCE(SUM(hours) FILTER (WHERE project_deleted_at IS NULL AND deleted_at IS NULL
                                        AND ship_event_id IS NULL AND NOT project_has_ship), 0) AS unshipped_never,
          COALESCE(SUM(hours) FILTER (WHERE project_deleted_at IS NULL AND deleted_at IS NULL
                                        AND ship_event_id IS NULL AND project_has_ship), 0) AS unshipped_after_ship,
          COALESCE(SUM(hours) FILTER (WHERE project_deleted_at IS NULL AND deleted_at IS NULL
                                        AND ship_event_id IS NOT NULL), 0) AS shipped
        FROM devlogs
      SQL
    end

    # One row per software ship event: the latest ship review, the latest
    # YSWS review, the integrity check, and its live devlogs rolled up. A
    # devlog review's approved hours are the devlog's own hours unless the
    # reviewer marked it down, so an untouched devlog never shows a rounding
    # sliver as a markdown.
    def ship_rows_sql
      <<~SQL
        #{devlog_base_sql},
        ship_reviews AS (
          SELECT DISTINCT ON (post_ship_event_id) post_ship_event_id, status, returned_by_id
          FROM certification_ship_reviews
          WHERE post_ship_event_id IS NOT NULL
          ORDER BY post_ship_event_id, id DESC
        ),
        bounced AS (
          SELECT DISTINCT post_ship_event_id
          FROM certification_ship_reviews
          WHERE status = #{::Certification::Ship.statuses[:returned]} OR returned_by_id IS NOT NULL
        ),
        ysws AS (
          SELECT DISTINCT ON (post_ship_event_id) id, post_ship_event_id, reviewed_at, returned_at,
                 airtable_synced_at, in_unified_db
          FROM certification_ysws_reviews
          ORDER BY post_ship_event_id, id DESC
        ),
        live_shipped AS (
          SELECT dl.ship_event_id, dl.hours, dr.status AS review_status, dr.justification,
                 CASE
                   WHEN dr.status <> 'approved' THEN NULL
                   WHEN dr.approved_minutes >= dr.original_minutes THEN dl.hours
                   ELSE LEAST(dr.approved_minutes / 60.0, dl.hours)
                 END AS approved_hours
          FROM devlogs dl
          LEFT JOIN ysws y ON y.post_ship_event_id = dl.ship_event_id
          LEFT JOIN certification_devlog_reviews dr ON dr.ysws_review_id = y.id AND dr.post_devlog_id = dl.devlog_id
          WHERE dl.deleted_at IS NULL AND dl.project_deleted_at IS NULL AND dl.ship_event_id IS NOT NULL
        ),
        per_ship AS (
          SELECT ship_event_id,
                 COUNT(*) AS devlogs,
                 SUM(hours) AS hours,
                 SUM(GREATEST(hours - #{PAYOUT_CAP_HOURS}, 0)) AS raw_over_cap_hours,
                 COUNT(*) FILTER (WHERE hours > #{PAYOUT_CAP_HOURS}) AS over_cap_devlogs,
                 COALESCE(SUM(hours) FILTER (WHERE review_status = 'rejected'), 0) AS rejected_hours,
                 COALESCE(SUM(hours) FILTER (WHERE review_status = 'rejected'
                                               AND justification IN (#{AUTO_REJECT_JUSTIFICATIONS.map { |j| ::ActiveRecord::Base.connection.quote(j) }.join(", ")})), 0) AS auto_rejected_hours,
                 COALESCE(SUM(approved_hours), 0) AS approved_hours,
                 COALESCE(SUM(GREATEST(hours - approved_hours, 0)) FILTER (WHERE review_status = 'approved'), 0) AS marked_down_hours,
                 COALESCE(SUM(hours) FILTER (WHERE review_status IS NULL OR review_status = 'pending'), 0) AS unreviewed_hours,
                 COALESCE(SUM(GREATEST(approved_hours - #{PAYOUT_CAP_HOURS}, 0)), 0) AS certified_over_cap_hours
          FROM live_shipped
          GROUP BY ship_event_id
        )
        SELECT sp.ship_event_id,
               pr.deleted_at AS project_deleted_at,
               se.certification_status,
               r.status AS review_status,
               (r.returned_by_id IS NOT NULL) AS recert_from_ysws,
               (b.post_ship_event_id IS NOT NULL) AS bounced,
               y.reviewed_at, y.returned_at, y.airtable_synced_at, y.in_unified_db,
               (SELECT COALESCE(SUM(approved_minutes), 0) FROM certification_devlog_reviews dr WHERE dr.ysws_review_id = y.id) AS approved_minutes_all,
               i.status AS integrity_status,
               i.deduction_minutes,
               COALESCE(ps.devlogs, 0) AS devlogs,
               COALESCE(ps.hours, 0) AS hours,
               COALESCE(ps.raw_over_cap_hours, 0) AS raw_over_cap_hours,
               COALESCE(ps.over_cap_devlogs, 0) AS over_cap_devlogs,
               COALESCE(ps.rejected_hours, 0) AS rejected_hours,
               COALESCE(ps.auto_rejected_hours, 0) AS auto_rejected_hours,
               COALESCE(ps.approved_hours, 0) AS approved_hours,
               COALESCE(ps.marked_down_hours, 0) AS marked_down_hours,
               COALESCE(ps.unreviewed_hours, 0) AS unreviewed_hours,
               COALESCE(ps.certified_over_cap_hours, 0) AS certified_over_cap_hours
        FROM ship_posts sp
        JOIN software_projects pr ON pr.id = sp.project_id
        JOIN post_ship_events se ON se.id = sp.ship_event_id
        LEFT JOIN ship_reviews r ON r.post_ship_event_id = sp.ship_event_id
        LEFT JOIN bounced b ON b.post_ship_event_id = sp.ship_event_id
        LEFT JOIN ysws y ON y.post_ship_event_id = sp.ship_event_id
        LEFT JOIN certification_integrities i ON i.ship_event_id = sp.ship_event_id
        LEFT JOIN per_ship ps ON ps.ship_event_id = sp.ship_event_id
        ORDER BY sp.ship_event_id
      SQL
    end
  end
end
