# Planning Assignment: House of Horrors — Ruby on Rails Reservation Demo

## 1. Your Role and Objective

You are a senior Ruby on Rails software architect and technical planning agent.

Your task is to produce a **detailed, implementation-ready development plan** for a small demonstration application called **House of Horrors**.

The application allows guests to reserve one-hour experiences in a fictional haunted house containing four absurdly humorous rooms.

The primary objective is to demonstrate practical knowledge of:

- Ruby on Rails 8.1.4.1 and its ecosystem.
- Active Record models, validations, and associations.
- Controllers, routing, and HAML templates.
- Trailblazer operations for business logic.
- React integration with Rails.
- Reservation scheduling and capacity management.
- Authentication and authorization.
- Database migrations, seeds, and automated testing.
- Maintainable application architecture.

This is a **small portfolio/demo application**, not a production booking platform.

Prioritize correctness, clarity, ease of setup, and idiomatic Rails development over unnecessary complexity.

**Your deliverable is an implementation plan, not application code.**

The plan will be executed by a coding agent with relatively limited reasoning capabilities. Therefore, each implementation stage must have an unambiguous scope, explicit instructions, dependencies, and verifiable acceptance criteria.

---

## 2. Application Concept

The House of Horrors offers four themed experiences.

Each room has:

- Name
- Description
- Maximum simultaneous occupancy
- Image

All four rooms must be created automatically from seed data.

### Room 1: The Basement Where Mobile Signal Goes to Die

**Description:**

> You walk down the stairs and your phone gives up. First it loses 5G, then 4G, then the will to live. In the dark, something is still buffering. It has been buffering since 2009.

**Maximum capacity:** 10 people.

### Room 2: The Bathroom That Judges You

**Description:**

> You look into the mirror. The mirror looks back. It does not scream. It sighs, very slowly, and whispers: So... this is what we are wearing today?

**Maximum capacity:** 1 person.

### Room 3: The Kitchen of Leftovers That Watch You Back

**Description:**

> You open the fridge. All the boxes turn to look at you. One of them is from Christmas. It remembers everything. It knows what you did with the potato salad.

**Maximum capacity:** 3 people.

### Room 4: The Attic Full of Clowns Doing Taxes

**Description:**

> You expect screaming. Instead you hear a calculator. Twelve clowns sit at a tiny table, doing taxes. One looks up and says: You did not keep your receipts, did you?

**Maximum capacity:** 6 people.

The original names and descriptions must be preserved exactly.

The visual presentation should reflect the absurd horror theme, but sophisticated design is not required.

---

## 3. Domain Models and Associations

The application requires three principal models.

### 3.1 Room

Suggested attributes:

- `id`
- `name`
- `description`
- `capacity`
- `image`
- Rails timestamps

Associations:

- A room has many reservations.
- Reservations belong to a room.

Use appropriate validations for mandatory fields, capacity, name uniqueness where useful, and image references.

The administrator must be able to create, view, edit, and delete rooms.

Room deletion must be handled safely when associated reservations exist.

### 3.2 Reservation

Required attributes:

- `id`
- `room_id`
- `start_datetime`
- `end_datetime`
- Rails timestamps

A reservation represents **one person occupying one room for one hour**.

Therefore, the number of overlapping reservations represents the number of occupants.

Do not introduce party-size booking unless there is a compelling architectural reason. The default implementation should use one reservation per person.

Associations:

- A reservation belongs to a room.
- Define a minimal and consistent relationship to the User model if needed.

Required operations:

- Index
- Show
- New/Create
- Edit/Update
- Delete

A reservation must always reference a valid room.

### 3.3 User

Required roles:

- `guest`
- `admin`

Implement a simple, secure authentication mechanism suitable for Rails 8.1.

Requirements:

- Only authenticated administrators may access administration functionality.
- Guests can make reservations from the public homepage.
- Do not force unnecessary registration or login steps on public guests.
- Administrator credentials must be provided through seed data.
- Authorization must be enforced server-side.

Decide how guest reservations relate to User records without introducing an unnecessarily complex registration system.

