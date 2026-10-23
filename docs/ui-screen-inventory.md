# UI Screen Inventory

## Where the information comes from

- **AppExchange listing.** Captured with REA. The screenshots are in `docs/evidence/`:
  - `appexchange-overview.png`
  - `appexchange-specs.png`
  - `appexchange-resources.png`
  - `appexchange-support.png`
- **Product screenshots.** The listing carousel shows three thumbnails, "Classify", "Distribute" and "Manage". REA captured them only at thumbnail size, so this inventory does not use them as a source.
- **Reference screen structure.** This comes from the vendor's help centre text (H/…). We copied no images.
- **Confidence.** Reference screens are *partially verified*: they are documented but were not observed in a running org.

## Reference app navigation

From H/installation/whats-in-the-package: "The Distribution Engine app is split into a total of 9 tabs".
The listing reports 9 custom tabs, 1 app and 3 global Lightning components, which matches.

| # | Reference tab | Purpose (documented) | Our screen |
|---|---|---|---|
| 1 | Distribution Console | Application Monitoring, Today's Distributions, Sources, Availability Calendar | **Distribution Console** tab, which hosts the `deConsole` LWC |
| 2 | Distribution Classifier / Record Classification | Maps/Territories, Lead Matching, Auto Conversion, Stamp Groups, Delay Filters, Backfill | **Distribution Classifier** tab (`deClassifier`) |
| 3 | Distribution Teams | Team list, plus a team workspace with a left navigation | **Distribution Teams** tab (`deTeams`) |
| 4 | Distribution Tags | Tag collections, tags, tag assignment | **Distribution Tags** tab (`deTags`) |
| 5 | Distribution Sync | Object Sync actions | **Distribution Sync** tab (`deObjectSync`) |
| 6 | Distribution Availability | Out of Office, Regional Holidays, Regions, Shifts | **Distribution Availability** tab (`deAvailability`) |
| 7 | Distribution Logs | Distribution, classifier, sync, scheduler and archive logs | **Distribution Logs** tab (`deLogs`) |
| 8 | Distribution Analytics | Charts and filters | **Distribution Analytics** tab (`deAnalytics`) |
| 9 | Distribution Settings | Settings, Advanced, Trigger settings, Export/Import | **Distribution Settings** tab (`deSettings`) |
| — | Widget (utility bar) | Toggle, Get Next (Pull), Assigned to me, missed SLAs, toasts | `deWidget`, a global component in the utility bar |
| — | Record Detail component | History, Test, Assign (manual), Reject | `deRecordDetail`, a global component on record pages |
| — | Assignment Simulator | Simulation for a record | `deSimulator`, a global component used in Console → Simulator and on record pages |

## Screen-by-screen

### S1 Distribution Console (`deConsole`)

A tabset with four sub-tabs.

- **Application Monitoring**
  - Status cards for the Scheduler, Health Checker, Classifier and SLA Monitor. Each card shows Running, Not Running or Errored, the time of the last run, and errors in the last 24 hours.
  - Actions: **Start Scheduler**, **Stop Scheduler** (admins only) and **Run Health Check Now**.
- **Today's Distributions**
  - A datatable with one row per team: Team, Object, Distributions, SLA Alerts, Reassignments, Rejections, Errors, and Available (x of y).
  - Clicking a count opens Distribution Logs filtered to that team and status.
- **Sources**
  - Columns: Team, Order, Distributor, Type, Object, Source, Waiting, On Hold.
  - Row actions: **Test** (opens the simulator for the first waiting record), **Recent** (the logs) and **Preview** (the first 20 waiting records).
- **Simulator** (`deSimulator`)
  - Inputs: Record Id; Simulate At (date/time); checkboxes for Ignore Caps, Include Inactive and Stop on Success.
  - Action: **Run Simulation**.
  - Output: a tree of results by team and distributor, each step marked PASS or FAIL. Expanding a node shows the condition results and member exclusion reasons.

### S2 Distribution Teams (`deTeams`)

**Team list**

- Columns: Order, Name, Object, Type, Active, Distributors, Members, Available now.
- Buttons: **New Team**, **New Queue-to-Queue Team**, **Reorder** (arrow buttons, then **Save Order**), **Distribution Viewer**.
- Row actions: Open, Activate or Deactivate, Clone, Delete (with confirmation).

**Team workspace**

