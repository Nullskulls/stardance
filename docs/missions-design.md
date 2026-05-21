# Missions — design

The v2 design for the Missions feature, which replaces the prior Sidequests system. Reflects every decision captured during design review (see decision log below for the consolidated rationale).

For the reverse-engineered analysis of the original `stash@{2}` handoff, see [`missions-stash-reference.md`](./missions-stash-reference.md).

---

## Product framing

Missions replace "Sidequests" with a more beginner-friendly experience. Every project optionally attaches to an mission — a themed track that gives the builder direction. Two flavors:

- **Guided + fixed payout.** Steps + at least one static prize (boba drop, domain grant, etc.). Static-path ships get reviewed; if approved, the builder redeems a prize.
- **Loose + voted payout.** No steps, but still has a description that frames the mission. Ships go straight to voting and get a vote-based payout.

A project can detach at any time, attach later, or ship beyond what the mission prescribes. Missions can also unlock specific shop items (e.g. "wario-ware clone" mission unlocks a related accessory).

Brief examples: home-panel webdev, wario-ware clone, browser extension starter, Discord/Slack bot starter, advanced "build your own scripting language."

---

## Decision log (consolidated)

| Topic | Decision |
|---|---|
| Submission identity | Ship-bound. `Mission::Submission` keyed `(ship_event_id, mission_id)`, both immutable. `Project.mission_id` does not exist; project↔mission link via `Project::MissionAttachment` (visual only). |
| Multi-attachment per project | Schema supports many; v1 app code rejects a second active attachment server-side; v1 UI shows the active one. Future PR can lift the app-layer restriction without schema change. |
| Step completion granularity | Per-project. Survives detach (keyed to step). |
| `mission_prize_claimed_at` denormalized column | Dropped — derived from `submissions.where.not(shop_order_id: nil)`. |
| `shop_orders.mission_submission_id` reverse FK | Dropped — `submissions.shop_order_id` is canonical. |
| Attach-after-creation | Supported. |
| Soft-delete + windowing | `SoftDeletable` on `Mission` + `Mission::Step` + `Mission::Prize` + `Project::MissionAttachment` + `Mission::Submission` (the latter specifically powers the bypass action — see below). Plus `enabled` + `start_at` + `end_at` on Mission. |
| Mission catalog source | DB-defined, admin/owner-edited. |
| Multiple prizes per mission | Yes; builder picks one at redemption. |
| Canonical "completed" | An `:approved` submission exists for that user. Reached via reviewer approval — applies uniformly to both guided (with-prize) and loose (no-prize) missions. Both satisfy shop_unlocks identically. |
| Guided vs. loose | Single mission type. Two independent dimensions surfaced via `steps.any?` (guide / no guide) and `prizes.any?` (static prize / no static prize). All submissions go through review regardless. Voting payout flows from the ship's normal vote-based payout pipeline; mission review is orthogonal. |
| Ship cert + mission review | **Sequential** — submission created at ship time in `:awaiting_certification`, transitions to `:pending` (reviewable) on cert approval, auto `:rejected` on cert rejection. |
| Mid-flight swap | Allowed. Pending submissions for prior mission continue. Step completions preserved. |
| "Guided" mandatory? | No — zero-step missions valid. Same model. Description still required. |
| First-project funnel | Out of scope for v1. |
| Reviewer self-review | Forbidden. Reviewer must not be a project member of the submission's project. |
| Locked shop items UX | Shown on cards/show pages with explanation. Multi-unlock = OR semantics. |
| Step completions on detach | Preserved. |
| Rejection fee | Dropped. |
| Achievements | Per-mission. Admin sets name + description; slug auto-generated `mission_<slug>_completed`; icon reuses `mission.icon`. Granted eagerly in the same DB transaction as approve. Implemented via direct `User::Achievement` create — no global achievement-registry change required. |
| Per-mission callback classes | Dropped. All side-effects generic + configured on the mission row. |
| Reviewer roles | Per-mission `Mission::Membership` (owner/reviewer) + global `User::Role.mission_reviewer` (id 10). |
| Reviewer notifications | Slack DM only to per-mission reviewers/owners + global mission_reviewer role. **Admins are not in the default DM list** — they self-add via the global role. |
| Email fallback for Slack DM bounce | Dropped for v1. |
| Ship form UX | Single checkbox ("Submit for static prize review"). Defaults to checked when mission has prizes. Hidden when no mission attached OR mission has no prizes (forced `:voting`) OR user has already redeemed a prize for this mission (forced `:voting`). The checkbox only controls **payout_path** (`:static_prize` vs `:voting`); review happens on every submission either way. |
| Payout path on submission | Field captured at ship time, immutable. `:static_prize` (try for prize) or `:voting` (skip the prize, take vote-based payout). Both go through cert + reviewer review. |
| Post-rejection user actions | Reviewer-rejection (cert was approved): user can either ship a new event (existing Stardance pattern for fixing rejections) OR bypass on the rejected submission. Bypass = **soft-delete the submission** — the ship loses its mission link entirely and behaves as if no mission was ever attached. Cert-failure rejection: only "ship a new event" — bypass not offered (failed-cert ships have no voting eligibility). No automatic fallback to voting; user must take action. |
| Active form / popup nudge on ship | Skipped for v1. |
| Helper role | Read-only access to submissions index/show. |
| Featured missions | `featured_at` column + admin toggle present in v1 schema. UI consumption (highlighted on `/missions` index, etc.) deferred to a later PR. |
| `User#completed_mission_ids` | Cached as a Set per request to avoid N+ queries on shop pages. |
| Sidequest code | Removed wholesale as part of step 1 (controllers, views, models, OG handlers, sitemap entries). |
| Reviewer leaderboards | Deferred. Schema (`reviewed_by_id`, `reviewed_at`) supports it for free. |