Document the chosen approach and its trade-offs.

---

## 4. Reservation Scheduling

All rooms have identical operating hours.

**Opening hours: 01:00–07:00, every day.**

Each reservation lasts exactly 60 minutes.

Available reservation slots are:

| Start | End |
|---|---|
| 01:00 | 02:00 |
| 02:00 | 03:00 |
| 03:00 | 04:00 |
| 04:00 | 05:00 |
| 05:00 | 06:00 |
| 06:00 | 07:00 |

Requirements:

1. Users cannot create reservations outside operating hours.
2. Reservations must last exactly one hour.
3. Reservations must use the predefined hourly slots.
4. Users cannot reserve dates in the past.
5. The public interface must only offer future, bookable slots.
6. Fully booked slots must not be presented as available.
7. Availability must update when the selected room or date changes.
8. All time calculations must use a consistent configured application timezone.

Consider daylight-saving transitions and avoid ambiguous or invalid datetime handling.

---

## 5. Core Business Logic — Capacity Validation

**This is the most important functional requirement of the entire application.**

A reservation may only be saved if the number of simultaneous reservations for the selected room never exceeds that room's maximum capacity.

For any room and any instant within operating hours:

`active_reservation_count <= room.capacity`

For example:

- Room 1 allows a maximum of 10 simultaneous reservations.
- Room 2 allows a maximum of 1.
- Room 3 allows a maximum of 3.
- Room 4 allows a maximum of 6.

If Room 3 already has three reservations from 02:00 to 03:00, a fourth reservation for the same interval must be rejected.

Reservations for adjacent slots must be treated independently.

For example, 02:00–03:00 and 03:00–04:00 do not overlap.

### Required implementation properties

The solution must:

- Validate capacity on reservation creation.
- Validate capacity on reservation updates.
- Exclude the reservation being edited from its own occupancy calculation.
- Correctly handle room changes during reservation updates.
- Reject invalid, past, or out-of-hours intervals.
- Keep capacity enforcement entirely on the server.
- Never rely on frontend availability checks as the final authority.
- Return meaningful validation errors.
- Prevent overbooking under simultaneous requests.

Use database transactions and appropriate locking where necessary.

**Trailblazer must be used meaningfully for the reservation business logic.**

Consider Trailblazer operations for:

- Creating reservations.
- Updating reservations.
- Checking availability/capacity.

Avoid unnecessary abstraction. Explain which responsibilities belong in Trailblazer operations, Active Record models, or other Rails components.

### Concurrency requirement

Two users may attempt to reserve the last remaining place simultaneously.

The implementation must prevent both requests from succeeding if doing so would exceed capacity.

Explain the locking or transactional strategy and test it.

The implementation must remain correct even if an availability check performed earlier in the React frontend becomes stale.

### Algorithm documentation

The README must explain in **2–3 sentences** why the selected capacity validation algorithm works.

The implementation plan must provide a more detailed explanation, including concurrency considerations.

---

## 6. Application Interface

The application must have only **two principal user-facing pages**:

1. Homepage
2. Administration

Additional forms, dialogs, tabs, components, and API endpoints are allowed, but avoid introducing unnecessary full-page routes.

A shared navigation menu must appear on both pages:

`Homepage | Admin`

Use Rails controllers, HAML templates, and React components together in a coherent architecture.

### 6.1 Homepage

The homepage is the main public reservation interface.

It must include:

**Room selection**

- Dropdown or comparable selector containing all available rooms.
- Selecting a different room immediately updates its image and description.
- The selected room's maximum capacity is visible.

**Date and time selection**

- Select a reservation date.
- Select an available one-hour slot.
- Only available slots can be selected.
- Availability is obtained from Rails backend logic.
- Changing the room or date refreshes the available slots.

**Capacity information**

Show a visible warning when a slot is nearly fully booked.

Examples:

- "Only 1 place left!"
- "Almost fully booked!"

Define a simple, consistent rule for identifying near-capacity situations.

The rule should work sensibly for rooms with different capacities, including the one-person bathroom.

