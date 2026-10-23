# Behaviour Specification

This document specifies each workflow as **inputs → decisions → outputs**, followed by its **state transitions**, **validations** and **errors**.

- The algorithm details are in `routing-algorithms.md`.
- The evidence keys (L, H/…, I) are defined in `target-feature-inventory.md`.
- Confidence is defined in the same file. "Partially verified" means the vendor documents the behaviour but we have not observed it running.
- Where our build deviates from the reference or fills a gap, the entry is marked **Design decision**.

---

## W1 Create and configure a Distribution Team (F01, F07)

- **Evidence:** H/teams/distribution-teams, H/team-settings-page/team-settings, H/team-settings-page/assign-to-field. *Partially verified.*
- **Inputs:**
  - Name.
  - Distribution Object: the API name of any object that has OwnerId or a User lookup.
  - Execution Order.
  - Team Type: Standard or Queue to Queue.
  - Assignment Field: defaults to `OwnerId`.
  - Team Hours (a Shift) and Holiday Region.
  - Round Robin Level, Load Balancing Level, Load Balancing Type, Balance By, Active Status.
  - Weighting mode, rejection limit, action tracking, SLA hours, object sync, managers, dynamic members.
- **Decisions and validations (`DE_AdminService.saveTeam`):**
  - The object must exist and must be ownable, or must contain the chosen assignment field.
  - The assignment field must be a User reference. `OwnerId` is also accepted on queue-capable objects.
  - **The Object cannot change once the team exists.** Error: "The distribution object cannot be changed after the team is created."
  - **The Assignment Field cannot change while distributors exist.** Error: "Remove the team's distributors before changing the assignment field."
  - Every Active Status field and Balance field must exist on the object. The Balance field must be numeric.
  - A new team is saved **inactive**. Activation is an explicit action.
- **Outputs:** a `DE_Team__c` record. Field history is tracked (F53).
- **States:** Inactive → Active → Inactive.
- **Errors:** Validation errors are returned to the UI as a field-level message. Nothing is saved when validation fails.

## W2 Manage team members (F02, F03, F04, F13)

- **Evidence:** H/teams/adding-and-removing-team-members, H/advanced/q-2-q-teams, H/teams/dynamic-team-members, H/weighting-and-caps/weighting. *Partially verified.*
- **Inputs:** one or more Users (or Queues for a Queue-to-Queue team), Active, Weight (0.25–4 in steps of 0.25), Member Hours (Shift).
- **Decisions:**
  - The membership key `Unique_Key__c = teamId|memberId` blocks duplicate memberships.
  - Each member must be exactly one User or one Queue. A Queue-to-Queue team accepts queues only; a Standard team accepts users only.
  - When a user is added, a `DE_Agent__c` row is created if one is missing (Online = true).
- **Dynamic members:**
  - The `DE_DynamicMembersJob` (nightly, or run on demand from the UI) evaluates the `Dynamic Membership` conditions against active Users.
  - Matching users are added with `Dynamic__c = true`.
  - Dynamic members who no longer match are deactivated.
  - Members added manually are never removed by this job.
- **Errors:** "This user is already a member of the team." "Weight must be between 0.25 and 4 in steps of 0.25." (validation rule `DE_Weight_Range`).

## W3 Create a Distributor (F05, F06, F08, F09, F10, F15–F21)