---

## Architectural keystone — submissions are ship-bound

A submission is a permanent fact about a ship, not about a project. `Mission::Submission` is keyed on `(ship_event_id, mission_id)`, both immutable after creation. The mission is captured at ship time and never reinterpreted.

Why this matters:

- **Immutable history.** A ship made under mission X is forever a ship-for-X, regardless of what the project does later.
- **Trivial swap behavior.** Project changes its mission attachment → no cascade. Pending/awaiting-cert submissions on the prior mission continue their lifecycle.
- **Single source of truth for completion.** `User#completed_mission?(x)` = "owns a project with at least one approved submission for x." No project-state involvement.
- **Multi-mission history is free.** A project that ships once for A and once for B has two submissions across two missions. Falls out of the data model with no extra schema.

Project-side attachment (`Project::MissionAttachment`) is purely visual — it controls which mission panel shows on the project page and which mission is captured at ship time.

---

## Domain model

### `Mission`

The track. DB-defined, edited by admins or per-mission owners.

| Field | Type / notes |
|---|---|
| `slug` | string, unique. URL-safe handle. |
| `name` | string. |
| `description` | text (markdown). Always required — even for loose missions, this is the body that frames what the mission is about. |
| `enabled` | boolean. Admin-toggleable kill switch. |
| `start_at` | datetime, nullable. Open-ended below = always available. |
| `end_at` | datetime, nullable. Open-ended above = no automatic close. |
| `featured_at` | datetime, nullable. Admin-set highlight. v1 stores it; UI consumption deferred. |
| `achievement_name` | string, nullable. If present, the per-mission achievement is granted on first approved submission. |
| `achievement_description` | text, nullable. |
| `icon` | Active Storage attachment. Also used as the per-mission achievement icon. |
| `banner` | Active Storage attachment. |
| `deleted_at` | datetime — `SoftDeletable`. |

- `paper_trail` for audit logging.
- "Available to builders" = `enabled = true` AND now ∈ `[start_at, end_at]` AND `deleted_at IS NULL`.
- Unavailable missions still render their show page (with an "ended" / "coming soon" banner) so historical links don't 404.
- No derived predicate booleans (`has_static_prizes?`, etc.) — call `prizes.any?` in views directly.

Associations: `has_many :steps, :prizes, :memberships, :shop_unlocks, :submissions, :attachments` (and `:projects, through: :attachments`).

Scopes: `available`, `enabled`, `featured`, `with_approved_count` (left-joins submissions and counts approved, for listings).

### `Mission::Step`

A single guided todo. Loose missions have zero steps; same model.

| Field | Type / notes |
|---|---|
| `mission_id` | FK. |
| `position` | integer. Used for ordering. |
| `title` | string. |
| `body` | text (markdown, rendered through the existing markdown helper layer). |
| `deleted_at` | datetime — `SoftDeletable`. |

CTA links / buttons live inline in the markdown body — no separate `cta_label` / `cta_url` columns.

`paper_trail`. Drag-reorder in admin/owner UI.

### `Mission::StepCompletion`

Per-project step progress.

| Field | Type / notes |
|---|---|
| `project_id` | FK. |
| `mission_step_id` | FK. |
| `completed_at` | datetime, nullable. NULL while undone. |

- Unique on `(project_id, mission_step_id)`.
- Survives mission swap — keyed to the step. If a project detaches and reattaches to the same mission later, progress is restored.
- `paper_trail`.

### `Mission::Membership`

Owner / reviewer assignment, mirroring [`Project::Membership`](app/models/project/membership.rb).

| Field | Type / notes |
|---|---|
| `mission_id` | FK. |
| `user_id` | FK. |
| `role` | integer enum: `owner: 0, reviewer: 1`. |

- Unique on `(mission_id, user_id, role)` — a user can hold both roles via two rows.
- Owners can edit the mission, manage steps/prizes/shop_unlocks, manage memberships, and review submissions.
- Reviewers can review submissions for that mission.
- `paper_trail`.

### `Mission::Prize`

Maps an mission to a redeemable shop item.