**Reservation creation**

- Allow users to submit a reservation.
- Display success or error feedback without unnecessary full-page navigation.
- Handle conflicts when the last place has been booked by another user.
- Refresh availability after successful or unsuccessful booking attempts.

**Presentation**

- Display an additional House of Horrors image or illustration.
- Keep the layout functional and responsive.
- Use humorous room descriptions as the primary thematic content.

### 6.2 Administration

The administration page must require administrator authentication.

Its main content should consist of two tabs.

**Tab 1: Rooms**

Support:

- Room list
- Room details
- Create room
- Edit room
- Delete room
- Change room image
- View associated reservations where useful

**Tab 2: Reservations**

Support:

- Reservation list
- Reservation details
- Create reservation
- Edit reservation
- Delete reservation
- Filter by room and/or date where useful

All administrative reservation changes must use the same capacity validation rules as public bookings.

Do not duplicate reservation business logic in controllers.

A simple tabbed interface is sufficient. Forms can be displayed inline or in modal dialogs.

Authentication should not require a third principal application page if a login form can be integrated into the protected Admin route.

### 6.3 Rails Controllers and Routes

Provide the required Rails controller actions and appropriate routing for Room and Reservation resources.

At minimum, support index, show, new/create operations for both resources, and edit/update for reservations.

Additional room update/delete actions are necessary for administrative room management.

The external user interface may consist of only the two principal pages even if more JSON endpoints or controller actions exist internally.

Clearly separate:

- Page rendering
- Data retrieval
- Business operations
- Authorization

---

## 7. Frontend Architecture

React is mandatory.

HAML templates are also mandatory.

Design a simple integration where:

- Rails renders the principal pages using HAML.
- React powers the interactive interface.
- Rails provides backend JSON endpoints as needed.
- React does not contain authoritative reservation business logic.

Prefer a small, integrated Rails application over separate frontend and backend repositories.

Recommend a practical bundling solution compatible with Rails 8.1.4.1.

Examples of suitable approaches include `jsbundling-rails` with esbuild or another justified lightweight integration.

Do not introduce an independent Next.js application or unnecessary frontend infrastructure.

Explain:

- How React components are mounted in HAML templates.
- How initial data reaches React.
- How React communicates with Rails.
- How Rails CSRF protection is respected.
- How server-side validation errors are displayed.

---

## 8. Styling and Image Management

### 8.1 CSS

Use CSS in separate files.

Avoid inline styling and unnecessary CSS frameworks.

The interface should look clean, slightly humorous, and appropriate for a fictional haunted house.

Sophisticated design, animations, or large UI component libraries are not required.

### 8.2 Images

Provide images for:

- House of Horrors
- The Basement Where Wi-Fi Goes to Die
- The Bathroom That Judges You
- The Kitchen of Leftovers That Watch You Back
- The Attic Full of Clowns Doing Taxes

Bundle the initial images with the application.

Organize all House of Horrors images in one clearly identified logical asset collection or directory.

The administrator must be able to:

1. Upload an image for a newly created room.
2. Select an image from existing available images.
3. Replace an existing room's image.

Images should be reusable between rooms.

Use an appropriate Rails image-handling solution.

Consider Active Storage where justified, but account for the requirement to have a usable demonstration mode without a MySQL server.

Explain how bundled images, uploaded images, and image references will be stored and managed.

Include basic file-type, size, and upload security validation.

Image generation through external AI services is **not required**.

---

## 9. Required Technology Stack

Mandatory:

| Technology | Requirement |
|---|---|
| Ruby on Rails | Exactly 8.1.4.1 |
| Ruby | Compatible maintained version |
| Templates | HAML |
| Frontend | React |
| Business logic | Trailblazer |
| Linting | RuboCop |
| Persistent database | MySQL |
| Containerization | Docker for MySQL |
| Seed data | `db/seeds.rb` |
| Styling | Separate CSS files |
| Testing | Automated tests |

You may recommend additional Rails ecosystem libraries where they provide practical value.

Potential examples:

