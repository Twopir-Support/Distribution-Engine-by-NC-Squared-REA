# Help-centre Evidence for Components in the Reference CSV

These notes come from public pages at `help.distributionengine.com`, read on 2026-10-23 with WebFetch. We did not log in or bypass anything.

WebFetch returns model-made summaries of each page, so quotes are approximate. Paths are relative to the help centre. **INFERRED** marks our own inference.

They support `metadata-replication-matrix.md` for components the earlier evidence did not cover.

## Shift planner (CSV: Team shift planner, Shift planner block)

Sources: /hours/shift-planner, /hours/team-member-distribution-hours, /distribution-availability/shift-hours, /permissions/custom-permissions.

- Available on the Unlimited tier.
- Team managers assign shifts to members up to 12 weeks ahead. The view covers 4 weeks back and 12 weeks forward, and opens on the current week.
- Each member row shows the allocated shift per week. Click a week, pick a shift, and the change "applies until the next defined shift change".
- **INFERRED:** blocks are change points of (member, start week, shift). Each one holds until the next block.
- Turning the planner off keeps each user on their current shift and drops future changes.
- A member's hours come from one of three modes:
  - **Shift:** a reusable shift.
  - **Individual:** the member's own hours.
  - **Shift Planner:** the planned changes.

  Team hours are the default, and member hours override them.
- Only a Custom Team Manager with the "Switch to Shift Planner" permission can switch a team's planner on or off. The standard Team Manager cannot.
- Cloning is not documented.

## Assignment rejection (CSV: Distribution reject log, rejection configs)

Sources: /teams/assignment-rejection, /teams/stamp-rejection, /api/global-rejection-api, /settings/distribution-settings.

- **Team limit:**
  - Unlimited.
  - Manager only: System Manager or Admin.
  - Limited: N per day per user.
- **Stamp rejection:** each configuration is a set of stamps with Reject To, up to 3 field updates and a replace option. The highest-priority configuration wins.
- **Distributor settings:**
  - Enable.
  - Reject To (user or queue).
  - Up to 3 field updates.
  - Replace options: on usual assignment, as next assignment, or don't replace.
  - Remove sticky from rejected records: new sticky only, always, or never.
- **Reasons:**
  - Free text by default, or a list in Distribution Settings.
  - "Allow users to enter a custom reject reason" adds "Other".
- **Who can reject:**
  - Users reject their own assignments.
  - Managers and admins can reject on a user's behalf.
- **Where rejection is available:**
  - The record component.
  - The logs row menu.
  - The widget's "Assigned to me" section.
- **When rejection is unavailable:**
  - The owner changed after assignment.
  - The assignment errored.
  - The team is queue-to-queue.
  - The distributor does role assignment.
- **API:** `GlobalAPIReject.rejectAssignment(recordId, reason)`, and a bulk version taking up to 500 requests. The user must be "within their rejection request limit".
- **Not documented:** a manager approval or review queue. Public docs describe rejection as taking effect immediately.
  - **INFERRED:** the reject log records each rejection request (requested by, request time, reason) and its review.
  - **Our design:** we record every rejection request, apply allowed requests immediately with status Approved, and record denied ones with the reason.

## Change history (CSV: History object, *History Apex classes)

Source: /managing-and-monitoring/change-history.

- An audit of configuration changes and who made them.
- **Tracked areas:**
  - Teams.
  - Team members.
  - Distributors.
  - Holidays.
  - Out of office.
  - Shifts.
  - Tag assignments.
- **Where it shows:** under "History" in the page menu, listing the last 100 changes within the retention period.
- **Retention:** set by "Maintain change history logs" in Distribution Settings.

## Personas (CSV: Distribution engine profile, User profile, Custom Team Manager permission set)

Sources: /permissions/persona-management, /permissions/persona-assignment, /permissions/custom-permissions.

- Every user with the Custom Team Manager permission set has exactly one persona.
- **Personas:**
  - There is always one Default persona. It cannot be renamed or deleted.
  - You can add, rename, clone and delete personas. Names must be unique.
  - Deleting a persona requires reassigning its users to another persona.
- **Assignment:**
  - Per user, from a side panel.
  - In bulk, with "Assign Persona".
- **Capabilities and levels.** Anything not listed is not accessible.

| Capability | Levels |
|---|---|
| Test Tool | No Access / Access |
| Team List | No Access / Access |
| Team Summary | No Access / Access |
| Team Members | No Access / View / Edit, Create and Delete |
| Team Members Toggle | View / Edit |
| Team Availability | No Access / View |
| Team Performance | No Access / View |
| Distributors | No Access / View / Edit / Create and Delete |
| Edit Distributors sub-options | Name, Method, Source, Distributor Filters, Team Member Filters, Activate/Deactivate |
| Weighting | No Access / View / Edit |
| Caps | No Access / View / Edit |
| Holiday Region | No Access / View / Edit |
| Distribution Hours | No Access / View / Edit |
| Switch to Shift Planner | No Access / Edit |
| Tracking and SLAs | No Access / View / Edit |
| Assignment Rejection | No Access / View / Edit |
| Post Assignment | No Access / View / Edit |
| Team Settings | No Access / View / Edit, with sub-options Filter and Advanced |
| Tag Collections | No Access / View / Edit / Create / Delete |
| Tag Assignment | No Access / View / Edit, Create and Delete |
| Out of Office | Create Own / View Team / Create and Delete |
| Regional Holiday | No Access / View / Edit, Create and Delete |
| Shifts | No Access / View / Edit / Create and Delete |
| Distribution Logs | View Own / View Team / Delete |
| Analytics | No Access / Access |