| Field | Type / notes |
|---|---|
| `mission_id` | FK. |
| `shop_item_id` | FK. The shop item must have `mission_prize_only: true`. |
| `position` | integer. Display order on redemption screen. |
| `deleted_at` | datetime — `SoftDeletable`. |

- An mission can have multiple prizes; the builder picks one at redemption time.
- `paper_trail`.

### `Mission::ShopUnlock`

Gates a shop item behind mission completion. **OR semantics** — completing any one of the unlocking missions opens the item.

| Field | Type / notes |
|---|---|
| `mission_id` | FK. |
| `shop_item_id` | FK. |

- Unique on `(mission_id, shop_item_id)`.
- `paper_trail`.

### `Mission::Submission`

Ship-bound entry into an mission. Replaces the stash's `Mission::Review` — name change because the entity covers all five lifecycle states, not just reviewer-initiated ones.

| Field | Type / notes |
|---|---|
| `ship_event_id` | FK. **Unique** — one submission per ship. |
| `mission_id` | FK. **Immutable** after creation. |
| `status` | string AASM. `awaiting_certification`, `pending`, `approved`, `rejected`. |
| `payout_path` | string. `:static_prize` or `:voting`. Captured at ship time, immutable. |
| `reviewed_by_id` | FK → User, nullable. Set on approve/reject. |
| `reviewed_at` | datetime, nullable. |
| `rejection_message` | text, nullable. Reviewer's reason on rejection (or system reason on auto-reject); surfaced to builder. |
| `chosen_prize_id` | FK → `Mission::Prize`, nullable. Set at redemption time. |
| `shop_order_id` | FK → ShopOrder, nullable. Set when prize is redeemed. |
| `deleted_at` | datetime, nullable — `SoftDeletable`. Set when the user bypasses; default queries exclude soft-deleted rows. |

`paper_trail` on top of `SoftDeletable` covers the full audit timeline (creates, transitions, soft-deletes, restores).

**Lifecycle state machine** — same shape for guided and loose:

```ruby
state :awaiting_certification, initial: true
state :pending                 # cert cleared, ready for review
state :approved
state :rejected                # entered via cert failure OR reviewer rejection;
                               # distinguish by checking ship_event.certification_status

event :certify do                 # system, on ship cert approval
  transitions from: :awaiting_certification, to: :pending
end

event :fail_certification do      # system, on ship cert rejection
  transitions from: :awaiting_certification, to: :rejected
  # rejection_message set to a system reason; bypass NOT offered
end

event :approve do                 # reviewer
  transitions from: :pending, to: :approved
  after { |reviewer| ... }
end

event :reject do                  # reviewer
  transitions from: :pending, to: :rejected
  after { |reviewer, message| ... }
end

event :undo do                    # admin
  transitions from: [:approved, :rejected], to: :pending
  after { ... }                   # clears reviewed_by/reviewed_at/rejection_message
end
```

**Bypass is NOT a state transition** — it's a soft-delete. See "Post-rejection user actions" below.

Scopes: `awaiting_certification`, `pending`, `approved`, `rejected`, `unredeemed` (= `approved.where(shop_order_id: nil)`), `stale_pending(days: 7)`, `reviewable` (= `pending`). All operate on the default scope (non-deleted only). `with_deleted` exposes bypassed submissions for audit.

**Voting pool eligibility.** Today, voting eligibility is enforced by [`VoteableShipEventsQuery`](app/services/voteable_ship_events_query.rb) — a `where` chain on `Post::ShipEvent`. There is no `voting_eligible?` predicate on the model. Mission integration adds an exclusion clause to that query so ships held by a static-prize mission submission (not yet redeemed or bypassed) drop out of the voteable pool.

The conceptual logic, expressed as a predicate for clarity:

```ruby
# Conceptual — actual implementation is the WHERE clause described below.
def voting_eligible?
  return false unless certification_status == "approved"
  submission = mission_submission                             # default scope: excludes soft-deleted
  return true if submission.nil?                              # non-mission OR bypassed (soft-deleted)
  return false if submission.shop_order_id.present?           # prize redeemed — voting consumed
  return true  if submission.payout_path == "voting"          # voting path: always voting after cert
  false                                                        # static_prize: held until redeemed or bypassed
end
```

`VoteableShipEventsQuery` gains something equivalent to:

```ruby
.where.not(id: Mission::Submission
  .where(payout_path: "static_prize", shop_order_id: nil)
  .where(status: %w[awaiting_certification pending approved])
  .select(:ship_event_id))
```

`Mission::Submission`'s default scope already excludes soft-deleted rows, so bypassed ships fall through naturally to "regular voteable ship" — exactly matching the behavior of a ship that was never on a mission at all.

A submission is independent of the parent project's current mission attachment. Mission swaps on the project don't touch its lifecycle.

### `Project::MissionAttachment`

Visual attachment record. Schema supports many active attachments per project, but v1 app code rejects a second active attachment server-side (with a clear error: *"Detach the current mission before attaching another"*). Future PRs can lift this restriction without schema change.