- **Evidence:** H/team-distributors/*, H/distribution-methods/*. *Partially verified.*
- **Inputs:** Type, Method, Source, filters and logic, sort order, member filter, availability overrides, weighting, caps, sticky, lookup/related/dynamic settings, pull count, post-assignment updates, SLA and auto reassign, rejection.
- **Validations:**
  - Which methods each Type allows:

    | Type | Allowed methods |
    |---|---|
    | Standard | Round Robin, Load Balancing, Lookup Owner, Related Owner |
    | Pull | Round Robin (internally treated as "Pull") |
    | Manual | Any method (the method is ignored) |
    | Trigger | Round Robin, Load Balancing, Dynamic Owner, Current Owner |

  - **Source:**
    - A Queue source needs an `00G…` Id, and queues require an object that supports them (Lead, Case, Task, custom).
    - A User source needs a `005…` Id, and that user must not be a team member (H/team-distributors/distributor-sources).
    - A Field Value source needs a picklist field plus a ready value.
  - **Only one Manual distributor per team** (H/team-distributors/manual-distributor-settings).
  - Filter logic must parse, and it may only reference row numbers that exist. Error: "Filter logic references condition 4, which does not exist."
  - Every filter field must exist (paths are resolved through describe). Each operator must suit the field type.
  - **Trigger** distributors allow at most 5 filters (H/team-distributors/trigger-distributor-settings).
  - Sort fields must be sortable. Multi-select picklists and long text are rejected.
  - Sticky requires a match field. Auto reassign requires Reassign To. Rejection requires Reject To. These are enforced by validation rules.
  - Custom caps: minutes 5–180, hours 1–168, days 1–31.
- **Outputs:** `DE_Distributor__c` records plus their conditions and caps. A new distributor is saved **inactive**.

## W4 Scheduler distribution (F11–F14, F23, F24, F25)

- **Evidence:** H/team-distributors/distributor-types, H/distribution-methods/algorithms-round-robin, H/weighting-and-caps/caps. *Partially verified.*
- **Input:** a scheduler tick. Records waiting at their sources.
- **Decisions:** see `routing-algorithms.md` §2–§7.
- **Outputs, per assigned record:**
  - The assignment field is updated.
  - `DE_Is_Distributed__c = true`, `DE_Last_Distributed__c = now`, `DE_Distribution_Count__c + 1`.
  - Post-assignment field updates are applied.
  - A Distribution Log row is written with Status `Assigned`.
  - Rotation state advances.
  - A notification is sent and a platform event is published.
- **States of a record at its source:**

  ```
  Waiting at source ──assigned──> Assigned (log Current)
        │ no eligible member
        ├──> stays at source (retry next run); Failed_Attempts + 1
        └──(attempts ≥ threshold)──> On Hold until now + hold minutes ──> retried
  ```

- **Errors:**
  - A DML failure on a record (for example a validation rule on the target object) produces a log with Status `Error` and the message. The record stays at its source and its failure count goes up.
  - An unexpected exception in a team is caught. The run log gets Status `Error`, and the chain still re-enqueues itself.

## W5 Trigger distribution (F21)

- **Evidence:** H/team-distributors/trigger-distributor-settings, H/settings/trigger-settings. *Partially verified.*
- **Input:** an update on Lead, Case or Opportunity where `DE_Trigger_Distribution__c = true`, or a call to the Flow/Apex API.
- **Decisions:**
  1. The master switch `Trigger_Distribution_Enabled__c` must be on.
  2. Teams are taken in execution order, then active Trigger distributors in order. The first distributor that assigns the record wins.
  3. Distribution hours are ignored unless the team has `Respect_Hours_For_Triggers__c` set.
  4. If no distributor assigns the record, the first matching distributor's `Default_Owner_Id__c` is used.
- **Outputs:**
  - The owner is set in the same transaction (before update).
  - `DE_Is_Triggered__c = true` and `DE_Trigger_Distribution__c = false`.
  - A log is written.
- **Errors:** No retry, as documented. When nothing matches and there is no default owner, the record is left unchanged and a log is written with Status `Error` and the message "No trigger distributor could assign this record".

## W6 Pull ("Get next") (F19, F55)

- **Evidence:** H/team-distributors/pull-distributor-settings. *Partially verified.*
- **Input:** the user clicks **Get Next** in the widget for one of their Pull distributors.
- **Decisions:**
  - The user must be an active member of the team.
  - Records must pass the source, filters and the member filter for this user.
  - Caps are respected.
  - Up to `Pull_Count__c` records are taken in sort order.
- **Outputs:**
  - The records are assigned to the user with log Type `Pull`.
  - The widget shows the records it received.
  - If there are none, the message is "No records are available to pull right now."
- **Errors:**
  - Lock timeout: "Another assignment is in progress for this team. Try again." The user can retry.
  - Not a member: "You are not an active member of this team."

## W7 Manual distribution (F20, F56)

- **Evidence:** H/team-distributors/manual-distributor-settings. *Partially verified.*
- **Input:** on the Record Detail component, the manager picks a team that has an active Manual distributor, then picks a member.
- **Information shown:** each member's availability (Available or Unavailable, with the reason) and their assignments today.
- **Decisions:**
  - Requires the `DE_Team_Manager` (or higher) custom permission and edit access to the record.
  - **Caps are ignored.**
  - If `Treat_Manual_As_Rejection__c` is set, the previous owner is treated as having rejected the record. They get a replacement credit, and the record is added to their previous assignees.
- **Outputs:** the assignment field is updated, and a log is written with Type `Manual`. It counts toward caps and load balancing; it counts toward rotation only if `Count_Manual_As_Hit__c` is set.

## W8 Availability (F27–F34)

- **Evidence:** H/distribution-availability/*, H/hours/*. *Partially verified.*
- **Shift:**
  - A timezone plus a JSON schedule giving up to 3 blocks per weekday.
  - A block may end at `+1` (overnight).
  - Validation: blocks are `HH:MM-HH:MM`, at most 3 per day, and must not overlap. Error: "Monday has overlapping blocks."
- **Holiday:**
  - Fields: region, start, end, all day, timezone.
  - All-day holidays cover local 00:00 to 24:00 on each date in the range.
  - When a holiday is active, teams in that region do not distribute at all.
- **Out of Office:**
  - Fields: user or queue, start, end, all day, reason (at most 80 characters).
  - Applies to every team.
  - Users can create their own OOO. Managers with `DE_Team_Manager` can create OOO for others.
- **Toggle:**
  - Requires a reason when `Require_Toggle_Reason__c` is set. The reason must come from `Toggle_Reasons__c`.
  - **Timer toggles:**
    - The duration comes from `Timer_Durations__c`.
    - With `Timer_Toggles_Only__c` set, users can only toggle off with a timer. Managers are exempt.
    - The user comes back online automatically at `Toggle_Until__c`.
  - Every change writes a `DE_Availability_Event__c` row recording who, when, the reason and the source.
  - **Start of day:** applied at the first run after local midnight, using the user's timezone.
  - **End of day:** applied at the first run after the end of the user's last shift block that day.
- **Calendar (F34):** when an Event is created with `ShowAs = OutOfOffice` and a duration of at least 1 hour, a `DE_Out_Of_Office__c` row is created with Source = Calendar. Events created before calendar integration was turned on are ignored. *Design decision (subset of the reference, which also covers Exchange and Google via Einstein Activity Capture).*

## W9 Classification on insert (F35–F38, F40)

- **Evidence:** H/distribution-classifier/*, H/territories/*, H/matching/*, H/auto-conversion/*, H/custom-classification/*. *Partially verified.*
- **Input:** insert of a record whose object is listed in `Classifier_Objects__c`, or a backfill request.
- **Decisions:** see `routing-algorithms.md` §10.
- **Outputs:**
  - A `DE_Record_Detail__c` row (Done).
  - Territory and stamp fields are stamped on the record.
  - Matched account, contact or lead.
  - The lead may be converted or merged.
  - Records are distributed immediately when `Distribute_After_Classify__c` is set.
- **Errors:**
  - A conversion or merge failure leaves the lead unconverted, sets `Conversion_Result__c = "Failed: <message>"` and logs a run warning.
  - Classification still finishes (Done), so routing is never blocked.

## W10 SLA, escalation and auto reassign (F42, F43, F45)

- **Evidence:** H/tracking-and-slas/sla, H/tracking-and-slas/auto-reassign, H/tracking-and-slas/tracked-assignees. *Partially verified.*
- **Input:** a log whose `Next_SLA_Check__c` has passed.
- **Decisions and outputs:** see `routing-algorithms.md` §8.
- **Log states:** `Pending → (checkpoint fired) SLA Alert/Pending → … → Met | Missed | Cancelled`. If the record is reassigned, the log becomes `Reassigned` and not current.
- **Errors:** A reassignment DML failure is logged on the run log, and the log keeps `SLA Alert` so it is retried on the next pass.

## W11 Rejection (F44)

- **Evidence:** H/teams/assignment-rejection, H/api/global-rejection-api. *Partially verified.*
- **Input:** a reject request (widget, record component or API) with a reason. The reason must be one of `Reject_Reasons__c`, or "Other" with free text when that is allowed.
- **Decisions:** see `routing-algorithms.md` §9.
- **Errors:**
  - "This record has been reassigned since it was distributed and can no longer be rejected."
  - "You have reached today's rejection limit (3)."
  - "Only managers can reject assignments for this team."
  - "Rejection is not enabled for the distributor that assigned this record."

## W12 Action tracking (F41)

- **Evidence:** H/tracking-and-slas/action-tracking. *Partially verified.*
- **Input:** a record update that changes the team's action field to a tracked value, or a Task or Event logged with a type listed in `Auto_Action_Activity_Types__c`.
- **Decisions:**
  - The current log must have no action time yet.
  - The modifying user must be the assignee, unless `Track_Action_From_Any_User__c` is set.
- **Outputs:**
  - `Action_At__c` and `Time_To_Action_Mins__c` on the log. Working minutes follow `Action_Respect_Hours__c`.
  - `DE_Time_To_Action__c` on the record.
  - For an auto action, the action field is set to the first tracked value.

## W13 Object Sync (F46) and Archive (F47)

- **Object Sync:** see `routing-algorithms.md` §11. Each run writes a `DE_Run_Log__c` with Process = Object Sync.
- **Archive:** see `routing-algorithms.md` §12. Each daily run writes a run log with Process = Archive. Restore happens inline in the trigger.

## W14 Logs, retry and monitoring (F48–F50)

- **Distribution Logs screen:**
  - **Filters:** date range, status, object, team, distributor and assignee. Shows up to 500 rows.
  - **Retry** (Status Error or On Hold): clears the hold and failure count on the details. The next scheduler run picks the record up again.
  - **Retry all:** up to 9000 records.
- **Application Monitoring:**
  - Scheduler state: Running if a `DE_SchedulerJob` is queued or processing, Not Running, or Errored if the last run log has Status Error.
  - Health checker scheduled: yes or no. Last run time. Errors in the past day.
- **Today's Distributions:** for each team, today's counts of assignments, SLA alerts, reassignments and errors, plus "available x of y".

## W15 Simulator and test tool (F54)

- **Evidence:** H/assignmentsimulator/*. *Partially verified.*
- **Inputs:**
  - Record Id.
  - Options: Simulate at a date/time, Ignore caps, Include inactive teams/distributors, Stop on first successful assignment.
- **Outputs:** for each team and distributor, PASS or FAIL for:
  - Object
  - Source
  - Filters, with each condition's result
  - Eligible members, with the reason each one was excluded
  - Method choice

  Also the member who *would* be chosen.
- **No DML and no locks.**

## W16 Settings, permissions, export and import (F57–F59)

- **Settings:** saving requires `DE_Admin`. Starting or stopping the scheduler and scheduling the health checker are admin-only.
- **Permission sets:**

  | Permission set | Scope |
  |---|---|
  | `DE_Admin` | Everything. |
  | `DE_System_Manager` | Everything except Settings, the Classifier and the scheduler. |
  | `DE_Team_Manager` | Teams where their Id is in `Manager_User_Ids__c`: members, weights, caps, OOO for members, manual assignment. Holidays and shifts are read-only. |
  | `DE_User` | Widget, own OOO, own logs, reject. |

  The controllers check the matching custom permissions on every action. *(H/permissions/permission-set-overview)*
- **Export:** JSON containing teams with members, distributors, conditions, caps and SLAs, plus shifts, holidays, territories, stamp groups, matching rules, conversion rules and sync actions.
- **Import:** imported teams are inactive and territories are Draft. Ids are remapped. Users are matched by Username, and queues by DeveloperName.

## W17 Reporting (F51, F52)

- **Report type:** "DE Distribution Logs with Team and Distributor".
- **Reports:**
  - Distributions by Team (this month)
  - Distributions by Assignee (today)
  - SLA Alerts and Missed SLAs
  - Rejected Assignments by Day
  - Speed to Assign by Team
  - User Availability History
- **Dashboard:** "Distribution Engine Overview".
- **Analytics tab (LWC):** distributions over time, hourly trend, time to action and user activity. Filters: date range, team and object.
