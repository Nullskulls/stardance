# Expeditions — stash reference

Reverse-engineered analysis of `stash@{2}: On main: spaceport rebrand + expedition system (handoff)`. The stash was a WIP handoff that **referenced** an `Expedition` domain throughout the app but didn't contain the model files or migrations themselves — the *integration surface* of the feature with the domain implied by usage.

This file is preserved as historical context only. The canonical design lives in [`expeditions-design.md`](./expeditions-design.md). Anything in this file that conflicts with the v2 design is superseded.

---

## Domain model (inferred from usage)

The stash never declared these classes, but every reference in the integration code implied the following shape.

### `Expedition` (top-level)

| Field / scope / method | Inferred from |
|---|---|
| `slug` (string, unique) | `Expedition.enabled.find_by(slug: params[:expedition])`, and `param: :slug` on routes. |
| `name` (string) | `expedition.name` rendered in views and Slack-style sentences. |
| `enabled` (boolean) — `Expedition.enabled` scope | `Expedition.enabled.find_by(...)` and `.enabled.order(:id)`. |
| `description` (text) | Implied by an `expeditions#show` route and "expedition picker" UI. |
| `has_static_prizes?` | `expedition.has_static_prizes?` gate in ships controller; conceptually true when at least one `Expedition::Prize` is configured. |
| `has_many :expedition_steps` | Implied by step nested resource and `completed_expedition_steps` association on Project. |
| `has_many :expedition_prizes` (`source: :shop_item`) | `expedition_prizes` on ShopItem. |
| `has_many :expedition_reviewers` (`source: :user`) | `Expedition::Reviewer` join model. |
| `has_many :expedition_shop_unlocks` | Gate on shop items. |

### `Expedition::Step`

A single guided step inside an expedition.

| Field | Inferred from |
|---|---|
| `expedition_id` | nested `resources :expeditions do; resources :steps; end` admin route. |
| `position` (integer) | Step list shows ordered "current step → upcoming steps". |
| `title` (string) | `.project-expedition-panel__step-title`. |
| `body` (text/markdown) | `.project-expedition-panel__current-step-body`. |
| `cta_label`, `link`? | Implied by "complete-step button" + jump-to-step affordances. (v2 dropped — markdown body covers it.) |

### `Expedition::StepCompletion`

Joins a project to the steps it has marked done.

| Field | Inferred from |
|---|---|
| `project_id` | `has_many :expedition_step_completions` on `Project`. |
| `expedition_step_id` | Same. |
| `completed_at` (datetime) | Implied by toggle-create/destroy semantics. |

Routes: `resources :expedition_step_completions, only: [:create, :destroy], module: :projects, param: :expedition_step_id` nested under projects. So toggling step completion is `POST /projects/:project_id/expedition_step_completions` with the step_id as the resource param.

### `Expedition::Prize`

Maps an expedition to a shop item that can be redeemed as a static prize.

| Field | Inferred from |
|---|---|
| `expedition_id`, `shop_item_id` | `has_many :expedition_prizes` on `ShopItem`. |
| (probably `priority` / `is_default`) | "the review's prize" suggests a single chosen prize per review. |

### `Expedition::Review`

(Renamed `Expedition::Submission` in v2.) Created **after** a ship_event is posted on a project that's attached to an expedition with static prizes (and the prize hasn't been claimed yet).

| Field | Inferred from |
|---|---|
| `ship_event_id` | `has_one :expedition_review` on `Post::ShipEvent`. |
| `expedition_id` | `expedition_review.expedition_id`. |
| `status` (enum: `pending`, `approved`, `rejected`) | `Expedition::Review.create!(..., status: "pending")`; routes have `member { post :approve; post :reject }`. |
| `reviewer_id` (nullable) | Implied by reviewer role. |
| `reviewed_at` (datetime) | Used in `.order(reviewed_at: :desc)` for unredeemed prizes query. |
| `shop_order_id` (nullable) | Set when redeemed: `@expedition_review.update!(shop_order: @order)`. |
| `chosen_prize_id` (FK to `Expedition::Prize`?) | `.includes(chosen_prize: :shop_item)`. |
| Method: `prize_shop_item` | Returns the shop_item to lock the order to. |
| Method: `redeemable_by?(user)` | Authorizes redemption. |
| Scope: `unredeemed` | `Expedition::Review.unredeemed.joins(...)` to power the shop banner. |

### `Expedition::Reviewer`

(Folded into `Expedition::Membership` in v2.) Assigns a user to review submissions for a specific expedition.

| Field | Inferred from |
|---|---|
| `user_id`, `expedition_id` | `has_many :expedition_reviewer_assignments` on User → `reviewable_expeditions`. |

### `Expedition::ShopUnlock`

Gates a shop item behind completing an expedition.

| Field | Inferred from |
|---|---|
| `expedition_id`, `shop_item_id` | `has_many :expedition_shop_unlocks` on ShopItem. |

### `Project` additions