- A compatible authentication solution or Rails authentication generator
- Active Storage
- RSpec or Rails Minitest
- FactoryBot
- Shoulda Matchers
- SimpleCov
- Pagination where genuinely useful

Do not add libraries merely to demonstrate their existence.

For every important additional dependency, explain its purpose.

Verify compatibility with Rails 8.1.4.1, especially for Trailblazer and HAML integration.

Use idiomatic Rails conventions wherever possible.

---

## 10. Database and Demonstration Modes

The project must support two practical startup scenarios.

### Mode A: MySQL with Docker

Use a MySQL database running in a Docker container.

Requirements:

- Docker Compose configuration.
- Rails application connects to MySQL.
- Migrations create the required schema.
- `rails db:setup` initializes and seeds the application.
- The application can be used immediately afterward.
- Reservation and administration changes persist normally.

Only MySQL needs to run inside Docker; containerizing the Rails application itself is optional.

### Mode B: Demo Without a MySQL Server

The user must be able to try the demonstration without starting Docker or configuring an external database server.

The original requirement describes this as a "seed-only, no-database mode."

However, standard Active Record persistence and `rails db:setup` require a database backend.

**You must explicitly resolve this architectural issue in the plan.**

Evaluate these approaches:

- A lightweight local SQLite database populated by the same seed data, requiring no external database service.
- A genuinely database-free, seed-backed in-memory demonstration mode.

Explain their trade-offs, including:

- Implementation complexity
- Compatibility with Active Record and Trailblazer
- Full CRUD support
- Persistence behavior
- Capacity validation
- Concurrency guarantees
- Setup complexity

Prefer the simplest technically coherent solution, but do not silently describe SQLite as literally database-free.

If a genuine in-memory mode is implemented, document its limitations and clarify how its initialization differs from `rails db:setup`.

The main requirement is a simple, runnable demonstration with minimal setup effort.

Avoid maintaining two entirely separate application implementations.

---

## 11. Dynamic Seed Data

`db/seeds.rb` is an essential project component.

After database initialization, the demonstration must immediately contain meaningful example data.

### 11.1 Rooms

Create the four specified rooms with their exact names, descriptions, capacities, and bundled images.

### 11.2 Administrator

Create one administrator account.

Use simple, well-documented demonstration credentials.

The README must provide these credentials in section 5.

Clearly indicate that they are demonstration-only credentials.

### 11.3 Reservations

Generate reservations dynamically relative to the date when seeding runs.

**Do not hardcode calendar dates.**

Requirements:

- The earliest seeded reservation date is tomorrow (`today + 1 day`).
- Populate a rolling 30-day period beginning tomorrow.
- Generate randomized reservation occupancy values.
- Include all four rooms.
- Respect operating hours and capacity limits.
- Avoid invalid or overlapping capacity violations.
- Include fully booked slots.
- Include partially occupied slots.
- Include nearly full slots.
- Include completely available slots.

Use a deterministic random seed where beneficial for reproducible tests and debugging.

The seeded data must remain useful regardless of when the project is downloaded and initialized.

### 11.4 Special Scenario for Room 4

For **The Attic Full of Clowns Doing Taxes**, choose one date within the generated period.

On that date:

- Five of the six hourly slots must be completely booked.
- Exactly one entire hourly slot must remain available.
- The available hour must be clearly identifiable in the public booking interface.

This scenario is mandatory.

Additionally, create suitable near-capacity examples, such as:

- Room 1: 9 of 10 places occupied.
- Room 3: 2 of 3 places occupied.
- Room 4: 5 of 6 places occupied.

These examples should demonstrate the capacity warning system.

### 11.5 Idempotency

Design seeding to avoid accidental duplication of rooms or administrators.

Explain the intended behavior when seeds are run repeatedly, including how generated reservations are refreshed or preserved.

The seed procedure should be reliable for both initial setup and demonstration resets.

---

## 12. Validations

Implement meaningful validations for required attributes.

### Room

Examples:

- Name must be present.
- Description must be present.
- Capacity must be a positive integer.
- Image must be a valid reference or supported upload.
- Name should be unique where appropriate.

