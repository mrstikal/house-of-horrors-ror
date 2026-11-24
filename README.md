# House of Horrors

A small Rails demo of four deliberately unsettling rooms, one-hour bookings, and a local administration area. The public booking page is a React interaction on a HAML shell; the Administration area is ordinary Rails forms with server-side validation. The demo is local-only and is not a production deployment.

## 1. Selected Theme

House of Horrors is a tongue-in-cheek booking site for four rooms: The Basement Where Mobile Signal Goes to Die, The Bathroom That Judges You, The Kitchen of Leftovers That Watch You Back, and The Attic Full of Clowns Doing Taxes. Guests pick a room, a UTC date and one aligned hourly slot; each slot has a capacity and can fill up. Guests book anonymously. Administrators sign in at `/admin`, manage rooms and images, and list, create, edit and delete reservations.

The five supplied JPEGs in `sources/` drive the visual identity: `house.jpg` is the Homepage header, and `room1.jpg` through `room4.jpg` map to the four rooms in catalog order. The header image is rendered by HAML above the booking component and is visible without JavaScript. The Administration area never shows the house header.

## 2. DECISIONS

### One application, one database, two adapters

One Rails application runs against one database per instance. SQLite is the no-server mode; MySQL 8.4 LTS in Compose is the server mode. Both use the same migrations, models, operations, transactions and tests. There is no deployable production configuration and no deployment target; `config/environments/production.rb` is the stock Rails file and is not configured for this demo.

### Server-authoritative booking

HAML renders the shell and all Administration forms; React controls only the public room, date, availability and booking interaction. Rails controllers authenticate, authorize, allowlist inputs, dispatch operations and render HAML or JSON. Trailblazer operations own booking commands and the availability query. No business rule exists only in JavaScript.

One reservation means one person in one room in one hourly slot. Public guests are anonymous: there are no guest accounts, no ownership links, no customer records and no public read, edit or delete endpoint. Administrators manage all reservations. A reservation cannot be edited or moved after its slot has started, but it can still be viewed and deleted. Refusals use 422 for invalid input, 404 for a missing resource, 409 for a full slot, and 503 when the guarded write cannot acquire the lock.

### Capacity and guarded writes

Room capacity is enforced by a guarded write that takes a row lock, counts committed reservations for the room and slot, excludes the reservation being edited, and writes or refuses inside one transaction on both adapters. A busy database may decline a request, but it cannot overbook. The public JSON API and the Administration writes use the same operations.

### Images

The four room JPEGs and the house header are bundled Propshaft assets, not uploaded blobs. Administrator uploads use Active Storage Disk and are referenced directly from `rooms.image_blob_id`. A room has exactly one image reference, enforced by a database check: either a bundled `image_key` or an uploaded blob. Uploaded files are immutable, reusable and never purged by a room change or room deletion. There is no upload deletion endpoint and no automatic orphan cleanup.

### Administration

`/admin` is the whole Administration entry point, including its login form. The public page and the Administration login share the `Homepage | Admin` navigation; authenticated resource pages use the workspace header with Rooms and Reservations. One successful sign-in unlocks both tabs, and all Administration resource URLs render the same dashboard. Protected resource routes return 403 before record lookup without a valid admin session. Forms use Rails CSRF tokens and strong parameters. The public JSON POST uses the Rails CSRF meta token, same-origin credentials, and JSON headers.

### Deliberately out of scope

No payments, notifications, audit trails, pagination, image transformations or variants, direct uploads, public Active Storage routes, arbitrary durations or party sizes, guest accounts, password recovery, email, HTTPS termination, or production deployment. Authentication is a local demo fixture, not a production identity system.

## 3. Why the Capacity Algorithm Works

Think of a room as having a fixed number of places for each hourly slot. A room with capacity 3 can hold three separate reservations at 01:00-02:00 UTC, three more at 02:00-03:00 UTC, and so on. Availability is simply:

> places left = capacity − confirmed reservations for that room and that hour

### The booking step in plain language

- A guest chooses a room, a UTC date and one hourly slot.
- The system opens a short protected step that only one booking attempt can use at a time.
- Inside that step it counts how many reservations already exist for exactly that room and hour.
- If the count is below the room's capacity, the new reservation is saved as part of the same protected step.
- If the count has reached the capacity, nothing is saved and the guest is told that the slot has just filled up.

The protected step matters because two guests can ask for the last place at almost the same moment. Without it, both could read the same old count, both could decide that one place is left, and both could save a reservation. With it, the second attempt waits, sees the updated count, and is refused. The system can therefore answer "full" or "busy", but it cannot silently overbook.

```text
Guest A ──┐
          ├──> [one booking at a time] ──> count this room + hour
Guest B ──┘                                  │
                                             ├── below capacity ──> save
                                             └── at capacity ─────> refuse
```