A vertical navigation, mirroring the documented left navigation:

- **Summary.** Key settings, member and distributor counts, and today's distributions.
- **Team Members**
  - Datatable columns: Member, Type, Active, Weight, Shift, Tags, Online, Available now (with reason), Today, Dynamic.
  - Actions: **Add Members** (multi-select user or queue picker), Activate/Deactivate, Remove, Toggle online (manager override).
- **Distributors**
  - An ordered list showing Type and Method badges.
  - Actions: **New Distributor**, Edit, Clone, Activate/Deactivate, Move up/down, Delete, **Test**.
  - The distributor editor has the following sections:
    1. **Details:** Name, Description, Type, Order.
    2. **Method:** Method, plus the fields for the chosen method:
       - Sticky
       - Lookup (to object, record field, target field, where-conditions, assign to, tie-breaker)
       - Related (related object, otherwise use)
       - Dynamic owner field
       - Pull count
       - Default owner
    3. **Source:** Queue / User / Field Value / Any, with a picker or the field and values.
    4. **Filters:** the `deConditionBuilder` with logic, plus the sort order builder (field and direction rows).
    5. **Team Members:** All or Selected, the member filter builder (Tag, Dynamic Tag, Territory, Stamp), and the exclude field.
    6. **Availability:** Assign if unavailable; Assign if offline.
    7. **Weighting and Caps:** weighting on or off; Respect team caps; distributor cap rows.
    8. **Post Assignment:** field updates; email; in-app notification.
    9. **SLA and Reassign:** SLAs enabled, Auto reassign, Reassign from SLA, Reassign to, field updates, toggle user off, remove sticky.
    10. **Rejection:** enabled, reject to, field updates, replace option, treat manual as rejection.