### Reservation

Examples:

- Room must exist.
- Start and end datetimes must be present.
- End must be after start.
- Duration must equal exactly 60 minutes.
- Reservation must fit within operating hours.
- Reservation must use an allowed hourly slot.
- Reservation must not be in the past.
- Room capacity must never be exceeded.

### User

Examples:

- Valid role.
- Valid administrator credentials.
- Secure password storage.
- Necessary uniqueness constraints.

Validate on the server, regardless of frontend behavior.

---

## 13. Automated Tests

Testing is mandatory, especially for the capacity algorithm.

Choose a suitable test framework and document the decision.

### 13.1 Model Tests

Test:

- Required fields.
- Valid and invalid capacities.
- Associations.
- Invalid reservation durations.
- Invalid room references.
- Operating hour restrictions.
- Past reservations.

### 13.2 Capacity Algorithm Tests

At minimum, cover:

1. First reservation in an empty slot succeeds.
2. Reservations succeed until capacity is reached.
3. The reservation exceeding capacity fails.
4. A one-person room rejects a second reservation for the same slot.
5. Adjacent one-hour slots are not considered overlapping.
6. Editing a reservation without changing its slot does not count itself twice.
7. Editing a reservation to a full slot fails.
8. Moving a reservation between rooms respects the target capacity.
9. Simultaneous attempts to claim the last available place cannot cause overbooking.
10. The system handles boundary times correctly.

### 13.3 Request and Authorization Tests

Test:

- Public homepage availability retrieval.
- Successful reservation creation.
- Failed reservation creation due to capacity.
- Unauthorized administration access.
- Authorized administrator access.
- Room CRUD.
- Reservation CRUD.

### 13.4 Seed Tests

Verify:

- Four default rooms exist.
- Their capacities are correct.
- An administrator exists.
- Reservations begin tomorrow.
- Data covers the intended rolling period.
- No seeded slot exceeds capacity.
- Room 4 has the required special date with exactly one free hour.
- Near-capacity scenarios are present.

### 13.5 Frontend Tests

Include only lightweight tests needed to establish that:

- Room selection updates the image and description.
- Date changes update available slots.
- Unavailable slots cannot be submitted through the normal UI.
- Capacity warnings appear correctly.
- Reservation errors are displayed.

Keep the test suite proportional to the small demo.

---

## 14. README Requirements

Create a clear `README.md` with the following numbered sections.

### 1. Selected Theme

Briefly introduce House of Horrors and its reservation system.

### 2. DECISIONS

Document the important architectural decisions and explain why they were made.

Include at least:

- Model structure and associations.
- Reservation representation.
- Placement of business logic.
- Use of Trailblazer.
- React and HAML integration.
- Database strategy.
- Authentication and authorization.
- Image management.

### 3. Why the Capacity Algorithm Works

Explain in **2–3 concise sentences** why the reservation capacity algorithm correctly prevents overbooking.

Mention concurrency protection where relevant.

### 4. Technology Stack

Briefly list the technologies used and their responsibilities.

### 5. Project Setup

Provide clear instructions for:

**A. MySQL / Docker setup**

- Prerequisites
- Environment configuration
- Starting MySQL
- Installing dependencies
- Running migrations and seeds
- Starting Rails
- Accessing the application

**B. Demo setup without MySQL**

- Prerequisites
- Minimal initialization procedure
- Loading demonstration data
- Starting the application
- Persistence limitations, if any

Also include:

- Demonstration administrator username/email and password.
- Commands for running tests.
- Commands for running RuboCop.
- Instructions for resetting/recreating seed data.

The README should be concise but complete enough for a developer unfamiliar with the repository to start the demo.

---

## 15. Architectural Guidelines

Follow these principles:

**Keep Rails idiomatic.**

Use Rails conventions for models, controllers, migrations, routing, and validation.

**Keep controllers thin.**

Do not implement the reservation algorithm directly in controllers.

**Use Trailblazer purposefully.**

Place the booking workflow and its capacity-related business decisions in appropriate Trailblazer operations or explicitly justified supporting components.