### Two special cases

- **Editing an existing reservation:** the reservation being changed is not counted against itself. Otherwise, saving an unchanged booking in a full slot would look like a new booking and be refused. The system counts the other reservations in the slot, adds the edited one back, and checks the result against capacity.
- **Adjacent hours and other rooms:** a full 01:00 slot does not affect 02:00, and a full Basement does not affect the Attic. Capacity is checked for one room and one hourly slot at a time.

### What happens on each database

The same protected count-and-save step is used on SQLite and on MySQL.

- **SQLite:** it allows one writer at a time. A competing attempt waits for its turn; if it cannot get its turn in time, the request is refused as busy rather than forced through.
- **MySQL:** the booking step takes a database row lock inside a transaction. A competing attempt waits for the lock or is refused as busy if the lock cannot be acquired in time.

In both cases, a busy result is safer than an overbooked room. The public booking page and the Administration forms call the same underlying operation, so the rule is identical in both places.

## 4. Technology Stack

- Ruby 3.4.13; Rails 8.1.4.1; Bundler.
- HAML 7.5.2 with `haml-rails` 3.1.0; Propshaft 1.3.2 for the CSS and bundled JPEGs.
- Trailblazer Operation 0.11.1 for booking commands and availability; Active Record 8.1.4.1 for persistence and record-local validations.
- Active Storage with the Disk service and its Marcel dependency for uploaded images; no image-processing service and no variants.
- React 19.3.1 and React DOM 19.3.1, bundled by esbuild 0.28.2 into `app/assets/builds/booking.js`; Node 22.22.2 or another 22.x patch.
- SQLite3 `~> 2.1` for the default mode; `mysql2` `~> 0.5` against MySQL 8.4 LTS in Compose.
- `bcrypt` `~> 3.1` and Rails encrypted cookie sessions for the demo admin account.
- Rails Minitest and `rubocop-rails-omakase` 1.1.0; Vitest 5.1.1, Vite 8.3.8, jsdom 31.0.1, and Testing Library React 16.3.3 / DOM 10.4.1 for the component tests.
- No Turbo, no client router, no separate JavaScript server, and no JavaScript bundling gem.

## 5. Project Setup

### Prerequisites

- Ruby 3.4.13 selected in the shell (`.ruby-version` records it). Check with `ruby -v`.
- Node 22.22.2 or a later 22.x patch (`.node-version` records it). Check with `node -v`.
- Bundler and the gems in `Gemfile.lock`; `bundle check` should succeed after `bundle install`.
- Docker Compose only for the MySQL mode. SQLite needs no server and no Docker.
- A shell where `DATABASE_URL`, `SCHEMA`, `HOH_DB` and `HOH_DB_SUFFIX` are unset for the default examples. `HOH_DB` accepts only `sqlite` or `mysql`; `HOH_DB_SUFFIX` accepts only lowercase letters and digits, at most 20 characters.

### Common dependencies

```sh
bundle install
npm ci
npm run build
```

Run `npm ci && npm run build` again after JavaScript changes; Rails request tests and browser checks need the generated bundle. The bundle is not committed and is produced locally.

### SQLite: no server, no Docker

```sh
bin/rails db:setup
bin/rails server -b 127.0.0.1
```

`db:setup` creates the development and test SQLite files, loads `db/schema.rb` and runs the seeds. Visit `http://127.0.0.1:3000/`.

`db:setup` is for a fresh target. If `storage/development.sqlite3` already exists, do not run `db:setup` against it; use `bin/rails db:migrate`, or choose a new suffix for a fresh demo:

```sh
HOH_DB_SUFFIX=demo1 bin/rails db:setup
HOH_DB_SUFFIX=demo1 bin/rails server -b 127.0.0.1
```

The suffix selects `storage/development_demo1.sqlite3`, `storage/test_demo1.sqlite3`, and the matching upload directory. Pass the same prefix to every command for that target.

### MySQL 8.4 in Docker Compose

```sh
docker compose up -d --wait mysql
HOH_DB=mysql bin/rails db:setup
HOH_DB=mysql bin/rails server -b 127.0.0.1
```

The Compose service listens only on `127.0.0.1:3307`. The password fallback is `hoh-local-mysql`; set `MYSQL_ROOT_PASSWORD` consistently if you change it. `db:setup` creates `house_of_horrors_development`, loads `db/mysql_schema.rb` and runs the seeds. Visit `http://127.0.0.1:3000/`.

For a fresh suffix without touching existing databases:

```sh
docker compose up -d --wait mysql
HOH_DB=mysql HOH_DB_SUFFIX=demo2 bin/rails db:setup
HOH_DB=mysql HOH_DB_SUFFIX=demo2 bin/rails server -b 127.0.0.1
```

