# House of Horrors: Implementation Plan

- **Status:** Audited and ready for user review; implementation is not authorized by this document.
- **Sources:** [Planning assignment](HOUSE_OF_HORRORS_IMPLEMENTATION_PLAN_base.md) and the supplied JPEGs in [`sources/`](sources/).
- **Baseline:** Existing repository root at `9f17557`, no Rails application. Preserve `AGENTS.md`, the assignment, and unrelated work. This plan describes the demo, not production deployment.

## A. Architecture Overview

- Use one Rails application and one database per running instance. `/` is Homepage. `/admin` is the Administration entry point, including its own login form. Admin resource URLs render the same dashboard, not distinct top-level pages. `Homepage | Admin` appears in the shared layout.
- Rails controllers authenticate, authorize, allowlist inputs, dispatch operations, and render HAML or JSON. HAML renders the shell and Administration forms; React controls the public reservation interaction. Active Record handles persistence and record-local validations. Trailblazer operations run booking commands and the availability query. No business rule is enforced only in JavaScript.
- One reservation always means one person in one room in one hourly slot. Public guests are anonymous: there is no account, ownership link, customer data, or public reservation read/edit/delete endpoint. `User` supports `guest` and `admin`; only `admin` can start an admin session. Anonymous reservations cannot subsequently be self-serviced; administrators manage them.
- The Homepage header on `/` displays `sources/house.jpg` as a bundled Propshaft asset, rendered by HAML above the booking component and visible without JavaScript. It is not part of the shared Administration layout or the room image catalog.
- `/` bootstraps React with JSON in `data-config` on `#booking-root`: `rooms`, `today`, `availability_path`, and `reservations_path`, using Rails route and asset helpers. Render the mount with Rails `tag.div(id: "booking-root", data: { config: payload.to_json })` in HAML: the helper escapes the HTML attribute. Never use `raw`, `html_safe`, or an inline script for the payload. React reads `dataset.config` with `JSON.parse`, mounts via `createRoot`, and uses same-origin `fetch`. Do not use raw HTML in JSX or include admin data in the bootstrap.
- Admin forms use ordinary Rails form submissions with CSRF protection (including login/logout and multipart upload); no Turbo or client router. Public JSON POST uses the Rails `csrf_meta_tags` token in `X-CSRF-Token`, same-origin credentials, `Content-Type: application/json`, and `Accept: application/json`. Keep Rails forgery protection enabled; a failed CSRF check must not write a booking.
- Do not add payments, notifications, audit trails, pagination, image transformations, support for arbitrary durations or party sizes, public guest accounts, or deployment. The paths and limits in this document describe the required demo only.

## B. Technology Decisions

| Choice | Purpose and constraints |
| --- | --- |
| Ruby 3.4.13 | Verified release on a maintained series above Rails' Ruby 3.2 minimum. Record `3.4.13` in `.ruby-version`; no dependency on version-manager-specific commands. |
| `rails`, exactly `8.1.4.1` | Use the exact version for generation and in `Gemfile`; verify the running version. Do not substitute a nearby release. |
| `haml-rails` 3.1.0, `haml` 7.5.2, Propshaft 1.3.2 | HAML handler and generators; Propshaft serves the CSS, bundled JPEGs, and compiled browser bundle. Keep one HAML layout, no ERB application views. |
| `trailblazer-operation` 0.11.1 | Use the real `Trailblazer::Operation` DSL and results, without optional Reform or Rails integration gems. Rails autoloads `app/operations`. |
| React and React DOM 19.3.1; esbuild 0.28.2; Node 22.22.2 or later 22.x patch | Plain JSX and one npm build into `app/assets/builds/booking.js`; no separate server, import maps, Hotwire, or JS bundling gem. Check in `package-lock.json`, not the bundle. |
| `mysql2` `~> 0.5`, `sqlite3` `~> 2.1`; MySQL 8.4 LTS in Compose | The same migrations, models, transactions and tests on both adapters. Developer needs a MySQL client build dependency if `mysql2` builds from source, but not a MySQL server for SQLite. |
| `bcrypt` `~> 3.1`; Rails encrypted cookie session | `has_secure_password`, `authenticate_by`, and `reset_session`; no signup, registration, password recovery or third page. |
| Rails Active Storage (Disk) and its Marcel dependency | Immutable, reusable admin uploads. The five supplied JPEGs are served by Propshaft, not stored as blobs. No variants, direct uploads, public Active Storage routes or image service dependency. |
| Rails Minitest, `rubocop-rails-omakase` 1.1.0; Vitest 5.1.1, Vite 8.3.8, jsdom 31.0.1, Testing Library React 16.3.3 / DOM 10.4.1 | Rails tests need no parallel worker framework; JS tests render the React component and mock its HTTP contract. Vite satisfies Vitest's peer dependency and is used only in tests. Use explicit `npm test` / `npm run build` rather than hidden Rails hooks. |