- **Weighting and Caps.** Team caps (up to 3 period rows plus caps by tag), weighting mode, and individual weight sliders (0.25–4, showing each member's percentage share).
- **Distribution Hours.** Team hours (pick a Shift), member hours (a Shift per member) and Holiday Region.
- **Tracking and SLAs.** SLA hours setting; checkpoint rows (Checkpoint, Alert Type, Minutes or Field, SLA-missed-if conditions, Stamp, Notify); action tracking settings.
- **Assignment Rejection.** Limit (Unlimited / Manager only / Limited n per day).
- **Post Assignment.** Object Sync on or off.
- **Team Settings.**
  - Object (read-only once the team is saved).
  - Assignment field (locked while distributors exist).
  - Round robin level, load balancing level and type, balance by and field, active status field and values.
  - Team filters and logic.
  - Managers.
  - Dynamic members (conditions on User, plus **Sync Members Now**).
- **History.** Field history for the team and its distributors.

**Validations shown inline** (see W1 to W3 in `behavior-specification.md`). **Save** and **Cancel** appear on every editor. Cancel discards unsaved edits and restores the last saved values.

**Distribution Viewer.** A read-only map: Source (queue, user or field value) → Teams → Distributors, with each distributor's method, filters and member counts.

### S3 Distribution Availability (`deAvailability`)

- **Out of Office.** List with filters for user and date range. Actions: New, Edit, Delete. Managers can pick any user; other users only themselves.
- **Regional Holidays.** List and editor: Name, Region, All day, Starts, Ends, Timezone.
- **Regions.** The distinct regions in use, and the teams using each one.
- **Shifts.** A list, and an editor with a timezone, seven day rows with up to three blocks each (start, end, +1), **Copy to all** and **Add Shift**.
- **Availability Calendar.** A month grid with per-day counts of members working, on OOO and on holiday. Filter by team.
- **Team Roster.** Online toggles for every member, used for manager override, plus "toggled off for X minutes".

### S4 Distribution Tags (`deTags`)

- **Collections.** The distinct collection names.
- **Tags.** Tags within a collection. Action: **Add Tags**.
- **Tag Assignment.** A user list showing tags as pills. Actions: Assign Tags, Remove, and **Clone tags** from another user.

### S5 Distribution Classifier (`deClassifier`)

- **Territories.**
  - A list grouped by Map, showing Order, Status (Draft or Active), Countries, States and Postal codes.
  - Editor fields: lists, extra conditions and stamp field.
  - Actions: **Activate Map**, **Reorder**, **Import** (paste lines of `Territory,Country,State,PostalCodes`).
- **Lead Matching.** Rules per match type, with domain, company name, email and custom field options; personal domains; match filters; tie-breaker.
- **Auto Conversion.** Ordered rules; the default rule is pinned last.
- **Stamp Groups.** Groups, and stamps with their conditions in order.
- **Backfill.** A wizard:
  1. Object.
  2. Classification types (Territory, Stamps, Matching, Conversion).
  3. Record filter.
  4. Summary.
  5. Run.

  When it finishes, a run log is written and an optional completion email is sent.

### S6 Distribution Sync (`deObjectSync`)

- A list of sync actions with an editor: Distribution Object, Related Object, Lookup Field, filters, Active.

### S7 Distribution Logs (`deLogs`)

- **Distribution Logs.** Filters: date range, status, object, team, distributor, assignee and quick search. Shows the top 500 results.
  - Columns: Assignment Date, Record, Status, Object, Team, Distributor, Method (with a sticky marker), Assignee, Speed to Assign, SLA, Time to Action.
  - Actions: **Retry**, **Retry all (Error / On Hold)** and **Reject**.
  - A side panel shows the decision trace and the current owner.
- **Engine Runs.** The run logs, filterable by process.

### S8 Distribution Analytics (`deAnalytics`)

- Filters: date range, team, object, split by (User or Distributor).
- Charts, drawn as SVG with no external libraries:
  - Distributions over time
  - Hourly trend
  - Time to action (average by user)
  - User activity (online minutes, toggles)
- **Team Performance table.** For each member: Records Assigned, Avg Time to Action, Reassignments, SLAs Missed, Rejected, Actioned %, Conversion rate (for Leads). Action: **Download CSV**.

### S9 Distribution Settings (`deSettings`)

- **General.**
  - Engine enabled, scheduler interval, records per run.
  - Previous assignees tracked; hold after N failures; hold minutes.
  - Log retention; decision trace.
  - Platform events; week start.
- **Availability.** Toggle reasons, require a reason, timer durations, timer toggles only, start-of-day and end-of-day toggle behaviour.
- **Rejection.** Reject reasons; allow "Other".
- **Load balancing and rotation.** Count pull or manual assignments in rotation; include sticky or lookup assignments in balancing.
- **Classifier.** Enabled, objects, distribute after classify, personal domains.
- **Triggers.** Process trigger distributors.
- **Archive.** Enabled, after N days, archive queue.
- **Jobs.** Start or stop the scheduler; schedule the health checker and maintenance jobs; show their status.
- **Export / Import.** Download JSON; paste or upload JSON to import.

### S10 Widget (`deWidget`, utility bar)

- An **Online / Offline** toggle. Turning it off can require a reason and can offer a timer; while off, a countdown shows.
- **My Out of Office**: create an entry quickly.
- **Get Next**: one button per Pull distributor the user can pull from, labelled with the number of waiting records.
- **Assigned to me**: the last 5 current assignments, sortable by SLA remaining. Each has a **Reject** action.
- **Missed SLAs** count, which can be clicked to see the list.
- A **real-time toast** on each new assignment, through an empApi subscription to `/event/DE_Assignment_Event__e`. If empApi is not available, the widget polls every 10 seconds instead.

### S11 Record Detail (`deRecordDetail`, record page)

- A status header: Distributed?, team, distributor, assignee, SLA status, time to action, territory and stamps.
- **History**: a timeline of logs for the record.
- **Assign**: manual distribution (team picker, then a member list with availability and today's count).
- **Reject**: reason picker.
- **Distribute Now**: runs trigger and standard distribution for this record.
- **Simulate**: opens `deSimulator` with the record Id filled in.

## Shared components

| Component | Used by | Purpose |
|---|---|---|
| `deConditionBuilder` | Filters everywhere | Rows of Field (searchable combobox with relationship paths and DE.* pseudo-fields) / Operator (limited to the field type) / Value, add and remove rows, a logic input, and validation messages. |
| `deRecordPicker` | Every User or Queue Id field | Searches users, queues or both and returns an Id and label. |
| `deFieldUpdatesEditor` | Post-assignment, reassignment, rejection | Field and value rows that serialise to `Field=Value` lines. |
| `deShiftEditor` | Shifts | Seven day rows, each with up to 3 blocks. |
| `deSimulator` | Console, record page | The assignment simulator. |