- `expedition_id` (FK, nullable) — `belongs_to :expedition, optional: true`. **Replaced by `Project::ExpeditionAttachment` join in v2.**
- `expedition_prize_claimed_at` (datetime, nullable) — set when the prize redemption order is placed; gates `eligible_for_expedition_review?`. **Dropped in v2** — derived from submission state.
- `has_many :expedition_step_completions`.
- `has_many :completed_expedition_steps, through: :expedition_step_completions, source: :expedition_step`.

### `ShopItem` additions

- `requires_expedition_unlock?` → `expedition_shop_unlocks.exists?` **(dropped in v2 — call `expedition_shop_unlocks.exists?` directly)**
- `meet_expedition_unlock_require?(user)` → user has an approved ship on a project whose `expedition_id` is in any of this item's `expedition_shop_unlocks.expedition_id`.
- `expedition_locked_for?(user)` → requires unlock AND not met.

### `ShopOrder` additions

- New validation `:check_expedition_unlock_requirement` on create. Adds an error like *"You must complete the 'X' expedition (have an approved ship) to purchase this item."*

---

## Routes added in the stash

**Admin (nested under `admin/`)**:

```ruby
resources :expeditions, param: :slug do
  resources :steps,         controller: "expeditions/steps",         only: [:create, :update, :destroy]
  resources :prizes,        controller: "expeditions/prizes",        only: [:create, :update, :destroy]
  resources :reviewers,     controller: "expeditions/reviewers",     only: [:create, :destroy]
  resources :shop_unlocks,  controller: "expeditions/shop_unlocks",  only: [:create, :destroy]
end
```

**Project member routes**:

```ruby
resource :expedition, only: [:destroy], module: :projects, controller: "expedition"
resources :expedition_step_completions,
          only: [:create, :destroy],
          module: :projects,
          param: :expedition_step_id,
          shallow: false
```

**Top-level**:

```ruby
resources :expeditions, only: [:index, :show], param: :slug
resources :expedition_reviews, only: [:index, :show] do
  member do
    post :approve
    post :reject
  end
end
```

(v2 splits these into `public`, `project-side`, `manage/`, `admin/`, and `expedition_submissions` for clarity.)

---

## User flows in the stash

### 1. Pick an expedition when creating a project

`ProjectsController#new`:

```ruby
@project = Project.new
if params[:expedition].present?
  preselected = Expedition.enabled.find_by(slug: params[:expedition])
  @project.expedition = preselected if preselected
end
@available_expeditions = Expedition.enabled.order(:id)
```

`projects/new.html.erb` renders `_expedition_picker`. The form permits `:expedition_id` on save.

### 2. Work the expedition on the project page

`projects/show.html.erb` renders `_expedition_panel` when `@project.expedition.present?`. The panel shows current step, complete-step button, full step list (collapsing), all-done block. Detach via `DELETE /projects/:id/expedition`.

### 3. Ship — choose a path

In `_ship_step_update.html.erb`, **only** if the project has an expedition with static prizes AND the prize hasn't been claimed yet, two radio options appear:

- `static_prize` (default): your ship is reviewed; if approved you get the static prize.
- `voting`: your ship goes to the voting pool.

(v2 collapses this to a single checkbox, and persists a `voted`-status submission for analytics either way.)

### 4. Review queue

A reviewer (any user with an `Expedition::Reviewer` assignment) sees pending reviews, approves or rejects. On approve, status flips, `reviewed_at` is stamped.

### 5. Redeem the prize

The shop index loads `Expedition::Review.unredeemed.joins(...)` and renders a `_unredeemed_prizes` partial. Each banner links to a redemption order. The order locks `@shop_item` to the review's `prize_shop_item`. Pricing waiver was unimplemented in the stash. (v2 replaces with `expedition_prize_only` shop items.)

### 6. Shop unlocks

`ShopItem#requires_expedition_unlock?` is true when at least one `Expedition::ShopUnlock` row points at it. `ShopOrder` validation blocks purchase unless the user has an approved ship on a matching expedition. (v2 keeps the validation, adds locked-state UI before order attempt, OR semantics across multiple unlocks.)

---

## Gaps the stash didn't fill

The original "What the stash *doesn't* contain" gap list, preserved here so we can confirm v2 covers each one:

1. **Domain model files** — covered by v2 schema.
2. **Migrations** — listed in v2 implementation step 1.
3. **Controllers** — covered by v2 routes (public, project, manage, admin).
4. **Views** — covered by v2 (panel, picker, redemption banner, manage UI, admin UI).
5. **Policies** — covered by v2 Pundit specs.
6. **Price waiver** — replaced by `expedition_prize_only` flag.
7. **Project ↔ expedition swap rules** — covered by v2 (pending submissions continue, step completions preserved).
8. **"Beyond the expedition" shipping** — supported via `voted` submissions and "all done" UI.
9. **Reviewer notification** — added in v2.
10. **Tutorial / onboarding integration** — explicitly out of scope for v1; flagged for someone else.