- "Team" scopes mean the teams the user manages.

## Role assignment (CSV: Distributor team role fields, Salesforce team Apex classes, role notification flows)

Sources: /team-distributors/distributor-saleforce-teams, Rhino 22.1 release notes.

- **Objects:** Account, Opportunity and Case teams, which must be enabled in the org.
- **Distributor settings:** "Salesforce Team Member" plus a team role and access levels.
  - Account access levels cover Account, Case and Opportunity.
  - Opportunity access covers Opportunity.
  - Case has no access settings; access comes from the Case Team Role.
- **"Add default team":** for Account and Opportunity, adds the assignee's default team.
- **Limitations:**
  - The source must be Field Value.
  - No object sync, rejection, SLAs, or active and criteria caps.
- **Notifications:** the flows "DE Email Team Role Notification on new log / on log update".

## Email notifications (CSV: 3 templates, 3 email alerts, 2 workflow rules, 4 email flows, EmailNotification VF components)

Sources: /emails/email-notifications, /emails/disabling-standard-email-notifications, /emails/email-template, /teams/post-assignment.

- The assignee is emailed on assignment, SLA alert or reassignment.
- **Mechanism:** the legacy workflow rule "Distribution Engine Notification", or the flows "DE Email Notification on new log / on log update".
- **Content:**

| Object | Fields shown |
|---|---|
| Lead | Name, Source, Company, Rating, Status |
| Opportunity | Name, Source, Type, Stage |
| Case | Number, Subject, Priority, Type, Account, Contact, Status |

  No long descriptions are included.
- **Disabling:**
  - Deactivate the flows.
  - Per team: turn off logging.
  - Per distributor: uncheck "Send standard email notifications".

## Action tracking (CSV: Distribution log action)

Sources: /tracking-and-slas/action-tracking, /managing-and-monitoring/distribution-analytics.

- Measures the time from assignment to the tracked action value(s). Several values can count as an action.
- Respects hours: Team and member, Team only, or None.
- Can track actions from any user.
- Tasks and Events can auto-action a record.
- Analytics shows "Time to action" per monitored action.
- **INFERRED:** one action record per tracked action on an assignment.

## Classifier and object sync logs (CSV: 4 classifier log objects, Object sync log)

Sources: /logs/territories-logs-list, /logs/lead-matching-logs-list, /logs/custom-classification-logs-list, /logs/auto-conversion-logs-list, /logs/object-sync-logs-list, /configuration/object-sync.

- **Territory log:**
  - Columns: Date, Name, Status, Object, Territory (Map.Territory).
  - Detail panel: match level (Country, State or Postcode) and the cleaned address.
- **Matching log:**
  - Columns: Date, Name, Status, Matched Account (with type), Matched Contact, Matched Lead.
  - Detail panel: confidence and the rule used.
- **Custom classification log:** Date, Name, Status, Object, Stamp Group, Stamps.
- **Auto-conversion log:**
  - Columns: Date, Name, Type (Conversion or De-Duplication), Opportunity Created, Status, Assignee.
  - Detail panel: the target records.
- **Retry:** failed classifications are retried on each classifier run. The Health Checker emails about repeated failures.
- **Object sync log:**
  - Columns: Date, Name, Status (error, or skipped with no actions), Object, Number of Actions, Team, Assignee.
  - Detail panel: object types and record counts synced.
- **Sync actions:**
  - Defined per distribution object: related object plus an optional filter. They can be activated or deactivated.
  - Each child object must have a lookup to the distribution object.
  - Teams enable sync on their Post Assignment page.

## Holiday regions (CSV: Holiday Region, Regional Holiday)

Sources: /distribution-availability/holiday-regions, /distribution-availability/regional-holidays, /hours/team-holiday-regions.

- **Region:**
  - Has a name only.
  - Can be deleted only when no team uses it.
  - Each team chooses one region.
- **Holiday:** Name, Region, All-day, Starts, Ends, Timezone.
  - An all-day holiday runs from 00:00 on the start date to 23:59:59 on the end date.
- Team managers have read-only access to regions and holidays.

## Tags, weighting and caps

Sources: /tagging/*, /weighting-and-caps/*.

- **Collections:** attributes that hold tags.
- **Assignment:** org-wide, shown as Collection/Tag. Bulk assignment and clone (append or replace) are supported.
- **Tag weighting:** a default weight plus a weight per tag. If a member has several tags, the highest weight wins.
- **Tag caps:** a default cap plus a cap per tag.
- **Caps in general:**
  - Up to 3 team cap periods.
  - Custom rolling periods: minutes 5–180, hours 1–168, days 1–31.
  - Criteria caps.
  - Active caps.

## Other items

- **Classic home page component.** "Distribution Engine Widget" is legacy, and the older "Distribution Engine" component no longer works. Mobile users get a Lightning app page with the widget.
- **Processing modes** (Queueable, Automatic, Parallel, Asynchronous, Synchronous, Batch) and the licensed-users list are documented.
- **Not documented:**
  - Targeted messages, analyticsGuidance, tier reduction.
  - Prevent overflow, experimental distributors, "not operators".
  - Platform cache.