Do not run `db:setup` against an existing database; use `HOH_DB=mysql bin/rails db:migrate`. Do not delete the Compose volume to fix a password mismatch; either use the existing password consistently or create a new volume/target with permission.

### Expected URL and demo-only sign-in

- Homepage: `http://127.0.0.1:3000/`
- Administration: `http://127.0.0.1:3000/admin`
- Demo administrator: `admin@example.test`
- Demo password: `house-of-horrors-demo-2026`

These credentials are an intentional public demo fixture, not a secret and not suitable for any real deployment. The seed will not silently reset an existing password or role.

### Seed scenario and UTC dates

Let `D` be the UTC calendar date when `db:setup` or `db:seed` runs. Sample reservations cover `D + 1` through `D + 30`; no calendar date is hardcoded. The deterministic checks use `D + 1` as “tomorrow” and `D + 7` as the “week out” date.

- `D + 1` at `01:00`: Basement 9/10, Kitchen 2/3, Attic 5/6. Basement `02:00` is 3/10 and Basement `03:00` is 0/10.
- `D + 7`: Bathroom `02:00` is empty; Attic `04:00` is empty and the other five Attic hours are 6/6, so the Attic offers only `04:00-05:00 UTC`.
- Selecting tomorrow's Basement `01:00` shows `Only 1 place left!`. The empty Bathroom on `D + 7` at `02:00` has one place because its capacity is one, but it does not show the nearly-full warning.

The seed uses a fixed random seed for sample counts, plus the explicit overrides above. Re-running `db:seed` does not delete existing reservations.

### Tests and lint

Use disposable, unseeded test databases with distinct suffixes. Tests are serial and must not use the development database.

```sh
HOH_DB_SUFFIX=testdocs bin/rails db:test:prepare
HOH_DB_SUFFIX=testdocs bin/rails test

HOH_DB=mysql HOH_DB_SUFFIX=testdocm bin/rails db:test:prepare
HOH_DB=mysql HOH_DB_SUFFIX=testdocm bin/rails test

npm test
npm run build
bin/rails zeitwerk:check
bundle exec rubocop
```

`bin/rails --version` must report `Rails 8.1.4.1`. The Rails suites include the committed-write and concurrency tests; the JavaScript suite renders the React component against a mocked HTTP contract.

### Migration replay

The checked-in schema dumps are `db/schema.rb` for SQLite and `db/mysql_schema.rb` for MySQL. To prove that migrations can build a fresh schema, use new suffixes and alternate schema files that do not exist yet:

```sh
HOH_DB_SUFFIX=replaysqlite SCHEMA="$PWD/tmp/migration_replay_sqlite.rb" bin/rails db:migrate
HOH_DB=mysql HOH_DB_SUFFIX=replaymysql SCHEMA="$PWD/tmp/migration_replay_mysql.rb" bin/rails db:migrate

HOH_DB_SUFFIX=replaysqlite bin/rails db:migrate:status
HOH_DB=mysql HOH_DB_SUFFIX=replaymysql bin/rails db:migrate:status
```

Every migration should report `up`. Confirm that `db/schema.rb` and `db/mysql_schema.rb` are unchanged. Never export `SCHEMA` into a shared shell; set it only on the two replay commands that need it, and use otherwise unused suffixes because the alternate dump is created in `tmp/`.

### Recovery from common setup failures

- **Wrong Ruby or missing `bundle`:** select Ruby 3.4.13 (the version in `.ruby-version`), then run `bundle install`.
- **MySQL is not ready:** run `docker compose ps` and `docker compose up -d --wait mysql`; the service must report healthy on `127.0.0.1:3307`. If the volume was created with another password, use that password consistently or create a new volume/target with permission; do not delete data to fix the mismatch.
- **`db:setup` on an existing database recreates the schema and destroys its rows:** it does not abort merely because the SQLite file or MySQL database exists; `db:schema:load` uses `force: :cascade`. Use `db:migrate` for an existing install, or choose a new suffix and run `db:setup` against that disposable target.
- **Missing `booking.js` or an empty booking area:** run `npm ci && npm run build`.
- **SQLite reports a locked database:** stop another Rails server or writer for the same file; SQLite allows one writer at a time and the configured timeout is five seconds.
- **Invalid mode or suffix:** `HOH_DB` must be `sqlite` or `mysql`; `HOH_DB_SUFFIX` must match `[a-z0-9]{0,20}`.
- **Port already in use:** start Rails with another `-p` port.
- **Pending migrations:** run `bin/rails db:migrate` with the same `HOH_DB` and suffix prefix as the target.

### Reseeding, disposable reset and retention