| Field | Type / notes |
|---|---|
| `project_id` | FK. |
| `mission_id` | FK. |
| `attached_at` | datetime. |
| `detached_at` | datetime, nullable. NULL = currently attached. |
| `deleted_at` | datetime — `SoftDeletable`. |

- Unique partial index: `(project_id, mission_id) WHERE detached_at IS NULL` — can't double-attach to the *same* mission simultaneously.
- v1 model validation rejects `create!` if any other `attachments.where(detached_at: nil)` already exists for the project.
- "Current mission" for the panel = `attachments.where(detached_at: nil).order(attached_at: :desc).first&.mission`.
- `paper_trail`.

### `Project` additions

- `has_many :mission_attachments, class_name: "Project::MissionAttachment", dependent: :destroy`
- `has_many :missions, through: :mission_attachments`
- `has_many :mission_step_completions, dependent: :destroy`
- `has_many :completed_mission_steps, through: :mission_step_completions, source: :mission_step`
- `has_many :mission_submissions, through: :ship_events`
- `current_mission` method = the single attachment where `detached_at` is null (today; tomorrow could return many).
- **No** `mission_prize_claimed_at` column. Derived.

### `ShopItem` additions

- `mission_prize_only` (boolean, default false). When true, item is hidden from the regular catalog and only purchasable via the redemption flow.
- `has_many :mission_prizes`
- `has_many :mission_shop_unlocks`
- `mission_locked_for?(user)` — true iff `mission_shop_unlocks.exists?` AND none of those missions are in `user.completed_mission_ids`.

### `ShopOrder` additions

- Validation `:check_mission_unlock_requirement` on create. Fails purchase with: *"You must complete one of: <missions> (have an approved ship) to purchase this item."*
- Redemption flow short-circuits cookie balance check by accepting `params[:mission_submission_id]`. The submission's `chosen_prize` locks `shop_item_id`. **No reverse FK on `shop_orders`** — `Mission::Submission#shop_order_id` is the canonical link.

### `User` additions

- `has_many :mission_memberships, class_name: "Mission::Membership"`
- `owned_missions`, `reviewable_missions` filtered by membership role.
- **`completed_mission_ids`** — single source of truth, **cached as a Set per request** so shop pages don't re-query for every locked card. Completion is reviewer-approval, uniformly for both guided and loose missions:

  ```ruby
  def completed_mission_ids
    @completed_mission_ids ||= Mission::Submission
      .approved
      .joins(ship_event: { post: :project })
      .joins("INNER JOIN project_memberships ON project_memberships.project_id = projects.id")
      .where(project_memberships: { user_id: id })
      .distinct
      .pluck(:mission_id)
      .to_set
  end

  def completed_mission?(mission) = completed_mission_ids.include?(mission.id)
  ```
- `mission_review_notifications` (boolean, default true). Opt-out for the global mission_reviewer role.

### `User::Role` additions

Add `mission_reviewer` (id 10) — global role, can review submissions for any mission (subject to self-review prevention).

The existing `helper` role gains read-only access to mission submissions index + show (matches its existing read-only access to projects/orders).

---

## Lifecycle

### Attaching

A project attaches to an mission either at creation (form selector) or after creation via:

```
POST /projects/:project_id/mission  body: { mission_slug: ... }
```

This creates a `Project::MissionAttachment` row. v1 model validation rejects creation if the project already has an active attachment, returning *"Detach the current mission before attaching another."*

The first-project funnel (suggesting an mission to first-time builders on the new-project page) is out of scope for v1.

### Working an mission

Builder marks steps complete via:

```
POST    /projects/:project_id/mission_step_completions  body: { mission_step_id: ... }
DELETE  /projects/:project_id/mission_step_completions/:mission_step_id
```

The mission panel on the project page renders differently for guided vs loose:

- **Guided (steps > 0):** current step (title + markdown body), "complete step" button, `<details>`-wrapped step list (line-through on completed), "all done" celebration block when every step is complete.
- **Loose (steps == 0):** the mission's description as the panel body; no step UI. Just a "you're on the X mission" header + the description.

Step content is admin-edited markdown rendered through the existing markdown helper layer. No Action Text / WYSIWYG.

### Detaching / swapping

```
DELETE /projects/:project_id/mission  → soft-detach (sets detached_at on the active attachment)
```

- Step completions are preserved (keyed to step). Reattaching restores progress.
- Awaiting-cert / pending submissions on the prior mission continue their lifecycle unchanged — they're locked to the ship event.
- Approved/rejected/voted submissions stay forever (immutable history).

### Shipping

Ship form has a single checkbox: **"Submit this for static prize review."**

The checkbox controls **payout_path**:
- Checked → `payout_path: :static_prize` (if approved, user redeems a prize)
- Unchecked → `payout_path: :voting` (if approved, ship goes to voting; user still gets completion credit + shop unlocks)

Defaults to checked when the mission has prizes; not shown otherwise.