**Avoid duplicating business rules.**

Public booking and administrative booking updates should use the same authoritative logic.

**React is a presentation layer.**

It manages interaction and state but does not decide whether a reservation is valid.

**Keep the domain model small.**

Do not introduce speculative models for payments, tickets, notifications, pricing, customer accounts, or future extensions.

**Avoid overengineering.**

Do not introduce microservices, event buses, CQRS, event sourcing, or unnecessary design patterns.

**Prefer verifiable correctness.**

The capacity algorithm and concurrency behavior are more important than decorative UI features.

---

## 16. Expected Planning Deliverable

Produce a complete implementation plan in English.

Organize the response into the following sections.

### A. Architecture Overview

Describe:

- Selected architecture.
- Major components.
- Data flow between React, Rails, Trailblazer, and database.
- Responsibilities of each layer.

### B. Technology Decisions

List mandatory and additional technologies.

Explain important choices and compatibility considerations.

### C. Data Model

Provide:

- Models and attributes.
- Associations.
- Validations.
- Relevant database indexes.
- Foreign key constraints.
- Recommended migration structure.

### D. Reservation Algorithm

Describe in detail:

- Slot generation.
- Availability calculation.
- Capacity validation.
- Reservation creation.
- Reservation updates.
- Concurrency protection.
- Error handling.

Include pseudocode if it clarifies the logic.

### E. Project Structure

Propose a practical Rails directory structure identifying where to place:

- Models
- Controllers
- Trailblazer operations
- HAML templates
- React components
- CSS
- Images
- Tests
- Seeds
- Docker configuration

Avoid unnecessary directory nesting.

### F. Implementation Stages

Divide implementation into small, sequential, independently verifiable stages.

For every stage provide:

1. **Stage ID and title**
2. **Objective**
3. **Prerequisites**
4. **Files/components to create or modify**
5. **Detailed implementation instructions**
6. **Tests and validation steps**
7. **Acceptance criteria**
8. **Explicit completion boundary**

Each stage should be small enough for a relatively simple coding agent to implement without making major architectural decisions.

Avoid vague steps such as "implement booking functionality" or "add frontend."

Instead, specify the exact expected behavior, interfaces, validation rules, and files or components.

Distribute work reasonably evenly across stages, without creating dozens of trivial tasks.

### G. Test Strategy

Describe the test suites and their relationship to implementation stages.

Pay particular attention to the overbooking and concurrency scenarios.

### H. Setup and Seed Strategy

Explain both supported startup modes and provide the dynamic seed algorithm.

### I. Final Acceptance Checklist

Provide an actionable checklist verifying that the entire application satisfies the requirements.

---

## 17. Planning Constraints

Follow these rules when producing the plan:

1. **Do not implement the application yet.** Produce only the plan.
2. All requirements in this assignment are mandatory unless explicitly described as optional.
3. If a requirement is ambiguous or technically inconsistent, explain the problem and recommend the simplest coherent solution.
4. Clearly distinguish mandatory functionality from optional improvements.
5. Do not expand the project into a production-grade reservation platform.
6. Do not replace React with Hotwire or HAML with ERB.
7. Do not omit Trailblazer.
8. Do not weaken server-side capacity validation to simplify implementation.
9. Do not sacrifice concurrency correctness for a simpler frontend.
10. Do not silently change the requested Rails version.
11. Prefer existing Rails capabilities over additional dependencies where appropriate.
12. Keep the implementation plan detailed enough to serve as the primary instruction document for an autonomous coding agent.
13. Ensure each implementation stage can be tested and reviewed before proceeding to the next stage.

## Final Priority

The most important success criterion is a **fully functional, immediately testable Rails reservation demo with a demonstrably correct, concurrency-safe capacity validation algorithm**.

The second priority is showcasing sensible, maintainable integration of Rails, Trailblazer, HAML, React, and the broader Rails ecosystem.

The third priority is ease of setup, understandable code, and a clean but minimal user interface.

**Favor a small, complete, well-tested application over an ambitious architecture with unnecessary complexity.**