Safe reseeding for an existing demo:

```sh
bin/rails db:seed
HOH_DB=mysql bin/rails db:seed
```

The seed keeps existing reservations, does not overwrite administrator changes to seed rooms, and skips sample occupancy if canonical capacities have changed. To refresh aged sample data, prefer a new suffix and `db:setup`.

An explicitly destructive reset exists only for a verified disposable target:

```sh
HOH_DB_SUFFIX=<verified-disposable-suffix> SKIP_TEST_DATABASE=1 bin/rails db:reset
HOH_DB=mysql HOH_DB_SUFFIX=<verified-disposable-suffix> SKIP_TEST_DATABASE=1 bin/rails db:reset
```

`db:reset` destroys that development database. Verify the suffix and obtain permission first; it must not be pointed at data you want to keep. It does not remove uploaded bytes or the Docker volume.

### Upload limits and retained images

Administrators can upload PNG or JPEG files of 1 byte through 2 MiB. The type is detected from the file bytes, not from the caller's filename or declared type; SVG and oversized files are refused with 422. Successful uploads receive a generated `room-<uuid>.png|jpg` name and can be reused across rooms. Uploads are stored by Active Storage Disk under the following roots. The `<suffix>` placeholder includes the leading underscore; for example, `HOH_DB_SUFFIX=demo1` gives `storage/room_images/development-sqlite_demo1`.

- SQLite development: `storage/room_images/development-sqlite<suffix>`
- MySQL development: `storage/room_images/development-mysql<suffix>`
- SQLite test: `storage/room_images/test-sqlite<suffix>`
- MySQL test: `storage/room_images/test-mysql<suffix>`

Uploaded bytes persist until explicitly deleted. A room change or room deletion never purges an old blob, and there is no upload deletion endpoint or automatic orphan cleanup; an unassigned upload remains in the room image selector. `db:reset` does not remove these files. Uploaded images are served only through `/room_photos/:id` for catalogue blobs referenced by a room; bundled JPEGs are served by Propshaft. There are no variants, direct uploads, or public Active Storage routes.

### Local-only authentication limitations

The demo admin account is created by the seed with public, demo-only credentials. There is no signup, password recovery, email delivery, account ownership, or guest account. Only the `admin` role can use `/admin`; authenticating a non-admin does not grant that role. Admin sessions expire after eight hours, login attempts are rate-limited, and logout ends the session. The application binds to loopback and has no HTTPS or deployment target; the stock `config/environments/production.rb` is not configured for this demo. Do not expose it on a public interface or reuse the demo credentials for anything real.

## 6. Potential Future Extensions: Redis, RabbitMQ, and Background Workers

Given more development time, I would extend the application with **Redis, RabbitMQ, and Ruby-based background workers** to demonstrate asynchronous processing, temporary reservation management, and event-driven architecture.

**1. Redis — Temporary Reservation Holds and Caching**

- Introduce temporary reservation holds with a configurable expiration time (e.g., 5 minutes), allowing guests to complete their booking before the reserved capacity is released.
- Cache room availability to reduce repeated database queries.
- Use Redis TTL (Time to Live) to automatically expire temporary data.
- Keep MySQL as the authoritative source of reservation state and capacity enforcement.

**Benefits:** Faster availability lookups, efficient management of short-lived data, and better scalability under heavy booking traffic.

**2. RabbitMQ — Event-Driven Messaging**

- Publish events such as `reservation.created`, `reservation.confirmed`, and `reservation.expired`.
- Decouple reservation processing from secondary operations such as notifications, audit logging, and analytics.
- Use durable queues, acknowledgements, and retry/dead-letter mechanisms to handle processing failures.

**Benefits:** Improved reliability, independent processing of asynchronous tasks, and easier integration with additional services.

**3. Ruby Background Workers — Asynchronous Processing**

- Implement background workers in Ruby.
- Consume RabbitMQ messages and perform tasks such as sending booking confirmations, recording audit events, and processing reservation expirations.
- Use a suitable Ruby RabbitMQ client or worker framework, such as Bunny or Sneakers.
- Ensure that expired holds are excluded from availability calculations immediately, even if background processing is delayed.

**Benefits:** Non-blocking HTTP requests, reliable background processing, and a consistent Ruby-based technology stack.

**Architecture and Reliability**

The core capacity validation would remain synchronous and transaction-safe in Rails/Trailblazer, backed by MySQL. Redis and RabbitMQ would support performance and asynchronous workflows rather than becoming the authoritative source of booking capacity.

For reliable event publishing, a transactional outbox pattern could be introduced to prevent events from being lost between database commits and message publication.

These extensions would be optional and deployed through Docker Compose, preserving the application's lightweight standalone demonstration mode.