The checkbox is **hidden / forced to `:voting`** when:
- The project has no current mission attachment (no submission created).
- The current mission has no prizes (loose).
- The user has already redeemed a prize for this mission.

A submission is **always** created when the project has an mission attached, regardless of the checkbox — review applies to both paths.

`Projects::ShipsController#create`:

```ruby
attachment = @project.current_mission_attachment
if attachment
  Mission::Submission.create!(
    ship_event: ship_event,
    mission: attachment.mission,
    payout_path: payout_path_from_form,
    status: :awaiting_certification,
  )
end
```

`mission_id` is captured at this moment from the project's current attachment and immutable thereafter.

### Certification interaction

Ship cert and mission review are **sequential**. Submissions in `:awaiting_certification` are not visible in the reviewer queue and surface a "waiting for ship certification" status to the builder.

**Initial vs subsequent ships.** Stardance auto-approves cert for *subsequent* ships in [`Projects::ShipsController#create`](app/controllers/projects/ships_controller.rb) (`@post.postable.update!(certification_status: "approved")` immediately on create), while *initial* ships start with `certification_status: "pending"` and wait for fraud-team review. Both flows route through the same callback below — for subsequent ships, the submission transitions through `:awaiting_certification → :pending` synchronously inside the same controller action; for initial ships, it sits in `:awaiting_certification` until fraud review resolves.

**Driving the state transitions.** `Post::ShipEvent` has no existing callback infrastructure for cert status changes; today, mutations happen via direct `update!` calls. We add an `after_update` callback on `Post::ShipEvent`:

```ruby
after_update :sync_mission_submission_status, if: :saved_change_to_certification_status?

private

def sync_mission_submission_status
  submission = mission_submission  # nil-safe; non-mission ships do nothing
  return unless submission&.may_certify? || submission&.may_fail_certification?

  case certification_status
  when "approved" then submission.certify!
  when "rejected" then submission.fail_certification!
  end
end
```

Outcomes:

- `pending → approved`: `submission.certify!` fires. Status → `:pending` (now reviewable).
- `pending → rejected`: `submission.fail_certification!` fires. Status → `:rejected` with `rejection_message: "Ship was not certified — see ship feedback for details."` Bypass is NOT offered (the ship can't enter voting from cert-failure).

If a ship is decertified after mission approval (rare admin override), the mission submission stays approved — "if both audits passed at the time, the prize is honored." Known edge case for admins; the callback's `may_certify?` / `may_fail_certification?` guards prevent invalid transitions.

### Post-rejection user actions

After a **reviewer-rejection** (the submission is `:rejected` AND `ship_event.certification_status == :approved`), the rejected ship is held — it does **not** auto-fall-through to voting. The builder sees the rejection via:

1. A Slack DM (existing notification template).
2. A **banner on the project page** rendered when the project owner is viewing and any of the project's ship_events has a `:rejected` (cert-approved) submission. The banner reads:

   > **Mission submission rejected.** Reviewer's note: "<rejection_message>".
   > [Ship a new version with edits] · [Bypass and send this ship to voting]

   The banner is the discovery surface for the bypass action — without it the owner has no way to find the bypass button.

The owner has two options from the banner:

- **Ship a new event** — existing Stardance pattern for fixing ship-cert rejections, applies the same way here. Creates a new ship_event with revised content, which spawns a new `Mission::Submission`. The old submission stays `:rejected` as historical record. The old ship remains held (not in voting) unless the user also bypasses it; typically users abandon the old ship in this case.
- **Bypass** — soft-delete the rejected submission (`submission.soft_destroy!`). The ship loses its mission link entirely and behaves from this point on as if no mission was ever attached: it enters the regular voting pool, appears as a regular ship in feeds, and has no mission framing anywhere user-facing.

After a **cert-failure rejection** (`certification_status == :rejected`), the banner shows the same shape but **only** the "Ship a new version" CTA — bypass is not offered because a cert-failed ship has nothing to gain from the voting pool. The cert feedback flow itself (whatever Stardance does today) is referenced from this banner.

### Bypassed ships — what severance looks like

Bypass = soft-delete the submission. This is a deliberately destructive action from the data layer's perspective: the `(ship_event_id, mission_id)` link is "gone" as far as default-scoped queries are concerned. Concretely:

- **Project page feed**: ship renders as a regular cert-approved ship, no mission badge — `mission_submission` returns nil under the default scope.
- **Voting / homepage feeds**: ship appears as a regular voted ship; no mission framing.
- **Owner's project page**: the rejection banner clears immediately on bypass.
- **My Missions on user profile**: bypassed submissions are not listed — neither in "in progress" nor "completed."
- **Reviewer queue**: by default excludes bypassed submissions. A `?with_bypassed=1` admin filter makes them visible (uses `with_deleted` scope) for analytics + admin restore.
- **Submission show page**: not reachable from any user-facing surface; admins can navigate via the queue's bypass filter.
- **Admin restore**: `submission.restore!` (un-soft-delete) re-attaches the submission. Used rarely — handles "user bypassed by accident" cases. PaperTrail records the soft-delete and any restore.

Soft-delete keeps the audit trail intact (PaperTrail + `with_deleted` queries) while delivering the user-facing semantics of "the mission has been removed from this ship."

### Reviewing

Reviewers see `/mission_submissions` (filterable by status, mission, stale-pending). On a submission show page, approve/reject/undo actions.

**Who can review** (`Mission::SubmissionPolicy#review?`):

- Admins (any admin role)
- Users with global `mission_reviewer` role
- Users with per-mission membership (`role: :reviewer` or `:owner`) for *this* submission's mission

**Self-review prevention**: review? returns false if the reviewer is a project member (any role) of the submission's project.

On **approve** (`submission.approve!(current_user)`):

- Sets `reviewed_by`, `reviewed_at`, transitions to `approved`.
- **Eager achievement grant** in the same DB transaction — if `mission.achievement_name.present?` and the submitter doesn't already have the slug `mission_<mission.slug>_completed`, create the `User::Achievement` row directly. Icon resolves from the mission's `icon` attachment.
- Sends Slack DM to builder via `SendSlackDmJob` with template `notifications/missions/submission_approved.slack_message.slocks`. **No email fallback.**

On **reject** (`submission.reject!(current_user, rejection_message:)`):

- Sets reviewer attribution, transitions to `rejected`, stores `rejection_message`.
- Sends Slack DM with the rejection message. **No email fallback.**
- **No rejection fee** (dropped from the sidequest model).

On **undo**: reverts to pending, clears `reviewed_by` / `reviewed_at` / `rejection_message`. No notifications. Visible in the audit timeline.

When a submission transitions to `:pending` (i.e. cert cleared), reviewers are notified:

- Slack DM to per-mission reviewers/owners + users with the global `mission_reviewer` role (and `mission_review_notifications: true`).
- **Admins are NOT in the default DM list** — they self-add via the global `mission_reviewer` role if they want pings. Admin dashboard tile + `/mission_submissions?status=pending` are the discovery surface for admins.

### Redeeming a prize

Shop index loads `Mission::Submission.unredeemed` for `current_user`, renders banners ("🎁 Claim a prize from <mission>") above the regular shop. Banner links to a redemption page listing the mission's prizes.

Builder picks a prize → goes through a redemption order form at `/mission_submissions/:id/redeem`:

- Form has a hidden `mission_submission_id` field.
- `ShopOrder` creation locks `shop_item_id` to the chosen prize (validated against `submission.mission.prizes`).
- Cookie balance check is bypassed when `mission_submission_id` is present (the prize shop item is `mission_prize_only` — not for-sale).
- On success: `submission.update!(chosen_prize_id:, shop_order_id:)`. Funnel event `mission_prize_redeemed` fires.

---

## Routes

```ruby
# Public
resources :missions, only: [:index, :show], param: :slug

# Project-side actions (current user's project)
resource :mission,
         only: [:create, :update, :destroy],
         module: :projects,
         controller: "missions"

resources :mission_step_completions,
          only: [:create, :destroy],
          module: :projects,
          param: :mission_step_id

# Reviewer queue (admin / global mission_reviewer / per-mission reviewer-or-owner / helper read-only)
resources :mission_submissions, only: [:index, :show] do
  member do
    post :approve
    post :reject
    post :undo
    get  :redeem  # picks prize + opens redemption flow
  end
end

# Owner-managed (per-mission members with role :owner)
namespace :manage do
  resources :missions, param: :slug, only: [:show, :edit, :update] do
    resources :steps,         only: [:create, :update, :destroy]
    resources :prizes,        only: [:create, :update, :destroy]
    resources :memberships,   only: [:create, :update, :destroy]
    resources :shop_unlocks,  only: [:create, :destroy]
  end
end

# Admin (full CRUD, soft-delete management, audit log access)
namespace :admin do
  resources :missions, param: :slug do
    resources :steps,         only: [:create, :update, :destroy]
    resources :prizes,        only: [:create, :update, :destroy]
    resources :memberships,   only: [:create, :update, :destroy]
    resources :shop_unlocks,  only: [:create, :destroy]
    member do
      post :restore  # un-soft-delete
    end
  end
end
```

Owner and admin controllers share concerns where logic overlaps — they diverge only in policy guards and layout.

---

## Permissions (Pundit)

- `MissionPolicy`
  - `index?`, `show?` — public for available missions
  - `manage?` — admin OR member with `role: :owner`
  - `destroy?` — admin only (soft-delete)
- `Mission::SubmissionPolicy`
  - `index?`, `show?` — admin / global mission_reviewer / per-mission reviewer-or-owner / submitter (project member) / `helper` (read-only)
  - `review?` — admin OR global mission_reviewer OR per-mission reviewer-or-owner; **AND** the reviewer is not a project member of the submission's project
  - `approve?`, `reject?`, `undo?` → all delegate to `review?`
- `Mission::StepPolicy`, `Mission::PrizePolicy`, `Mission::MembershipPolicy`, `Mission::ShopUnlockPolicy` — all gate on `Mission.manage?` (admin or owner of parent mission)
- `Project::MissionPolicy` (project-side attach/detach) — gate on project membership

---

## Side effects

All side effects are **generic** — no per-mission callback classes. Behavior is configured on the mission row (achievement copy, prize relationships) or universal (Slack DMs, audit logs).

| Trigger | Side effect |
|---|---|
| Submission transitions to `:pending` (cert cleared) | Slack DM to per-mission reviewers + owners + users with global `mission_reviewer` role and `mission_review_notifications: true`. Admins NOT included by default. |
| Submission `approve` event | Slack DM to builder (`submission_approved` template). Eager achievement grant if configured. PaperTrail entry. |
| Submission `reject` event | Slack DM to builder (`submission_rejected` template, includes `rejection_message` AND CTA prompts to either ship-again-with-edits or bypass to voting). PaperTrail entry. |
| Submission `fail_certification` event | Slack DM to builder mirroring the cert-rejection DM (with system message). PaperTrail entry. |
| Submission soft-deleted (bypass) | PaperTrail entry. No notifications (user-initiated). Ship's `mission_submission` becomes nil under the default scope, so voting eligibility falls through to the regular non-mission path. |
| Submission `undo` event | PaperTrail entry only. No notifications. |
| Mission softly deleted | No cascade. Submissions and step completions remain, queryable via `with_deleted`. Project attachments are auto-detached so the panel UI clears. |
| Prize redeemed | PaperTrail entry on submission. |

---

## Shop integration

**Prizes** are `ShopItem`s with `mission_prize_only: true`:

- Hidden from the public shop catalog.
- Not purchasable via cookies — only redeemable through the mission flow.
- Admin links existing prize-only shop items to missions via `Mission::Prize` join records.

**Locks** use OR semantics:

- A shop item can have multiple `Mission::ShopUnlock` rows.
- Completing **any** of the linked missions unlocks the item.
- The shop item card / show page renders a "🔒 Complete the X mission (or Y, or Z) to unlock" badge when locked, linking to the mission show pages.
- Validation on order creation is the safety net, not the discovery surface.

The admin shop-item form gains a multi-select for picking unlocking missions (mirrors how the sidequest form worked).

Both guided and loose missions can gate shop unlocks. The canonical "completed" check is the unified definition above (approved submission OR voted submission with cert-approved ship), so loose missions are first-class for unlocks — the user just has to ship + pass cert under the mission's banner, no reviewer in the loop.

---

## Admin / owner UI

### Owner panel (`/manage/missions/:slug`)

- Edit mission meta: name, description, icon, banner, start/end, achievement name + description.
- Manage steps (drag-reorder, markdown body editor).
- Manage prizes (link existing `mission_prize_only` shop items, set position).
- Manage memberships (add/remove owners + reviewers).
- Manage shop unlocks (link existing shop items as mission-gated).
- View this mission's submission queue (filterable by status; stale-pending highlighted).
- Cannot soft-delete the mission.
- Cannot toggle `featured_at` — admin-only.

### Admin panel (`/admin/missions/:slug`)

Everything in the owner panel, plus:

- Soft-delete + restore.
- Full audit log view (PaperTrail history of mission + nested resources).
- Featured flag toggle (column exists in v1 schema; UI consumption deferred).

### Super-mega dashboard tile

Mirrors the sidequest tile pattern:

- Pending count, approved count, rejected count, voted count, awaiting_certification count.
- Submissions today / 7d.
- Approval rate.
- Oldest pending age.
- Per-mission submission breakdown (pie chart).
- Stale-pending list (pending > 7 days).

### Submission show — timeline tab

Renders PaperTrail history: created → cert-cleared → reviewed → undone, etc. Falls out of `has_paper_trail` automatically. The same schema (`reviewed_by_id`, `reviewed_at`) feeds future reviewer leaderboards / "submissions reviewed by this user" views.

---

## My Missions (user profile)

Surfaces on the user's profile page (only visible to the profile owner):

- **Needs your attention**: any submission in `:rejected` (with cert-approved ship) that hasn't been bypassed or superseded by a newer ship. Click-through to the project page where the rejection banner lives.
- **In progress**: project attached AND no approved submission yet for that mission AND no `:rejected` submission needing action.
- **Completed**: at least one `:approved` submission for that mission.

Bypassed submissions are intentionally absent — bypass is the user opting out of the mission for that ship, so the user's My Missions surface treats the link as severed.

Links to the mission show page.

---

## Sitemap, OG images, niceties

- Per-mission OG image generator at `app/services/og_image/missions.rb`.
- Sitemap includes a route per public mission.
- Sidebar nav: add an "Missions" item linking to `/missions`.
- All sidequest-era code (controllers, views, models, OG handlers, sitemap entries) is **removed wholesale** as part of step 1 — not preserved alongside.

---

## Soft delete + windowing semantics (recap)

| Field | Effect |
|---|---|
| `enabled = false` | Hidden from public lists. Existing submissions lifecycle untouched. |
| now < `start_at` | Hidden from public lists. Show page renders "coming soon" banner. |
| now > `end_at` | Hidden from public lists. Show page renders "ended" banner. Existing submissions lifecycle untouched. |
| `deleted_at` set | Hidden everywhere except admin views with `with_deleted`. Project attachments auto-detached. Restorable by admin. |

---

## Funnel events

Event prop names mirror the AASM enum exactly so renames cascade for free.

- `mission_attached_at_creation` — project created with attachment
- `mission_attached_post_creation` — attached after creation
- `mission_detached`
- `mission_swapped` — replaced one attachment with another
- `mission_submission_created` — props: `payout_path: <static_prize|voting>` (captured at ship time; status is always `:awaiting_certification` at create)
- `mission_submission_certified` — `:awaiting_certification` → `:pending`
- `mission_submission_failed_certification` — `:awaiting_certification` → `:rejected` (system)
- `mission_submission_approved`
- `mission_submission_rejected`
- `mission_submission_bypassed` — user soft-deletes a `:rejected` submission
- `mission_submission_undone`
- `mission_prize_redeemed`

---

## Implementation order

Each step is independently shippable behind a feature flag (`Flipper.enabled?(:missions)`). Commit titles `feat(missions): <step>`.

**Step 1 is the groundwork PR by design** — it's larger than later steps because it's the foundation everything else builds on. Reviewer expectations should be set accordingly. If reviewer load is a concern, this step is the natural place to split into 1a/1b along the schema/associations seam.

1. **Schema + base models + sidequest removal.** Migrations for `missions`, `mission_steps`, `mission_step_completions`, `mission_memberships`, `mission_prizes`, `mission_shop_unlocks`, `mission_submissions`, `project_mission_attachments`. Column additions: `shop_items.mission_prize_only`, `users.mission_review_notifications`. New `User::Role.mission_reviewer` (id 10). `User#completed_mission_ids` cache. `SoftDeletable` included on relevant models (`Mission`, `Mission::Step`, `Mission::Prize`, `Mission::Submission`, `Project::MissionAttachment`). **Achievement validation tweak**: `User::Achievement.validates :achievement_slug` relaxed to accept `Achievement.all_slugs` OR a slug matching `/\Amission_[a-z0-9_-]+_completed\z/`. Achievement-rendering helpers gain a parallel lookup that resolves dynamic mission slugs to `(name, description, icon)` from the `Mission` row. Indexes on `mission_submissions(mission_id, status)`, `(reviewed_by_id)`, `(status, created_at)`, partial `(shop_order_id) WHERE shop_order_id IS NOT NULL`, and `(deleted_at)`. **Markdown rendering**: verify the helper path used by guides (or add a minimal CommonMarker-based helper if none exists) — used for mission `description` and step `body`. Stub view/controller scaffolding. **Sidequest code removed in this same PR** (controllers, views, models, OG handlers, sitemap entries).
2. **Public missions surface.** `/missions` index + show using the dark-space styling. Sitemap entries + OG image generator.
3. **Project attachment + step completions.** Project-side controllers, mission panel partial on project show (with guided/loose branches), attach/detach actions. v1 single-active-attachment server-side restriction.
4. **Submission creation at ship time.** Ship form checkbox, `Projects::ShipsController#create` integration, AASM submission record initialized in `:awaiting_certification`. Add `after_update :sync_mission_submission_status` callback on `Post::ShipEvent` that fires `submission.certify!` / `submission.fail_certification!` when `saved_change_to_certification_status?`. Update [`VoteableShipEventsQuery`](app/services/voteable_ship_events_query.rb) with the static-prize-hold exclusion clause (see "Voting pool eligibility" in the domain model section). Verify subsequent-ship flow (cert auto-approves in same transaction) drives the submission through `:awaiting_certification → :pending` synchronously.
5. **Reviewer queue + AASM transitions.** `/mission_submissions` index/show, approve/reject/undo, self-review policy, Slack DMs to builder + reviewers (no email fallback), eager achievement grant on approve.
6. **Shop integration.** `mission_prize_only` hiding, locked-state UI on shop item cards/show, `ShopOrder` validation + redemption flow with `mission_submission_id`. Admin shop-item form gains the unlock multi-select.
7. **Owner-managed CRUD.** `/manage/missions/:slug/...` for edit, steps, prizes, memberships, shop_unlocks. Owner Pundit policies. **Step reordering uses up/down arrow buttons in v1** (drag-reorder Stimulus controller deferred to a follow-up — Stardance has no existing sortable controller, so adding one is a separate concern from the mission UI itself).
8. **Admin CRUD + dashboard.** `/admin/missions/...` with soft-delete + restore, audit log view, super-mega-dashboard tile, stale-pending filter.
9. **Profile + reference niceties.** My Missions on user profile, audit timeline tab on submission show, sidebar nav link. (Featured flag UI is its own deferred PR.)