**Compatibility evidence:** RubyGems publishes [Rails 8.1.4.1](https://rubygems.org/gems/rails/versions/8.1.4.1), [haml-rails 3.1.0](https://rubygems.org/gems/haml-rails/versions/3.1.0) and [trailblazer-operation 0.11.1](https://rubygems.org/gems/trailblazer-operation/versions/0.11.1). The HAML integration declares Rails component lower bounds of 5.1 and no conflicting upper bound; the Operation gem does not depend on Railties. [Operation API](https://trailblazer.to/2.1/docs/operation/), [exact Rails SQLite adapter](https://github.com/rails/rails/blob/v8.1.4.1/activerecord/lib/active_record/connection_adapters/sqlite3_adapter.rb), and npm package metadata inform this plan. These are metadata/source checks, not a combined runtime proof. S01a verifies actual HAML rendering, Zeitwerk and a real Operation result on the exact Rails bundle; S04b verifies autoload for real operations. S09 gates the frontend toolchain with an actual bundle and test.

## C. Data Model

Use Rails 8.1 Ruby-format migrations, default bigint Rails IDs on MySQL and native IDs on SQLite. The order is `CreateRooms`, `CreateReservations`, `CreateBookingWriteLocks`, `CreateUsers`, generated `CreateActiveStorageTables`, `AddUploadedImagesToRooms`. Use generated timestamps for migration filenames and keep both schema dumps (§H) in sync.

| Table / Model | Attributes, constraints and associations |
| --- | --- |
| `rooms` / `Room` | `name:string(120)`, `description:text`, `capacity:integer`, initially `image_key:string(32)`, all non-null; Rails timestamps. Strip `name`; require it unique, nonblank and within 120 characters. Require a nonblank description (max 2,000 characters) and integer capacity `1..2147483647`; non-null plus `capacity > 0` DB CHECK. Unique index on `name`. Case-sensitive names in both modes (MySQL `utf8mb4_0900_bin`; SQLite default BINARY). Nullable unique `seed_key:string(32)` is internal only, never accepted via HTTP. `has_many :reservations, dependent: :restrict_with_error`. Validate bundled keys against `RoomImages`; after Stage 12 use exactly one of allowed `image_key` or valid `image_blob_id`. |
| `reservations` / `Reservation` | Non-null `room_id` FK, `start_datetime` and `end_datetime` UTC `datetime(6)`, Rails timestamps. `belongs_to :room`, explicitly validate presence of association. `room_id` FK uses `ON DELETE RESTRICT` and composite index `(room_id, start_datetime)` (omit redundant FK index); separate `start_datetime` index for date filtering. DB CHECK `end_datetime > start_datetime`. Model rejects invalid schedule and started intervals; capacity is a guarded command-level validation. |
| `users` / `User` | `email_address:string(254)`, `password_digest:string`, `role:string(8)` (default `guest`), all non-null, Rails timestamps. Use `normalizes :email_address, with: ->(email) { email.strip.downcase }` so assignment and `authenticate_by` queries use the same equality, require a valid `URI::MailTo::EMAIL_REGEXP` address and max length 254, and add a unique index. Inclusion and DB CHECK for roles `guest`/`admin`; `admin?` is `role == "admin"`. `has_secure_password`, minimum 12 characters for new/changed passwords, retain bcrypt's byte limit. No association to reservations. |
| `booking_write_locks` / `BookingWriteLock` | Internal infrastructure, not a resource. Use `create_table ..., id: :integer`; non-null integer `token`, no timestamps. The guard lazily upserts id `1`; schema dumps therefore do not need data rows. |
| Active Storage tables | Use Rails-generated migration. In Stage 12 make `rooms.image_key` nullable, add indexed nullable `image_blob_id` FK to `active_storage_blobs` with `ON DELETE RESTRICT`, and add a DB CHECK `(image_key IS NULL) <> (image_blob_id IS NULL)`. Use `belongs_to :image_blob, class_name: "ActiveStorage::Blob", optional: true`; the model must verify membership in the upload catalog when using a blob. An upload is reusable by many rooms. |

Room deletion must fail when any reservation exists, including history. A capacity reduction below the maximum number already booked in a slot is rejected, including historical slots. Capacity can be raised without touching reservations. An elapsed reservation stays visible and deletable but cannot be changed; updates to a future reservation must also target a future slot. There is no direct `Reservation.create!` path for user input, and no client-supplied end time, role, seed key, record owner, or Active Storage key.

### Default Room Catalog

Use these names and descriptions verbatim from assignment §2, with no room-number prefixes. This is the exact order for a fresh seed. The key is both `seed_key` and the initial `image_key`; the rightmost column supplies the bundled JPEG for that key (S02).

| Key | Name | Description | Capacity (people) | Image source |
| --- | --- | --- | --- | --- |
| `basement` | The Basement Where Mobile Signal Goes to Die | You walk down the stairs and your phone gives up. First it loses 5G, then 4G, then the will to live. In the dark, something is still buffering. It has been buffering since 2009. | 10 | `sources/room1.jpg` |
| `bathroom` | The Bathroom That Judges You | You look into the mirror. The mirror looks back. It does not scream. It sighs, very slowly, and whispers: So... this is what we are wearing today? | 1 | `sources/room2.jpg` |
| `kitchen` | The Kitchen of Leftovers That Watch You Back | You open the fridge. All the boxes turn to look at you. One of them is from Christmas. It remembers everything. It knows what you did with the potato salad. | 3 | `sources/room3.jpg` |
| `attic` | The Attic Full of Clowns Doing Taxes | You expect screaming. Instead you hear a calculator. Twelve clowns sit at a tiny table, doing taxes. One looks up and says: You did not keep your receipts, did you? | 6 | `sources/room4.jpg` |

## D. Reservation Algorithm and Contracts

**Canonical time.** Set Rails `config.time_zone = "UTC"` and Active Record `default_timezone = :utc`; label all user-facing dates/times `UTC`. There are no DST hops in UTC; do not use browser-local time or environment-selected wall hours. `BookingSlots` owns `HOURS = (1..6).freeze`, `.parse_date(value)` (strict ASCII `YYYY-MM-DD`, `Date.iso8601(value, Date::GREGORIAN)`, valid year `1000..9998`, else `nil`), `.parse_hour(value)` (only integers 1–6 or strings `"1"`–`"6"`, else `nil`), and `.interval(date, hour)` returning `[start_at, end_at]` via `Time.utc` and `+ 3600`. The input year bound also keeps the exclusive next-day filter bound within MySQL's datetime range. A slot is start-inclusive, end-exclusive. Only a start strictly greater than `Time.current` can be booked. Validate exact hour alignment, correct duration and canonical start/end in the model even if assigned directly. Date display and filtering also use UTC; an admin date filter is `[00:00, next 00:00)`.

**Occupancy.** `Reservations::Occupancy.count(room_id:, start_at:, excluding_id: nil)` queries `room_id` and exact `start_datetime`, excluding the subject when present. `counts(room_id:, starts:)` is the same indexed condition, grouped by `start_datetime` in one query; absent keys count as zero. `peak(room_id:)` is the maximum of grouped counts across all slots (zero if none). Exact-start comparison is equivalent to `old_start < new_end AND old_end > new_start` because every valid interval is a member of a disjoint, aligned slot grid. At the exact boundary one slot ends before the next occupies capacity.

**Write guard.** Implement exactly one `BookingWrite.with_lock { ... }` entry in `app/services/booking_write.rb`. Use `ApplicationRecord.connection_pool.with_connection`, reject `transaction_open?` on that connection (raise `ArgumentError`; a caller-owned transaction is a programming error), and run the following under `ApplicationRecord.uncached` and one outer transaction on that connection. Use `connection.transaction(isolation: :read_committed)` if `adapter_name == "Mysql2"`, and `connection.transaction` for `SQLite` (no Rails isolation option for this case).

1. Before any application data read, execute `BookingWriteLock.upsert({ id: 1, token: 0 }, on_duplicate: Arel.sql("token = 1 - booking_write_locks.token"), record_timestamps: false)`. Use the literal SQL expression, never external parameters. InnoDB serializes on the singleton primary key, including first insert; `READ COMMITTED` gives the post-lock occupancy query a fresh snapshot even on a cold connection. On Rails 8.1.4.1 SQLite uses an IMMEDIATE transaction; the upsert is a write before any capacity reads. The native transaction holds the lock across processes, not just Ruby threads. This serializes demo writes globally in return for one simple protocol, not a throughput optimization.
2. Under that lock, load current records by ID, take a fresh clock reading for the eligibility check, validate, count occupancy and persist. Do not pass stale model instances or perform DB reads for the guarded decision outside the lock. Keep every room create/update/delete, reservation create/update/delete, and reservation seeding on this same guard. Separate image ingestion does not change a room or its capacity. Do not use `requires_new` to mask a nested transaction.
3. Return success only after commit. Semantic refusal is a structured failure; run `save!`/`destroy!` only after all checks or map a known model error after rollback. **Outside** the transaction, map `ActiveRecord::Deadlocked`, `ActiveRecord::LockWaitTimeout` and `ActiveRecord::StatementTimeout` to `BookingWrite::Busy`. Rails translates SQLite's `BusyException` to `StatementTimeout`. Also map `SQLite3::LockedException` (direct or the `cause` of an `ActiveRecord::StatementInvalid`); re-raise all other statement errors. Do not silently retry or treat a refusal as successful. See §G for the separate-connection proof on both modes.

**Operations.** Call classes as `Operation.call(room_id: ..., date: ..., start_hour: ...)`. Declare `step :parse_input` and `step :commit_booking` on both Create and Update; use `step :parse_input` then `:delete_booking` or `:load_slots` on Destroy/Availability. Steps are instance methods `def parse_input(ctx, room_id:, date:, start_hour:, **)` (declare the keyword set for that operation). On success a step stores its outputs in `ctx` and explicitly returns `true`; every known refusal stores `ctx[:code]` (symbol) and `ctx[:messages]` (nonempty strings) and explicitly returns `false`, ending the operation with `result.success? == false`. Do not introduce custom signals or failure routes. For example:

```ruby
step :parse_input
step :commit_booking

def parse_input(ctx, room_id:, date:, start_hour:, **)
  # Ask Booking to normalize all three scalars, then:
  if (input = Reservations::Booking.parse(room_id:, date:, start_hour:))
    ctx[:input] = input
    true
  else
    ctx[:code] = :invalid_input
    ctx[:messages] = ["Select a valid room, date and hour."]
    false
  end
end
```

`Reservations::Booking.parse` returns `{room_id:, date:, start_hour:}` with normalized values or `nil`. `Reservations::Booking.commit(action:, input:, id: nil)` performs the complete guarded decision and returns `{ok:, record:, code:, messages:}`; copy the relevant keys into `ctx` and return `outcome[:ok]`. Update additionally parses its `id`; the same ID helper is available as `BookingSlots.parse_id` (integer or ASCII decimal string of at most 19 digits, positive, max `9223372036854775807`; otherwise `nil`). Destroy and Availability reuse this helper directly; known `BookingWrite::Busy` maps to `:busy`. Invalid shape/date/hour is `invalid_input`; a well-formed missing ID is `not_found`. Assign the computed start/end, use model validation (`errors.full_messages`), and store `ctx[:record]` or `ctx[:slots]` on success. No write transaction spans separate Operation steps.

| Call | Guarded or read behavior |
| --- | --- |
| `Reservations::Create.call(room_id:, date:, start_hour:)` | Load current `Room`; validate new reservation; refuse `slot_full` if occupancy is already `>= capacity`; otherwise save under lock. |
| `Reservations::Update.call(id:, room_id:, date:, start_hour:)` | Load original by id under lock, refuse if original has started (`invalid_input`), resolve target room under lock, recompute proposed interval, exclude the original id from target count, then save or leave the original row unchanged. |
| `Reservations::Destroy.call(id:)` | Parse ID, load and `destroy!` under lock. Deletes may target history. Return the deleted record. |
| `Reservations::Availability.call(room_id:, date:)` | Validate ID/date, reject dates before UTC today, load room, build future starts, group occupancy and return only starts with `remaining > 0`, sorted by hour. `nearly_full` iff `remaining == 1 && capacity > 1`; an empty one-person bathroom is not nearly full. This read need not take the write lock: it is advisory and may be stale before submit. |
| `Rooms::Write.call(action:, id: nil, attributes: {})` | Plain Ruby command returning `{ok:, record:, code:, messages:}`. All write modes (`:create`, `:update`, `:destroy`) use the guard. Validate the room, reject a reduction below `Occupancy.peak` as `capacity_below_bookings`, and reject deletion with any bookings as `room_has_reservations`. Map a duplicate name to `invalid_input`, a missing id to `not_found`, and `BookingWrite::Busy` to `busy`. |

**Public HTTP.** Use `Api::AvailabilityController#show` for `GET /api/availability?room_id=3&date=YYYY-MM-DD` and `Api::ReservationsController#create` for `POST /api/reservations`, with body `{ "reservation": { "room_id": 3, "date": "YYYY-MM-DD", "start_hour": 4 } }`. Disable Rails implicit JSON wrapping with `wrap_parameters false`. Require `params[:reservation]` to be `ActionController::Parameters`, then `permit(:room_id, :date, :start_hour)`; pass explicitly named keyword arguments, using `nil` for missing/filtered fields. Missing or non-object wrappers give 422 `invalid_input`; malformed JSON is a framework 400 and need not use the envelope. Do not expose an API action to list reservations. Generate route URLs with Rails helpers `api_availability_path` and `api_reservations_path`; prepend no host URL.

| Response | Contract |
| --- | --- |
| Home data | Each `rooms` element: `{id, name, description, capacity, image_url}` ordered by room id; `today` is server UTC `YYYY-MM-DD`. |
| GET 200 | `{room_id, date, slots: [{start_hour, start_datetime, end_datetime, label, remaining, nearly_full}]}`. Datetimes ISO 8601 with `Z`; `label` like `04:00-05:00 UTC`; an empty match is `slots: []`. Use `Cache-Control: no-store` for availability. |
| POST 201 | `{reservation: {id, room_id, start_datetime, end_datetime}}`. The client does not persist any of this as an authorization mechanism. |
| Error envelope | `{error: {code, messages: [...]}}`: `invalid_input` 422, `not_found` 404, `slot_full` 409, `busy` 503. Example: `This slot has just filled up. Select another time.` for `slot_full`. Handle Rails-generated non-JSON responses (including CSRF failure) and network failures with a generic useful message in React. |

**Admin HTML.** Implement `Admin::RoomsController` and `Admin::ReservationsController` with `index/show/new/create/edit/update/destroy` via `namespace :admin` resource routes. All resource actions share the private dashboard shell and navigation. Success redirects with HTTP 303 and notice (to record detail on create/update; list on delete). Render the same view and submitted fields on invalid input (422), capacity/deletion conflict (409), or busy (503). Missing resources are 404; failed authorization is 403 before record lookup. Use Rails-generated form tokens and strong parameters. No deletion on GET.

| Admin refusal code | HTTP status and display |
| --- | --- |
| `invalid_input` | 422 on the same dashboard mode; preserve submitted values and show messages. |
| `slot_full`, `capacity_below_bookings`, `room_has_reservations` | 409 on the same mode; explain the conflict, never show success. |
| `busy` | 503 on the same mode; explain that the write did not commit and can be retried. |
| `not_found` | 404; no redirect or lookup before authorization. |

## E. Project Structure

| Location | Responsibility |
| --- | --- |
| `app/models/` | Records, `booking_slots.rb`, `room_images.rb` catalog, validations, associations |
| `app/operations/reservations/` | `create.rb`, `update.rb`, `destroy.rb`, `availability.rb`; `booking.rb` and `occupancy.rb` as their small shared Ruby collaborators |
| `app/services/` | `booking_write.rb`, `rooms/write.rb`, `room_image_upload.rb`, `demo_seeds.rb` |
| `app/controllers/`, `api/`, `admin/` controller namespaces | Home, public JSON, public room photo reads, separate admin/session controllers |
| `app/views/layouts/application.html.haml`, `home/`, `admin/` | Shared layout, booking mount, admin login/dashboard panels and forms |
| `app/helpers/room_images_helper.rb` | Bundled asset and uploaded photo URLs used by both surfaces |
| `app/javascript/booking.jsx`, `app/javascript/booking_app.jsx`, `app/javascript/booking_app.test.jsx` | Mount, component, and focused UI tests; generated bundle in `app/assets/builds/` |
| `sources/`, `app/assets/images/house_of_horrors/` | Supplied originals and identical bundled copies served by Propshaft |
| `app/assets/stylesheets/application.css`, `storage/room_images/` | Separate CSS and private Active Storage disk roots for admin uploads |
| `db/migrate/`, `db/schema.rb`, `db/mysql_schema.rb`, `db/seeds.rb` | Portable migrations, adapter-specific dumps, demo loader |
| `test/models/`, `test/operations/`, `test/integration/`, `test/services/`, `test/support/` | Local validation, operation/locking, HTTP and authorization, seed/upload/service verification, committed test data helpers |
| `compose.yaml`, `config/database.yml`, `config/storage.yml`, `README.md` | Local DB service, adapter switch, upload storage and documented setup |

## F. Implementation Stages

Execute in listed order; lettered IDs are separate acceptance gates. All preceding stages must be accepted; the prerequisite field identifies concrete inputs each stage consumes. A stage must test only capabilities present at its boundary. Stop at failure instead of silently changing an architectural choice, widening scope or using a placeholder for a failed integration. Stop for user acceptance before starting the next stage. Per `AGENTS.md`, write each stage report in Czech and state files changed, observed behavior, exact commands and results (redacting secrets), unexecuted checks as `NOT RUN`, limitations and manual acceptance steps. End each stage report with: `Ke schválení fáze <ID> potvrďte „Schvaluji fázi <ID>“.` Replace both `<ID>` placeholders with that stage's ID. This is not approval to deploy, drop an existing DB, commit, or change agent memory.

**Recurring commands.** Work from the repository root. Set `HOH_DB_SUFFIX=stagecheck` (or another verified dedicated, disposable suffix) on all stage setup, migration, test and browser commands, after checking what paths/names it selects (§H). Once both modes exist, run `bin/rails db:migrate` then `HOH_DB=mysql bin/rails db:migrate` after every schema change to regenerate the two dumps. Before running that adapter's tests after initial setup or a schema change, prepare its dedicated disposable test DB with `bin/rails db:test:prepare` or `HOH_DB=mysql bin/rails db:test:prepare`; this reloads the dump and **purges the test DB**, never run it on data that must be preserved. Then `bin/rails test PATH` uses SQLite and `HOH_DB=mysql bin/rails test PATH` uses MySQL. Run suites serially. From S09, run `npm ci` on a fresh clone and `npm run build` before Rails request tests; when JS changes rebuild again. End each stage with `bundle exec rubocop` on the current tree. A browser check means `bin/rails server -b 127.0.0.1` with the stage's setup and suffix, not a deployed instance.

### S01a. Rails and HAML Baseline

**Objective:** Prove that Rails, HAML, Trailblazer and local SQLite work together before adding Docker or models.

**Prerequisites:** Approved plan and explicit go-ahead for S01a; Ruby 3.4.13 and Bundler. The current repository contains no generated Rails application, and its host currently selects Ruby 3.3.7. Before generation, provision and select [Ruby 3.4.13](https://cache.ruby-lang.org/pub/ruby/3.4/) with the local version manager (e.g. `rvm install 3.4.13`, `rvm use 3.4.13` on the current host), then confirm `ruby -v`. Preserve the existing ignore rules for project/memory files; approve the stated application-runtime ignore additions as part of the S01a go-ahead, before changing `.gitignore`.

**Files and instructions:**

1. Generate in the repository root with `gem install rails -v 8.1.4.1 --no-document` then `rails _8.1.4.1_ new . --name=house_of_horrors --no-rc --skip-git --skip-bundle --skip-docker --skip-ci --skip-kamal --skip-solid --skip-thruster --skip-javascript --skip-hotwire --skip-jbuilder --skip-action-mailer --skip-action-mailbox --skip-action-text --skip-action-cable --skip-system-test --skip-brakeman --skip-bundler-audit`. Keep Active Record, Active Job, Active Storage, Propshaft and Minitest. Do not overwrite existing project files. `--skip-git` does not produce ignore entries: after the required approval, append only `/.bundle/`, `/.env`, `/.env.*`, `/config/master.key`, `/config/credentials/*.key`, `/log/*`, `!/log/.keep`, `/tmp/*`, `!/tmp/.keep`, `/storage/*`, `!/storage/.keep`, `/public/assets/`, `/app/assets/builds/*`, `!/app/assets/builds/.keep`, `/vendor/bundle/`; preserve the existing `node_modules/` entry. Do not stage keys or any files in this plan.
2. In `Gemfile`, use the §B pins for Rails, HAML, Propshaft, Trailblazer and RuboCop, plus SQLite; remove `image_processing` if present (no variants) and leave `mysql2` for S01b and `bcrypt` for S06. Run `bundle install`. Keep `.ruby-version`, `Gemfile.lock`, `.rubocop.yml`; leave generated `README.md` for replacement in S14. Remove `parallelize` and `fixtures :all` from `test/test_helper.rb`; tests supply their own records, not model fixtures.
3. In `config/database.yml` implement the SQLite portion of §H for development and test, including suffix. Accept only `sqlite` until S01b. In `config/application.rb` set UTC (§D), `config.active_record.schema_format = :ruby`, `config.active_storage.draw_routes = false`, and `config.active_storage.variant_processor = :disabled`. Do not configure or run a production DB, or install Solid components.
4. Add root route and `HomeController#show` in `config/routes.rb` and `app/controllers/home_controller.rb`; replace `app/views/layouts/application.html.erb` with `application.html.haml` and remove the unused generated `app/views/pwa/` templates. Add `app/views/home/show.html.haml`; render title, viewport, CSRF meta, `stylesheet_link_tag "application"`, a `House of Horrors` heading and only the Homepage link until Admin exists.
5. Add `test/integration/foundation_test.rb`: assert exact Rails version, `GET /` HTML heading rendered using HAML, SQLite adapter, and a two-step `Trailblazer::Operation` probe defined in the test. Check `true` reaches the second step, while `false` skips it and preserves `code`/`messages` with `success? == false`. Check `ruby -v` matches `.ruby-version`; this machine's preinstalled older Ruby is not the planned runtime. Then run `bin/rails db:create`, `bin/rails db:migrate`, `bin/rails db:test:prepare`, `bin/rails zeitwerk:check`, `bin/rails test test/integration/foundation_test.rb`, and `git check-ignore config/master.key tmp/local_secret.txt storage/development_stagecheck.sqlite3`.

**Accept:** Exact Rails version, HAML page, SQLite connection, Operation result, key/file exclusion, lint and autoload checks pass. Manually load `/` from SQLite; MySQL and JS are not needed. **Boundary:** Stop before adding the second adapter.

### S01b. MySQL Adapter and Local Compose

**Objective:** Boot the same baseline on a separate, durable MySQL service without breaking SQLite.

**Prerequisites:** S01a; compatible MySQL native client headers (on Debian/Ubuntu: `default-libmysqlclient-dev`, `build-essential`, `pkg-config`), Docker Engine and Compose v2, local port 3307 available or already used by this project's service.

**Files and instructions:** Add `mysql2` per §B to `Gemfile`; run `bundle install`, update `Gemfile.lock`. Add MySQL to `config/database.yml`, with the exact Compose settings, version, isolated DB names and per-adapter dumps in §H; create `compose.yaml`. Extend `foundation_test.rb` to check the chosen adapter and on MySQL run `SELECT @@collation_database, @@default_storage_engine` to assert `utf8mb4_0900_bin` and `InnoDB`. Include the initial `db/mysql_schema.rb`; leave `db/schema.rb` the SQLite dump.

**Verify:** `docker compose config --quiet` (no credential output), `docker compose up -d --wait mysql`; `HOH_DB=mysql bin/rails db:create`, `HOH_DB=mysql bin/rails db:migrate`, `HOH_DB=mysql bin/rails db:test:prepare`; run `bin/rails test test/integration/foundation_test.rb` in both modes. **Accept:** Docker health succeeds, implicit SQLite and explicit MySQL share the same HAML test and distinct DBs/dumps; manually load `/` in MySQL mode. **Boundary:** Stop before domain migrations.

### S02. Room Model and Bundled Images

**Objective:** Establish validated rooms and bundle the supplied JPEGs, including the Homepage header.

**Prerequisites:** S01b; both databases available; `sources/house.jpg` and `sources/room1.jpg` through `sources/room4.jpg` present.

**Files and instructions:**

1. In `db/migrate/*_create_rooms.rb` and `app/models/room.rb` implement the initial room fields, validations and constraints in §C. Defer the reservation association to S03 and blob association to S12a.
2. Copy `sources/house.jpg` and the four room JPEGs from §C unchanged into `app/assets/images/house_of_horrors/`, preserving their filenames and the originals. Use no generated replacements or symlinks. Add `app/models/room_images.rb`: map `basement` to `house_of_horrors/room1.jpg`, `bathroom` to `house_of_horrors/room2.jpg`, `kitchen` to `house_of_horrors/room3.jpg`, and `attic` to `house_of_horrors/room4.jpg`. `app/helpers/room_images_helper.rb#room_image_url(room)` resolves this allowlist through the Rails asset helper. Do not add `house.jpg` to the allowlist. The app serves the bundled copies, not the `sources/` directory.
3. In `app/views/home/show.html.haml` place the heading and `image_tag "house_of_horrors/house.jpg", alt: "Entrance to the House of Horrors", width: 1536, height: 656` inside `%header.home-header`. Keep this header above the future React mount. In `app/assets/stylesheets/application.css` make `.home-header img` a block with `max-width: 100%` and `height: auto` so the image retains its proportions on narrow screens.

**Verify:** Migrate/dump both modes; `bin/rails test test/models/room_test.rb test/integration/foundation_test.rb` and its MySQL equivalent. `test/models/room_test.rb` checks presence, invalid and noninteger capacities, duplicate names, the four valid keys, and rejection of unknown keys and the House image as a room choice. The MySQL test also checks `rooms.name` collation via `SHOW FULL FIELDS FROM rooms`. In `foundation_test.rb` GET `/`, assert `header.home-header` contains the House image (digest URL and alt text), then GET the House URL and the four mapped Propshaft URLs; each must return 200 `image/jpeg` with bytes matching its corresponding source file. **Accept:** Both dumps represent the same room constraints; all five supplied assets load, and the House JPEG renders in the Homepage header without JavaScript, a seeded DB or later functionality. **Boundary:** No bookings, upload, or public room picker.

### S03. Canonical Slots and Reservation Record

**Objective:** Reject invalid intervals and missing rooms before an ordinary model write.

**Prerequisites:** S02.

**Files and instructions:** Implement `app/models/booking_slots.rb`, `app/models/reservation.rb`, `db/migrate/*_create_reservations.rb` and the `Room#reservations` association per §§C–D. Always validate the canonical schedule; validate future start on create and whenever either interval endpoint or `room_id` changes. Attach `Select an hourly slot from 01:00 to 07:00 UTC.` and `Select a slot that has not started.` to `:base` for schedule and start-time failures, respectively. Reading or deleting history never runs that check; an unchanged model save can leave a historical row intact, but the Update operation will reject user edits to history. Restrict room deletion now via association and FK; this stage does not expose a booking write path. Only tests may create valid records directly to exercise model behavior.

**Verify:** Migrate/dump both modes; run `bin/rails test test/models/booking_slots_test.rb test/models/reservation_test.rb` and its MySQL equivalent. Use frozen UTC time and test malformed/partial dates, leap day, a DST change date with six UTC slots, midnight and 07:00 starts invalid, 01:00 and 06:00 valid, bad duration, off-minute or subsecond start, exactly-now/past create refused, unchanged historical model valid, both associations, and FK rejection. **Accept:** All model/boundary checks pass independently, without a booking service or seeded rows. **Boundary:** No public/admin booking endpoints until S08/S13.

### S04a. Database Write Guard

**Objective:** Prove the cross-connection serialization primitive and lock timeout on both actual databases.

**Prerequisites:** S03; MySQL service ready; `max_connections: 5` in each database config (§H).

**Files and instructions:** Add `db/migrate/*_create_booking_write_locks.rb`, `app/models/booking_write_lock.rb`, and `app/services/booking_write.rb` with exactly the §D transaction and exception rules. Define a `CommittedTestData` mixin in `test/support/committed_test_data.rb` using `ActiveSupport::Concern`, setting `self.use_transactional_tests = false` in its `included do` class block. Add setup assertions for `Rails.env.test?` and no open transaction and teardown for owned rows (FK-dependent rows first). Require and include it explicitly in each guarded-write test class. Add `test/services/booking_write_test.rb` for first upsert on an absent lock row, commit/rollback, refusal of a caller-owned transaction, and the lock-contention test in §G item 2. Use a plain guarded block in that test; do not implement or call an Operation yet.

**Verify:** Migrate/dump both modes. Run `bin/rails test test/services/booking_write_test.rb` and its MySQL equivalent. **Accept:** Both native adapters prove the second block never runs during an intentional overlapping lock timeout; a subsequent call commits. Nested calls fail explicitly, and no alternative write lock is needed. **Boundary:** No booking command, availability or HTTP routes.

### S04b. Reservation Creation and Last-Place Race

**Objective:** Deliver the first capacity-safe reservation command and its committed-state race proof.

**Prerequisites:** S04a guard and S03 domain model.

**Files and instructions:** Add `app/operations/reservations/{booking,create,occupancy}.rb` exactly as in §D, limiting Booking to create and Occupancy to `count` at this boundary. Implement `Reservations::Create` with parsing then guarded validation/count/save. Add `test/operations/reservations/create_test.rb` using the S04a mixin; cover first/last place, overflow, one-person room, adjacent slots, invalid input, no mutation on refusal, and §G item 1.

**Verify:** `bin/rails zeitwerk:check`, `bin/rails test test/operations/reservations/create_test.rb test/services/booking_write_test.rb` and its MySQL equivalent. **Accept:** Exact count reaches, but never exceeds, room capacity. A sequential overflow must be `slot_full`; two simultaneous last-place calls produce one committed booking and a domain refusal (`slot_full` or a bounded `busy`), on both actual adapters. **Boundary:** No update/delete operation, public API or UI.

### S05. Reservation Update and Delete

**Objective:** Safely move or remove an existing reservation using the proven guard.

**Prerequisites:** S04b.

**Files and instructions:** Extend `app/operations/reservations/booking.rb` for the guarded update variant; add `update.rb` and `destroy.rb` in the same directory. Implement original-record reload, past-original refusal, target room lookup, same-count self-exclusion, end recomputation and no mutation after refusal as in §D. Reuse the guard, failure contract and `Occupancy.count`. Keep count rule in one location, not copied into controllers or models.

**Verify:** `bin/rails test test/operations/reservations` and its MySQL equivalent. In `test/operations/reservations/update_test.rb` and `destroy_test.rb` cover unchanged slot at capacity, time move to full slot, move into full different room, successful move releasing the source place, elapsed-original rejection, missing IDs, and deleting history/future records. Verify rejected moves preserve both rows and both occupancy counts. **Accept:** Shared create suite and all update/delete cases pass on both engines without routes. **Boundary:** No admin or public HTTP work.

### S06. Admin Authentication and Entry

**Objective:** Add the second principal surface and a reusable server-side role gate.

**Prerequisites:** S01a framework and HAML shell, S01b database modes, and S02 Homepage header for the layout check. Tests create their own admin and guest users (no seeds or booking services needed).

**Files and instructions:** Uncomment/update `bcrypt` per §B in `Gemfile`, run `bundle install`, update `Gemfile.lock`. Add `db/migrate/*_create_users.rb`, `app/models/user.rb`; add `app/controllers/admin/{base,dashboard,sessions}_controller.rb`, `app/views/admin/dashboard/show.html.haml`; update `app/controllers/application_controller.rb`, `app/views/layouts/application.html.haml`, `config/routes.rb` and `config/initializers/filter_parameter_logging.rb`. Use `get "admin", to: "admin/dashboard#show", as: :admin` plus `namespace :admin` containing `resource :session, only: [:create, :destroy]`, explicitly `controller: "sessions"`.

1. `GET /admin` is accessible to all; render a `form_with scope: :session, url: admin_session_path, local: true` login form, or a signed-in heading and logout button for an admin until S11b. `POST /admin/session` permits only `session[email_address]` and `session[password]`; require strings. `User.authenticate_by` and `admin?` must both succeed. Otherwise render the same login form with generic 422 `Invalid email or password.` Never repopulate the password.
2. `reset_session` before storing `session[:admin_user_id]` and integer `session[:admin_expires_at] = 8.hours.from_now.to_i`; 303 to `/admin`. In `ApplicationController#current_admin`, require an unexpired timestamp (`Time.current.to_i < admin_expires_at`), load the user, then check `admin?` on every request. `require_admin` returns 403 before resource lookup; `Admin::BaseController` sets its `before_action`. `Admin::SessionsController` instead protects only `destroy` with the same method. `DELETE /admin/session` resets the session and returns 303 to `/admin`; use `button_to` with `method: :delete`. The session uses the Rails encrypted, HttpOnly, SameSite=Lax cookie in this loopback demo; no role is stored in it. Add `Homepage | Admin`, and ensure password fields are filtered from Rails logs.
3. In `Admin::SessionsController` create `RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)`; use `rate_limit to: 10, within: 3.minutes, only: :create, store: RATE_LIMIT_STORE, with: :render_rate_limited`. Render the same login form with HTTP 429 `Too many attempts. Try again in a few minutes.` The store is bounded and process-local (including test), unlike the generated null test cache; all POST attempts count. No distributed limiter is required. Add `test/support/admin_session_test_helper.rb` with a concern that clears this store in setup and teardown; require/include it in every integration class that posts a login, so the full suite does not share one IP's attempt budget across tests.

**Verify:** Migrate/dump both modes; `bin/rails test test/models/user_test.rb test/integration/admin_auth_test.rb` and MySQL equivalent. Assert hashed password and normalized unique email, 422 for guest and wrong password, successful login and logout, 403 for unauthorized logout, and 403 after role removal or eight-hour expiry. Assert `/admin` does not render the Homepage image header. Clear `Admin::SessionsController::RATE_LIMIT_STORE` before and after auth tests; send eleven invalid POSTs from the same test client for ten 422s then 429. Enable forgery protection in a dedicated request test, check rendered token and reject login without one. **Accept:** Login, logout and role checks work with no extra page or seed dependency; inspect `/admin` in a browser without logging in. **Boundary:** No dashboard resource tabs/actions yet.

### S07. Dynamic Demo Data

**Objective:** Provide reproducible, current demo data safely before exposing it publicly.

**Prerequisites:** S02 room schema and bundled image keys, S03 reservation schema, S04a guard, and S06 user model. Both local DBs are migrated; no HTTP changes needed.

**Files and instructions:** Implement `db/seeds.rb` as a call to `DemoSeeds.call` in `app/services/demo_seeds.rb`. Copy the four §C catalog rows verbatim for names, descriptions, capacities and keys; implement §H's fixed examples and idempotency guard. Set `image_key` on new seed rooms without uploading files or storing a filename in the DB. Do not seed outside development/test. Run the batch in one `BookingWrite.with_lock` transaction; use canonical `BookingSlots` and validated rows, not nested calls to reservation operations. This is the sole trusted bulk writer; it verifies zero reservations, distinct groups, and per-group bounds before writing.

**Verify:** `bin/rails test test/services/demo_seeds_test.rb` and its MySQL equivalent, then `bin/rails db:migrate` and `bin/rails db:seed` on a dedicated, unused SQLite development DB. Tests use `CommittedTestData`; check each fresh room's `name`, `description`, `capacity`, `seed_key` and `image_key` against literal expectations from §C, not constants from the seed implementation. Freeze time, run seed twice and at a later UTC date with existing records, and verify all days and mandatory scenarios, protected user rows and credential hash, no bookings beyond capacity and no damage to admin changes. Precreate the Attic name without `seed_key`; expect `DemoSeeds::Conflict` with the message in §H, existing row unchanged and no partial initialization. Also test an existing guest with the demo email is not promoted. **Accept:** Fresh DB yields the four specified room records with their bundled image keys, one admin, nonempty reservations tomorrow through day 30 inclusive, and all specified occupancies. Rerun behavior matches §H. **Boundary:** No dependency on HTTP availability or browser code.

### S08. Public Availability and Booking API

**Objective:** Expose and test the two narrow JSON endpoints without React.

**Prerequisites:** S04b create and occupancy rules; S01a HAML CSRF meta tag. Automated tests create their own committed data; seeds are not a dependency.

**Files and instructions:** Add `app/operations/reservations/availability.rb`, extend `occupancy.rb` with `counts`, create `app/controllers/api/{availability,reservations}_controller.rb`, and add a `namespace :api, defaults: { format: :json }` block to `config/routes.rb` with `get "availability", to: "availability#show", as: :availability` and `resources :reservations, only: :create`. Implement the §D contracts and call the real operations. In Availability capture one `Time.current` for the whole query, suppress past and started slots, and use one grouped count for the day. Do not return individual bookings from availability. Keep Rails CSRF enabled for POST.

**Verify:** `bin/rails test test/operations/reservations/availability_test.rb test/integration/public_booking_api_test.rb` and MySQL equivalent. Use `CommittedTestData` in the HTTP class. Test privacy, same-day boundary, empty bathroom, near-full and full slots, 404/422/409, malformed JSON 400, 201 with stored UTC datetimes, and stale read followed by second POST. To trigger 503 without another timed DB race, stub `Reservations::Create.call` for one request with a failure object implementing `success? == false` and `[:code] == :busy`; test the JSON envelope and unchanged row count. Use a Minitest fake or temporarily replace/restore the method in `ensure`; the actual DB timeout is proven in S04a. With CSRF enabled, GET `/` for the token and POST with same session and token; another POST without it writes nothing. **Accept:** On both adapters, GET returns only future bookable hours and POST cannot overbook even after a stale GET. **Boundary:** No JS bundle or admin booking UI.

### S09. React Mount and Room Preview

**Objective:** Prove npm-to-Propshaft-to-HAML integration and render the room picker.

**Prerequisites:** S08 endpoints and S02 image helper and header; S07 seeded local demo for manual browser checks; Node version in §B.

**Files and instructions:** Add `.node-version` (`22.22.2`), `package.json`, `package-lock.json`, `vitest.config.mjs`, `app/javascript/{booking,booking_app,booking_app.test}.jsx`, and `app/assets/builds/.keep`. Pin §B npm versions; run `npm install` once to create the lockfile. Set `build` to `esbuild app/javascript/booking.jsx --bundle --format=esm --jsx=automatic --outfile=app/assets/builds/booking.js`, `test` to `vitest run`. Use `test: { environment: "jsdom" }` and `oxc: { jsx: { runtime: "automatic" } }` in Vitest config; import test globals and register `afterEach(cleanup)` explicitly. Propshaft discovers existing `app/assets/*` subdirectories; no custom path addition. Update `app/controllers/home_controller.rb`, `app/views/home/show.html.haml`, and `app/views/layouts/application.html.haml`: emit §A/§D data, mount below the S02 header only on Homepage, and set the script as `type: "module"` with `javascript_include_tag "booking"` from the layout's `yield :head`/Home `content_for :head`. Use a controlled labeled room selector (first by default; no-room message if none), show the selected room's name, description, capacity and `image_url` from `room_image_url(room)`. Changing rooms changes the preview, not the header. Only show implemented controls. Use `app/assets/stylesheets/application.css` for responsive layout, readable controls and visible keyboard focus, no inline styles.

**Verify:** `npm ci`, `npm run build`, `npm test`, `bin/rails test test/integration/foundation_test.rb`; add a transactional request case with its own `Room` and a description containing quotes and `<script>` as text. Assert the parsed `data-config` retains the exact text and IDs with no extra HTML script; check route paths, asset URLs and the module tag. JS test switches rooms and verifies image, description and capacity; include no rooms. Open `/` at `1280x800` and `390x844` using seeded SQLite; keep `house.jpg` visible above the picker and select each room to check its exact §C text, capacity and matching JPEG. Confirm in browser network tools that assets load from the same origin without third-party requests. **Accept:** At both widths the header remains unchanged and each of the four room selections shows its own preview. No date/slot/POST interaction is required yet. **Boundary:** No date/slot UI until S10a, no submission until S10b.

### S10a. React Date and Availability

**Objective:** Display only currently offered time choices and communicate loading and near-full states.

**Prerequisites:** S09 mount, S08 GET contract, S07 seeded data only for the manual check.

**Files and instructions:** Extend `app/javascript/booking_app.jsx`, `app/javascript/booking_app.test.jsx` and `app/assets/stylesheets/application.css`. Use a labeled date input default/min server `today`, and a labeled slot select (placeholder, no automatic choice). On room/date change synchronously clear selected hour and old choices; a result is usable only if its `(roomId, date)` and generation match the current request. Fetch with `URLSearchParams`, `AbortController` and a monotonically increasing generation; abort on cleanup, ignore late settlements, show loading/empty/error text, and do not fetch without both inputs. Display only API slots, including `remaining`; show `Only 1 place left!` for a selected slot whose payload says `nearly_full`. No submit button yet.

**Verify:** `npm test`, `npm run build`. Add UI tests for initial GET, room/date changes, out-of-order responses (mocked fetch that ignores abort), loading/error/empty states, warning and empty bathroom. In a browser on a fresh seed, choose the Attic special date and see only `04:00-05:00 UTC`. **Accept:** Slot list never shows stale results as current or a slot the API removed. **Boundary:** No POST or booking feedback yet.

### S10b. React Booking Submission

**Objective:** Complete the public form, including visible conflict recovery without navigation.

**Prerequisites:** S10a controls and refresh behavior, S08 POST and CSRF contract.

**Files and instructions:** Extend the same component/test/CSS files as S10a. Disable submit while loading, saving, or without a currently offered hour; disable room and date edits while POST is pending. POST the §D body using the meta CSRF token. After **every** POST attempt (201, 409, 422, 503, non-JSON or network error), clear selection and trigger a new GET for the same tuple through S10a's loading logic. Keep booking feedback separate from availability so refresh does not hide it. Do not auto-POST again; ambiguous network errors say the booking could have succeeded and a refresh does not confirm its outcome. Use `role="status"`/`role="alert"` where applicable and preserve keyboard focus indicators.

**Verify:** `npm test`, `npm run build`, `bin/rails test test/integration/public_booking_api_test.rb`. Rendered tests cover missing choice/disabled submission, one POST per attempt with token/body, success, 409 and network failure, and the refresher issuing a new GET without erasing feedback. Browser: prepare a fresh disposable SQLite demo using `bin/rails db:setup` with a dedicated suffix. Open tomorrow's last Basement place in two guest sessions before submitting; only one succeeds, the other gets conflict feedback. **Accept:** Guest booking and conflict recovery work without navigation or another login. **Boundary:** No admin resource controls yet.

### S11a. Guarded Room Writes

**Objective:** Protect room changes before exposing any administrative room writer.

**Prerequisites:** S04a guard, S04b create, S03 FK and S02 bundled catalog.

**Files and instructions:** Add `app/services/rooms/write.rb` and `Occupancy.peak` in `app/operations/reservations/occupancy.rb`. Implement §D's `Rooms::Write` contract, accepting only name/description/capacity/image_key at this boundary. Build a new room or load by ID under the guard. Assign/validate before checking peak. Return `capacity_below_bookings` with `Capacity cannot be lower than the existing peak of N.` when the proposed value is too low, and `room_has_reservations` with `Delete this room's reservations before deleting the room.` when any reservations exist. Use `save!`/`destroy!` under the guard; map expected validation errors and unique constraint refusal, never rescue an entire database exception family. Preserve the old room when rejected.

**Verify:** `bin/rails test test/services/rooms/write_test.rb` and MySQL equivalent. Use `CommittedTestData` and test create/edit/delete on empty rooms, blocked deletion even for a historical booking, blocked capacity reduction below historical peak, allowed equal or higher capacity, and the competing create/reduction of §G item 3. **Accept:** No room command can orphan reservations or reduce capacity below committed occupancy, even concurrently. **Boundary:** No controller, admin form or upload.

### S11b. Admin Rooms Workspace

**Objective:** Expose room CRUD with existing image choices, one protected workspace and no duplicate business rules.

**Prerequisites:** S11a room command, S06 role gate, S02 bundled catalog, S08 API for the edited-capacity integration check.

**Files and instructions:** Add `app/controllers/admin/rooms_controller.rb`, `app/views/admin/workspace.html.haml` and `app/views/admin/rooms/{_panel,_form}.html.haml`. Add `resources :rooms` to `namespace :admin` in `config/routes.rb`; update `app/controllers/admin/dashboard_controller.rb` to redirect authenticated visits to `admin_rooms_path` (unauthenticated visits still render login). Workspace renders Rooms as active navigation (add Reservations in S13), flash/errors and a logout `button_to` using method `:delete`; use `aria-current="page"` on the active navigation link. Then render the Rooms panel. List name ordered by name then id; details show name, description, current image, capacity and reservation count. `@active_tab = :rooms`, `@mode` is `:index`, `:show`, `:new` or `:edit`; `@room` is the selected/new record or `nil` on index. Display a labeled local `form_with model: [:admin, @room]` on new/edit with name, description, integer capacity and current bundled choice. Permit only those four fields, passing only scalar strings or integer capacity. A failed create/update/destroy renders `:new`/`:edit`/`:show`, respectively, with submitted safe values and the §D status. Use `button_to "Delete", admin_room_path(@room), method: :delete`; no Turbo. Add workspace, navigation, field and focus styling in `app/assets/stylesheets/application.css`.

**Verify:** `bin/rails test test/integration/admin_rooms_test.rb test/services/rooms/write_test.rb` and MySQL equivalent. Use `CommittedTestData` in the HTTP class. Cover all seven routes, even direct anonymous requests with missing IDs (403 before lookup), and an authorized omitted resource (404); add invalid form, blocked deletion/reduction and a public API booking honoring edited capacity. Browser: log in, create and edit a temporary unbooked room with a different bundled image, then delete it. **Accept:** The room tab is usable and server-protected; room commands remain its only writer. **Boundary:** No upload UI or reservation tab.

### S12a. Reusable Image References and Safe Reads

**Objective:** Migrate bundled-only rooms without loss and prove safe serving of referenced raster media.

**Prerequisites:** S11b Rooms details, S02 catalog, S03 room FK. On each adapter use a dedicated dev DB with a bundled room and reservation created before these migrations (S07 seeds suffice). Record their IDs, image key and slot before migrating.

**Files and instructions:** The S01a generator enables the Active Storage engine but does not install its tables. Run `bin/rails active_storage:install` once here and add `db/migrate/*_add_uploaded_images_to_rooms.rb` after the generated migration, per §C. Update `app/models/{room,room_images}.rb`; normalize blank image keys to `nil`, validate exactly one reference, and implement `RoomImages.uploads` as blobs with `service_name: "room_images"`, MIME `image/png` or `image/jpeg`, and `byte_size` in `1..2.megabytes`. Implement the named Disk service and root from §H in `config/storage.yml`, selecting `:room_images` in `config/environments/{development,test}.rb`. Do not call `attach`, variants, analyzers, or direct-upload helpers. Built-in Active Storage routes remain disabled. Do not use Active Storage `unattached` as an orphan check, because direct room references are not `ActiveStorage::Attachment` rows.

Add `app/controllers/room_photos_controller.rb#show` and `get "room_photos/:id", to: "room_photos#show", as: :room_photo` to `config/routes.rb`. Resolve a valid numeric ID in `RoomImages.uploads` and require at least one room referencing it. Use `bytes = blob.download_chunk(0...blob.byte_size)` (size already bounded by the query) and `send_data` with the catalog raster MIME, `disposition: "inline"`, and `X-Content-Type-Options: nosniff`. Return 404 for `ActiveStorage::FileNotFoundError`, missing/noncatalog IDs, unassigned entries or `bytes&.bytesize != blob.byte_size`. Never expose service keys in URLs. Update `app/helpers/room_images_helper.rb#room_image_url` for `room_photo_path`, retaining bundled paths; Home calls `helpers.room_image_url(room)` and admin room detail calls the helper from HAML. Leave the bundled-only admin save workflow in place until S12b; there are no normal uploads yet.

**Verify:** Migrate/dump both, and check the room and reservation seeded **before** migration still have the same IDs, key and slot. Add `test/fixtures/files/room.png` (small real raster), `test/integration/room_photos_test.rb`, and cases in `test/models/room_test.rb`. Create a valid uploaded test blob via Active Storage and direct room association in tests only. Check linked bytes/MIME/nosniff, 404 for unlinked/noncatalog or missing content, blocked missing/both refs, intact bundled behavior, and FK checks; use the dedicated `test` Disk root and clean owned files. `bin/rails test test/integration/room_photos_test.rb test/models/room_test.rb test/integration/admin_rooms_test.rb` and MySQL equivalent. **Accept:** Existing data survives migration, and a room's valid uploaded reference serves safe raster bytes in both modes. **Boundary:** No upload endpoint or selector for newly stored blobs yet.

### S12b. Admin Image Upload and Selection

**Objective:** Allow uploads, existing-image selection and replacement while preserving reuse.

**Prerequisites:** S12a media schema/catalog/reads, S11b Rooms UI and S06 role gate.

**Files and instructions:**

1. Add `app/services/room_image_upload.rb` with `.call(upload)` returning `{ok:, record:, code:, messages:}`. Accept only `ActionDispatch::Http::UploadedFile` with `1..2.megabytes` bytes. In a rewindable IO, detect only `image/png`/`image/jpeg` using `Marcel::MimeType.for(io)` without trusting original name/MIME; rewind again before storage. Generate filename `room-<uuid>.png` or `.jpg`; never accept caller blob keys. In an Active Record transaction call `ActiveStorage::Blob.create_and_upload!` with that IO, filename, MIME, `service_name: "room_images"`, and `identify: false`. Rescue `IOError`, `SystemCallError` and `ActiveStorage::IntegrityError` outside the transaction as `storage_unavailable`, message `Could not store the image. Try again.` Invalid files return `invalid_input` with `Upload a PNG or JPEG of at most 2 MiB.` Signature detection is basic validation, not full raster decoding. An eventual DB commit failure after a disk write can leave an unreferenced disk object, not a catalog option; no automatic cleanup is in scope.
2. Add `app/controllers/admin/room_images_controller.rb#create` protected by `Admin::BaseController`, with `resources :room_images, only: :create` in the admin namespace. In `app/views/admin/rooms/_panel.html.haml` (index only), place a separate multipart POST form with field `image`, accept PNG/JPEG, never nest it in the room form. Success redirects 303 to `admin_rooms_path`, with the generated catalog filename in the notice. Invalid input or storage error re-renders the workspace in Rooms/index with 422 or 503 respectively; do not change any room. Upload first from the list, then choose the catalog item when creating/editing the room. There is no preview of an unassigned item and no upload deletion endpoint.
3. Update `app/controllers/admin/rooms_controller.rb`, `app/services/rooms/write.rb` and admin Rooms `_form`/`_panel`. Replace permitted `image_key` and its form field with `room[image_choice]`, selecting exactly one `bundled:<key>` or `upload:<id>`. Bundled choices use §C's known keys; upload choices use `RoomImages.uploads.order(:id)` and show the generated filename. Resolve the choice in `Rooms::Write` inside the existing guard, reject malformed/unknown values as `invalid_input`, set the selected reference and explicitly clear the other. Initialize the edit select from the persisted reference, preserve the attempted choice on refusal and keep showing the last persisted image until saved. Never purge the previous blob as a side effect of a room change or deletion. Update `test/services/rooms/write_test.rb` and `test/integration/admin_rooms_test.rb` to send `image_choice` in place of `image_key`, keeping all prior invariant assertions.

**Verify:** `bin/rails test test/services/room_image_upload_test.rb test/services/rooms/write_test.rb test/integration/admin_room_images_test.rb test/integration/admin_rooms_test.rb test/integration/room_photos_test.rb` and MySQL equivalent. Use `CommittedTestData` for guarded writes and the committed upload-rollback test to prove the catalog row was not committed. Verify unauthorized upload, spoofed MIME, SVG and oversize rejection; one service test forces `IOError` from `ActiveStorage::Service::DiskService#upload` before bytes are written (restore the scoped stub in `ensure`) and asserts no catalog row survives. Verify upload/select/reuse by two rooms, replacement for only one, and unchanged bundled seed rooms. Browser: upload on Rooms, use the notice to select the image for a new room, then reuse it in a second room. **Accept:** Both adapters support upload, selection, replacement and reuse; the old image remains viewable by the other room. **Boundary:** No admin reservation tab or upload deletion.

### S13a. Admin Reservation Reads and Filters

**Objective:** Make stored reservations visible in the authorized workspace without introducing mutation controls yet.

**Prerequisites:** S03 room/reservation model, S06 authorization and S11b workspace; no dependence on uploaded media or write operations.

**Files and instructions:** Add `app/controllers/admin/reservations_controller.rb < Admin::BaseController` and `app/views/admin/reservations/_panel.html.haml`. In `config/routes.rb` add `resources :reservations, only: [:index, :show]` to the admin namespace. In `app/views/admin/workspace.html.haml` add the Reservations tab and panel branch; in admin Rooms `_panel.html.haml` add a details link to `admin_reservations_path(room_id: @room.id)`. Use `@active_tab = :reservations`; render the common workspace. In `:index` render a labeled GET form for optional room and UTC date, listing by `[start_datetime, id]` and preloading rooms. Absent or blank scalar filters are omitted, other inputs use §D parsers and intersect. Invalid filters return 422 and preserve submitted scalar values; valid filters without matches return 200 and an empty state. In `:show` display the room, UTC start/end and id, including historical reservations. Missing IDs return 404 after the role gate.

**Verify:** `bin/rails test test/integration/admin_reservations_read_test.rb test/integration/admin_rooms_test.rb` and MySQL equivalent. Read tests create their own rooms and valid bookings in ordinary test transactions. Check anonymous 403 for both routes, authorized missing-ID 404, chronological order, room/date intersection across adjacent dates, invalid scalar and nonscalar filters, no matches and historical detail. In the browser sign in and navigate from a room's detail to its filtered bookings. **Accept:** Both tabs work in the same workspace, and indexed/detail reads expose nothing before authorization. **Boundary:** Reservation write routes and buttons do not exist yet.

### S13b. Admin Reservation Forms and Writes

**Objective:** Complete reservation CRUD by exposing the already verified booking commands.

**Prerequisites:** S13a reads and layout, S05 operations and S06 role gate.

**Files and instructions:** Expand `resources :reservations` in `config/routes.rb` to all seven REST actions. Extend `app/controllers/admin/reservations_controller.rb` and `app/views/admin/reservations/_panel.html.haml`; add `_form.html.haml` there. Use a local `form_with scope: :reservation` in `:new`/`:edit`: POST to `admin_reservations_path` or PATCH to `admin_reservation_path(id)`. New date defaults to UTC today with no selected hour; edit preselects room/date/hour. Offer `BookingSlots::HOURS` with UTC interval labels; if there are no rooms show a message and no submit. Accept only `room_id`, `date`, `start_hour`, and let `Reservations::Create`/`Update` validate and save. For delete use `button_to` with `method: :delete`, calling `Reservations::Destroy`. Use §D statuses; on refusal retain submitted safe fields and re-render `:new`/`:edit`, or `:show` for failed delete. Hide edit for started reservations. Direct GET edit on history returns 303 to its detail with an alert, direct PATCH is refused by the operation. Server logic, not the form, authoritatively rejects full slots.

**Verify:** `bin/rails test test/integration/admin_reservations_test.rb test/integration/admin_reservations_read_test.rb test/operations/reservations` and MySQL equivalent. Add `admin_reservations_test.rb` with `CommittedTestData`; check unauthenticated write/form routes, authenticated create/edit/delete, a full-slot refusal shared with the public API, self-exclusion, cross-room move and original rows retained after refusal. Time-travel to verify historical delete (but no edit) and an expired session's inability to write. Browser: create an available future booking, check detail, edit it then delete. **Accept:** Admin write controls use existing rules and leave no anonymous read/edit/delete route. **Boundary:** No further application features.

### S14. README and Full Demonstration Verification

**Objective:** Make the complete demo reproducible from clean local setups and close the final checklist.

**Prerequisites:** S13b and all preceding gates, including S10b public booking and S12b uploads; Docker, Ruby/Node/Bundler, and disposable verification DBs/disk roots with isolated names. Use a local Compose service dedicated to this demo that can be stopped without interrupting other work. Do not reset an existing DB without separate permission.

**Files and instructions:** Write `README.md` with exactly the five numbered headings `1. Selected Theme`, `2. DECISIONS`, `3. Why the Capacity Algorithm Works`, `4. Technology Stack`, `5. Project Setup`. Include §A–D design rationale in concise form; keep section 3 to 2–3 sentences explaining aligned slots, exclusion on edit and the same-transaction guard on both adapters. Section 5 gives both literal setup paths in §H, expected URL, credentials explicitly labeled demo-only, test/lint commands, UTC date for chosen seed scenario (formula, no fixed calendar date), recovery from common setup failures, and non-destructive reseeding vs an explicitly destructive reset. Explain both disk roots and retained images, file/type/size limits, and local-only authentication limitations. Update only a real defect uncovered by verification; do not add product features or relax tests.

**Verify:** Use §H on fresh disposable targets for each mode; first prove SQLite can start with the demo MySQL service stopped. Run `npm ci`, `npm run build`, `npm test`, `bin/rails zeitwerk:check`, `bundle exec rubocop`, `bin/rails test` and `HOH_DB=mysql bin/rails test`. Run §I on both modes, including stop/restart without data loss. On MySQL also use `docker compose stop mysql` then `docker compose up -d --wait mysql` without deleting the volume, and confirm rows survive. Record checks actually run. **Accept:** README commands work without preexisting rows; both modes and full suites pass; §I can be verified without hidden steps. **Boundary:** Implementation complete only on explicit S14 acceptance; no deployment, Git publishing or further features.

## G. Test Strategy

| Suite | What it verifies | Introduced |
| --- | --- | --- |
| Foundation and model | Exact dependencies, HAML render, both adapters, constraints and time boundaries | S01a, S01b, S02, S03, S06, S12a |
| Operation and concurrency | Committed atomic capacity enforcement, stale read, valid updates and delete | S04a, S04b, S05, S08, S11a |
| HTTP and authorization | Server role gate, safe forms, invalid/no-CSRF requests, API status and CRUD | S06, S08, S11b, S12a, S12b, S13a, S13b |
| Seeds and images | Exact default text and bundled JPEG mapping, repeated seed behavior, day/occupancy guarantees, restricted storage and shared media | S02, S07, S09, S12a, S12b |
| React | Component state and actual response handling via mocked HTTP, not simulated business rules | S09, S10a, S10b |

**Guarded tests need real commits.** Rails normally wraps each test in a transaction, which the guard rejects. Include `CommittedTestData` and use `self.use_transactional_tests = false` in **every test class that reaches guarded writes**, including request tests and seed runs, except the dedicated nested-transaction refusal case that explicitly opens its own transaction. Do not load fixtures globally or call these writers inside fixture/setup transactions. Ordinary read/local validation tests may use transactions. Run serial suites against a dedicated, unseeded `Rails.env.test?` DB; no in-memory SQLite. Clean each test's rows in FK order (reservations, then rooms, then any test blobs/files); also remove owned users. Do not use development or external DBs. Choose UTC tomorrow for threaded tests, so they need no clock stub during contention. For tests without contentions freeze time with Rails time helpers.

1. **S04b last-place race:** Create a capacity-2 room and one committed booking. Start two threads, each in `Rails.application.executor.wrap` plus `connection_pool.with_connection`. Report both connection object IDs on a `Queue` and require them to differ; wait for the parent to release both via a start queue, then call real `Reservations::Create`. Bound queue waits and joins to 15 seconds, propagate thread exceptions, release workers in `ensure` and clean up only after check-in. Assert one success, the loser `slot_full` or `busy` if the bounded wait expired, and final count 2 from a fresh query. A separate sequential overflow check must yield `slot_full`.
2. **S04a deliberate contention:** Prepare a room using committed test data. Thread A enters `BookingWrite.with_lock`, signals to the parent after acquisition and waits on a release queue. A different connection in thread B tries `BookingWrite.with_lock { room.update!(name: "Should never run") }` while A remains open. Expect `BookingWrite::Busy`, and unchanged room name. Release A in `ensure`, join both workers, then run a successful guarded update; do not assert exact duration. Use the same 15-second bounds and confirm adapter identity before the test. The independent test proves the guard actually waits/fails closed, not just lucky scheduling of item 1.
3. **S11a room reduction race:** Use item 1's worker setup with a capacity-2 room and one committed booking. Compete `Reservations::Create` for another place against `Rooms::Write` reducing capacity to 1. Require exactly one success; expected loser `capacity_below_bookings` if create won or `slot_full` if reduction won (or `busy` if the bounded wait expired). Assert final `(capacity, occupancy)` is `(2, 2)` or `(1, 1)` respectively, and assert the sequential reduction refusal separately.

For CSRF tests, temporarily enable `ActionController::Base.allow_forgery_protection` in a serial integration test, restoring the original in `ensure`. Accept Rails' generated failure response/exception as applicable, but explicitly verify that the protected action did not mutate anything. For frontend tests, clear mocks and restore global `fetch` between tests; use only deterministic responses defined by §D. Manual browser checks supplement, not replace, the race test on MySQL and SQLite.

## H. Setup and Seed Strategy

**Why SQLite is the second mode.** An honestly database-free memory store would need a separate repository with its own relationships, query semantics, file reference management and reset/locking logic, and cannot run Active Record migrations or `db:setup`. It loses data on restart and needs specific cross-process coordination to avoid overbooking. SQLite is a database, but needs no server or Docker; one local file permits full Active Record/Trailblazer CRUD, durable changes, shared seeds, and process-safe serialization at a cost of one native writer at a time. MySQL is the persistent server mode with InnoDB transactions, a named volume, and the same application code. Both use the guarded write protocol; a busy DB may decline a request, never overbook.

**Literal database configuration (`config/database.yml`):** Use an ERB header to read `mode = ENV.fetch("HOH_DB", "sqlite")` and validate it against `sqlite`/`mysql`; reject any other value. Read `HOH_DB_SUFFIX`, default empty; allow only `\A[a-z0-9]{0,20}\z` and use `suffix = value.empty? ? "" : "_#{value}"`. Emit a single primary config for `development` and `test` with `max_connections: 5`. Within each one select the fields by `mode`, including the literal `schema_dump:` key; `schema_dump: <%= mode == "mysql" ? "mysql_schema.rb" : "schema.rb" %>` selects both the dump and what `db:setup` loads. Set `config.active_record.schema_format = :ruby` in `config/application.rb`.

| Setting | SQLite | MySQL |
| --- | --- | --- |
| `adapter` | `sqlite3` | `mysql2` |
| `database` | `storage/<environment><suffix>.sqlite3` | `house_of_horrors_<environment><suffix>` |
| `schema_dump` | `schema.rb` | `mysql_schema.rb` |
| Connection | `timeout: 5000`; keep Rails default foreign keys and WAL | `host: 127.0.0.1`, `port: 3307`, `username: root`, `password: <%= ENV.fetch("MYSQL_ROOT_PASSWORD", "hoh-local-mysql").to_json %>` |
| Other | No Docker, server, or MySQL password | `encoding: utf8mb4`, `collation: utf8mb4_0900_bin`, `variables: {innodb_lock_wait_timeout: 5}` |

The MySQL root credential is for the loopback demo and DB tasks only. Base collation and InnoDB also belong in Compose so the Ruby schema can reload consistently. Active Storage uses Disk root `storage/room_images/<environment>-<mode><suffix>`; evaluate the same validated ERB mode/suffix in `config/storage.yml`. SQLite development and test database files and Disk media persist until explicitly deleted. Do not use an ambient `DATABASE_URL`/`SCHEMA` or configure a deployable production environment.

`compose.yaml`: service `mysql`, image `mysql:8.4`, bind `127.0.0.1:3307:3306`, named volume `mysql_data:/var/lib/mysql`, same password fallback via `${MYSQL_ROOT_PASSWORD:-hoh-local-mysql}`, `MYSQL_ROOT_HOST: "%"` to permit the host Rails connection through the loopback binding. Set `command: ["--collation-server=utf8mb4_0900_bin", "--default-storage-engine=InnoDB"]`. Healthcheck: `CMD-SHELL` with `mysql --protocol=TCP -h 127.0.0.1 -uroot --password="$${MYSQL_ROOT_PASSWORD}" -Nse 'SELECT 1'`, interval `3s`, timeout `3s`, retries `30`; the TCP query must succeed, not merely find a process. Container initialization password applies when the volume is first made; do not erase a retained volume to fix a mismatch. Do not commit real credentials or serve on a public interface.

**Setup after S14.** Common: `bundle install`, `npm ci`, `npm run build`, with `DATABASE_URL`, `SCHEMA`, `HOH_DB` and `HOH_DB_SUFFIX` unset for the default examples. For MySQL: `docker compose up -d --wait mysql`, `HOH_DB=mysql bin/rails db:setup`, `HOH_DB=mysql bin/rails server -b 127.0.0.1`. For SQLite: `bin/rails db:setup`, `bin/rails server -b 127.0.0.1`. Visit `http://127.0.0.1:3000/`. `db:setup` creates and loads the selected Ruby schema and runs seeds for development; use `db:migrate` on an existing install, never `db:setup` against one. On a clean checkout prepare disposable test DBs with §F before running tests. Use distinct verified-unused suffixes for S14 manual setup and tests; pass the same environment prefix to every command for a target.

**Migration replay.** Use other verified-unused DB suffixes, and ensure both named replay files do not exist before starting. Run `HOH_DB_SUFFIX=replaysqlite SCHEMA="$PWD/tmp/migration_replay_sqlite.rb" bin/rails db:migrate` and `HOH_DB=mysql HOH_DB_SUFFIX=replaymysql SCHEMA="$PWD/tmp/migration_replay_mysql.rb" bin/rails db:migrate`. `SCHEMA` redirects both lookup and output for that invocation; because the alternate file did not exist, Rails ran the migrations instead of loading the checked-in dump. Run `bin/rails db:migrate:status` with those same DB prefixes **without** `SCHEMA`; expect every migration `up`. Verify `db/schema.rb` and `db/mysql_schema.rb` were not changed by replay. Never export `SCHEMA` in a shared shell.

**Seed algorithm (`DemoSeeds.call`):**

1. Reject environments other than development and test. Enter `BookingWrite.with_lock`, resolve rooms by `seed_key`, and create missing entries in §C catalog order with the exact name, description and capacity in each row and `image_key` set to its key. Do not normalize text beyond the model's required name trim or overwrite any admin changes to existing seed rooms, including image replacements. If a missing key's default name is already taken, raise `DemoSeeds::Conflict` with `Cannot seed room <key>: its default name belongs to another room.` Find or create the administrator `admin@example.test` with password `house-of-horrors-demo-2026` and role `admin`. These are intentional public demo fixtures; do not reset an existing password or role silently. If the email belongs to a non-admin, raise `DemoSeeds::Conflict` with `The demo email is already assigned to a non-admin user.` Never delete unrelated data; the outer guard rolls back the complete call if a conflict is raised.
2. If any reservation exists, preserve all of them, do not fill gaps, and report that reservations were retained. If none exists but canonical capacities have been changed, preserve the rooms and report that sample occupancy was skipped because this is no longer a fresh demo. Otherwise capture `today = Time.current.to_date` (application timezone) once after acquiring the guard. Iterate tomorrow through `today + 30`, each canonical room in the catalog order, each hour in `BookingSlots::HOURS`. Use `Random.new(20261123)` for `0..capacity` sample counts, with explicit overrides below. No dates are hardcoded. Verify uniqueness of `[room_id, start_datetime]` groups and `0 <= count <= capacity`; use the canonical interval and `count.times { Reservation.create!(...) }`. No nested Trailblazer call, no concatenated SQL, no `validate: false`. Empty database plus single bounded group per room/slot proves this bulk write preserves the invariant. Failures roll back the entire batch.
3. Guarantee at least one `01:00` booking for each room on each of the 30 days before applying overrides. Tomorrow `01:00`: Basement 9/10, Kitchen 2/3, Attic 5/6; Basement `02:00` 3/10 and `03:00` 0/10. On `today + 7`: Bathroom `02:00` is empty; Attic `04:00` is empty, all five other hours 6/6. On a fresh demo there are always full, partial, near-full and empty examples; the only open Attic hour is visible through the normal UI. For seed status log only the outcome after commit: `Demo reservations generated from YYYY-MM-DD to YYYY-MM-DD.`, `Existing reservations retained.`, or `Sample occupancy skipped: canonical capacities have changed.` Never log passwords.
4. `bin/rails db:seed` (with correct mode prefix) never deletes existing reservations and repopulates an empty reservation table if canonical capacities are intact. To refresh aged demo data, prefer a new suffix and `db:setup`. Document the alternative `HOH_DB_SUFFIX=<verified-disposable-suffix> SKIP_TEST_DATABASE=1 bin/rails db:reset`, also prefixing `HOH_DB=mysql` for MySQL. It **destroys** that development DB and must not run without permission and a verified target. A DB reset does not remove old upload bytes; no automated deletion of storage or Docker volumes.

## I. Final Acceptance Checklist

- [ ] `bin/rails --version` reports `Rails 8.1.4.1`, Zeitwerk, all Rails tests on both adapters, Vitest, asset build and RuboCop pass. The concurrency tests report one committed last-place claim, no overbooking, and a fail-closed busy path on each adapter.
- [ ] A genuinely fresh MySQL Compose setup and a fresh SQLite setup with no MySQL server each start with the four §C room names, descriptions, capacities and image keys and the documented admin. Validate both normal `db:setup` and migration replay; verify data and uploaded media persist after restarting Rails, and MySQL data survives Compose stop/start with the named volume intact.
- [ ] On desktop and mobile, `/` shows the shared navigation and the JPEG from `sources/house.jpg` inside its header even with JavaScript disabled. With JavaScript enabled use a fresh seed to check that selecting each room shows its verbatim §C name and description, capacity and matching JPEG from `sources/room1.jpg` through `sources/room4.jpg`. The image in the header never changes when switching rooms and is absent on `/admin`.
- [ ] Changing date on `/` updates visible choices without stale results. Yesterday and already-started hours are not offered. On the seed date plus seven days, the Attic offers only `04:00-05:00 UTC`; selecting tomorrow's Basement `01:00` shows `Only 1 place left!`; selecting the empty Bathroom `02:00` on seed date plus seven days does not warn. Check before consuming the seeded examples.
- [ ] Public guest books without logging in. The UI shows outcome and refreshes. From two independent browser sessions load tomorrow's Basement `01:00` last place, book in one, then submit stale availability from the other; only the first succeeds and the second gets visible conflict feedback.
- [ ] `/admin` offers login in-place (no separate principal page); after auth both tabs work. Without a valid admin cookie, all protected resource actions return 403 regardless of IDs. Logout ends access and non-admin authentication does not confer a role.
- [ ] Admin views, creates, updates and deletes an unbooked room, uploads a valid raster, reuses an existing image on another room and replaces one reference. SVG/oversize submissions are rejected. Booked room deletion and below-peak capacity cuts are rejected without modifying rows.
- [ ] Admin lists, filters, shows, creates, edits and deletes reservations. An unchanged reservation at capacity can be saved; moving to a full room fails and preserves the old slot. Adjacent hours are independent. Verify the historical view/delete versus move rule with the time-controlled S13a/S13b integration tests rather than waiting for a slot to pass during the walkthrough.
- [ ] Seed integrity passes on both adapters: tomorrow through day 30, all four capacities, exactly one free Attic slot, near-capacity examples, no higher count than room capacity, and safe reseeding. README contains numbered sections, clear literal setup/test/reset commands, and the 2–3 sentence capacity explanation.

## Appendix: Critical Plan Audit

**Method:** Draft all stages first, then review independently in two read-only passes: (1) assignment coverage, stage size, prerequisites and test boundaries; (2) exact Rails, adapter, tooling and media mechanics. Integrate the findings and recheck the revision against the assignment. Dependency availability and framework source were inspected; this is not evidence of a working application. Rails suites, end-to-end database races, Compose startup and browser checks are `NOT RUN` in the planning task. The stage gates are where that evidence must be produced.

**Changes from audit:** Split six broad stages: framework/MySQL, locking/booking, availability/submit, room commands/forms, media references/uploads, and admin reservation reads/writes. Defined operation failure semantics, adapter/schema selection and safe migration replay, serial nontransactional test setup, bounded contention outcomes, session/limiter tests and safe upload failure injection. Explicitly tied the seeded visual checks to deterministic dates and occupancies.

| Stage | Reviewed workload and usable evidence at the boundary |
| --- | --- |
| S01a | Framework integration only; HAML, Operation success/refusal and SQLite verified without domain tables, MySQL or JS. |
| S01b | One adapter, one Compose service and one smoke suite; nothing calls domain models. |
| S02 | One table and five supplied JPEGs; header and model/Propshaft checks use no later reservations, seeds or uploads. |
| S03 | One table and deterministic slot policy; ordinary model tests need no guard or seeds. |
| S04a | One lock primitive, two adapters and a deliberate contention test, requiring no booking Operation. |
| S04b | One command and bounded last-place race; no update/delete, API or browser dependency. |
| S05 | Update and delete only, built on the existing guard and occupancy; tests exercise operations directly. |
| S06 | One model and admin session flow; test-created accounts, no seeds or resource routes. |
| S07 | One seed transaction and deterministic assertions against stored records only. |
| S08 | Two JSON endpoints with real operations and committed test data; no bundle needed. |
| S09 | One bundle, HAML bootstrap and room picker; test without dates, availability fetch or POST. |
| S10a | One read interaction and timing tests; no submit or admin dependency. |
| S10b | One write interaction layered on existing GET/POST contracts; two-session walkthrough tests conflict handling. |
| S11a | One room command and a second race scenario; no admin presentation work. |
| S11b | One admin tab using already tested services; bundled selector and legacy fields only. |
| S12a | One additive media boundary plus Active Storage setup; fixtures prove reads without an upload endpoint. |
| S12b | One upload endpoint and one changed selector; uses existing media reads and room guard. |
| S13a | Authorized index, detail and filters in the existing workspace; no later form or write route required. |
| S13b | Forms and writes over already tested operations; no new model or concurrency scheme. |
| S14 | README plus rehearsal on disposable targets; no new application behavior to design. |

**Scope closure:** Assignment §§2–8 and §12 map to S02–S13b contracts; §§9–10 to S01a/S01b, S09 and §H; §11 to S07; §§13–14 to §G and S14; §§15–17 to §§A–F and this review. The §C catalog preserves the exact text from assignment §2 and maps each room to its supplied JPEG; S02 bundles those assets and renders the Homepage header, S07 seeds the matching keys, and S09 verifies the finished picker. The only deferred matters are explicit execution/acceptance gates and runtime evidence, not architecture choices. Manual findings outside the agreed demo scope go back to the user rather than being improvised during a stage.
