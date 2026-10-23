# Routing Algorithms

This document describes how the engine routes records, step by step. For each part it gives the reference behaviour and how it was evidenced, then what our build does and which Apex class does it. Evidence keys (L, H/…, I) are defined in `target-feature-inventory.md`.

> **Confidence.** All reference behaviour here comes from the vendor's public documentation (**partially verified**). None of it was observed running, because no authorised org with the package was available. Where we had to fill a gap, the text says **Design decision (inferred)**.

---

## 1. How records enter distribution

| Path | Reference behaviour | Evidence | Our implementation |
|---|---|---|---|
| **Scheduler (Standard distributors)** | Queueable jobs run "approximately every minute" and pull records from each distributor's source. Records are retried until someone can take them. | H/team-distributors/distributor-types | `DE_SchedulerJob`, a self-chaining Queueable. It calls `System.enqueueJob(job, delayMinutes)`, where the delay comes from `Scheduler_Interval_Minutes__c` (1–10). `DE_HealthChecker`, a Schedulable that runs hourly, restarts the chain if it has died. |
| **Classification on insert** | The classifier runs on create. Distributors wait until the classifier status is `Done`. | H/distribution-classifier/classifier, H/de-widget/distributor-test-tool | The `DE_TriggerHandler` after-insert step enqueues `DE_ClassifierJob`. The job writes `DE_Record_Detail__c` with `Classifier_Status__c = Done`. If `Distribute_After_Classify__c` is set, it then routes those records straight away instead of waiting for the next tick. **Design decision (inferred):** this gives better speed-to-lead. |
| **Trigger distributors** | Run only on **update**, when the record is flagged. They assign immediately, have no retry, and fall back to a default owner. | H/team-distributors/trigger-distributor-settings | Before-update trigger. Fires when `DE_Trigger_Distribution__c` is true (Lead, Case, Opportunity), or when Flow or Apex calls the API. The owner is set directly on `Trigger.new`, so no extra DML is needed. |
| **Pull** | A member clicks the button and receives 1–100 records from the source. | H/team-distributors/pull-distributor-settings | `DE_PullService.pull(userId, distributorId)`, called from the widget. |
| **Manual** | A manager picks the member on the record page. This is allowed even when the member is at their cap. | H/team-distributors/manual-distributor-settings | `DE_ManualAssignService.assign(recordId, distributorId, userId)`. |
| **Flow / Apex** | The "DE Distribute Records" action. | H/api/trigger-distribution-api | The `DE_DistributeRecordsAction` invocable method and the `DE_Api` global class. |

## 2. Scheduler run sequence (Standard distributors)

Each run does the following:

1. **Guards.** Stop if the engine is disabled. Housekeeping:
   - Bring users whose timer toggle has expired (`Toggle_Until__c <= now`) back online.
   - Apply the start-of-day toggle rule.
   - Apply the end-of-day toggle rule.
2. **Teams.** Process each active team ordered by `Execution_Order__c` (ascending), then by Name. *(H/teams/distribution-teams: "top to bottom")*
   1. **Holiday check.** If a holiday in the team's holiday region is active now, skip the whole team. Holidays are respected even when a distributor ignores availability. *(H/distribution-methods/algorithms-round-robin)*
   2. **Lock.** Lock the team row with `SELECT … FOR UPDATE`. Every assignment path (scheduler, pull, manual, trigger, reassignment) takes this lock first, so rotation state cannot be read or written concurrently. *(Design decision (inferred).)*
   3. **Distributors.** Process each active **Standard** distributor ordered by `Order__c`:
      1. **Candidate query.** `WHERE <assignment field> = :sourceId` for a Queue or User source, or `WHERE <source field> = :readyValue` for a Field Value source.
         - Add `AND <active status field> IN :values` when the team defines Active Status. *(H/troubleshooting/faq-stuck-in-the-queue)*
         - Apply the custom sort order (default `CreatedDate ASC`) and cap the query with `LIMIT`.
      2. **Drop records that are not ready.** Drop records still being classified (details exist with status not `Done`, and the record is less than 10 minutes old). Drop records that are on hold (`On_Hold_Until__c > now`).
      3. **Evaluate filters.** Team filters (Purpose `Team Filter`) and then distributor filters (`Distributor Filter`), each with its own logic.
      4. **Assign** the records that pass (section 3). A record that is not assigned stays at its source and **overflows** to later distributors and later teams. *(H/territories/territory-distributor, "catch-all")*
   4. **Persist** (section 7).
3. **Failed attempts.** For every candidate record that passed filters but was not assigned by any distributor in this run, increment `Failed_Attempts__c`. Once it reaches `Hold_After_Failures__c`, set `On_Hold_Until__c = now + Hold_Minutes__c` and write an `On Hold` log. The documented "on hold" feature has these thresholds hidden, so ours are configurable. *(Design decision (inferred).)*
4. **SLA monitor.** Process up to 200 logs with `Next_SLA_Check__c <= now` (section 8).
5. **Run log.** Write a `DE_Run_Log__c` row (Process = Scheduler). It records records processed, assignments, errors and duration.
6. **Re-enqueue.** Schedule itself again with the configured delay.

### Budgets and governor limits

- **Per-run record budget.** `Records_Per_Run__c` (default 500, matching the reference's "default limit of 500 records per run").
- **Query safety stop.** If `Limits.getQueries()` exceeds 70% of the limit, the run stops early. The next run resumes from the next team, using a team cursor carried in the job state.

## 3. Assigning one record inside a distributor

The steps run in this order:

1. **Sticky** (if enabled and the method is Round Robin or Load Balancing). Build the key `<level prefix>|lower(trim(value of Sticky_Field__c))`, where the prefix is `D|<distributorId>`, `T|<teamId>` or `G`. Look up the most recent log with that `Sticky_Key__c` and `Assigned_At__c >= now - Sticky_Days__c`.
   - If the previous assignee is an eligible member, assign to them. Availability can be bypassed by the retain options.
   - Tagging is ignored for sticky assignments.
   - Caps follow `Sticky_Cap_Behaviour__c`:
     - *Ignore Caps*: assign regardless.
     - *Assign to Next Member*: fall through to normal selection.
     - *Don't Assign*: skip the record.
   - The log has `Is_Sticky__c = true` and `Counts_As_Hit__c = false`, so the member keeps their round robin place.
   - If there is no match and `Sticky_Only__c` is set, skip the record.
   - *(H/distribution-methods/distribution-algorithms-sticky)*
2. **Eligibility** (section 4) produces the eligible member list for this record.
3. **Method** (section 5) picks one eligible member.
4. If nobody is eligible, the record is not assigned. Rotation state does **not** change. *(H/distribution-methods/algorithms-round-robin: "nothing happens… round-robin order is not changed")*

## 4. Eligibility (who can receive this record)

Filters are applied first. Availability is then evaluated in the reference order **Holidays → Out of Office → Distribution Hours → Widget toggle** *(H/distribution-methods/algorithms-round-robin)*.

| Step | Rule | Overridable by |
|---|---|---|
| 1. Membership | The member is active and the user is active. Queue members (Q2Q teams) skip user checks. | — |
| 2. Selected members | If `Assign_To__c = Selected Members`, only those Ids are eligible. | — |
| 3. Member filters | `DE_Condition__c` rows with Purpose `Member Filter` (see list below). | — (ignored for sticky matches) |
| 4. Exclude field | Ids held in the record's `Exclude_Members_Field__c` are removed. | — |
| 5. Previous assignees | The last N assignees in `Previous_Assignees__c` (N = `Previous_Assignees_Tracked__c`) are removed, unless they are the only eligible candidates. *(H/tracking-and-slas/tracked-assignees)* | — |
| 6. Out of Office | An active `DE_Out_Of_Office__c` for the user or queue makes them unavailable. | `Assign_If_Unavailable__c` |
| 7. Hours | The member's shift, or the team shift if the member has none, must contain "now". | `Assign_If_Unavailable__c` |
| 8. Toggle | `DE_Agent__c.Online__c` must be true. A user with no `DE_Agent__c` row counts as online. | `Assign_If_Unavailable__c`, `Assign_If_Offline__c` |
| 9. Caps | Distributor caps always apply. Team caps apply when `Respect_Team_Caps__c` is set. A member at any cap is ineligible. *(H/weighting-and-caps/caps)* | Manual distribution and Lookup Owner ignore caps |

**Member filter types (step 3):**

- `Tag:<Collection>` with `includes`, `includes all` or `does not include`, against the semicolon-separated tags in the value.
- `DynamicTag:<Collection>` matched against a record field: the value is the record field API name, and the record's value must equal one of the member's tags in that collection.
- `Territory` against the record's classified territory name.
- `Stamp:<Group>` against the record's stamps in that group.

### Cap periods

These are counted from `DE_Assignment_Log__c` rows with Status `Assigned` and `Counts_As_Hit__c` or sticky, scoped to the team or the distributor.

| Period | Window start |
|---|---|
| Hourly | Top of the current hour, team timezone. Not rolling. |
| Half-hourly | Last :00 or :30. |
| Daily | Local midnight in the team timezone. |
| Weekly | Local midnight on the week start day (`Default_Weekday_Start__c`, default Monday). |
| Monthly | Local midnight on the 1st. |
| Custom Minutes / Hours / Days | `now - length`. Rolling. |
| Active | Count (or summed `Balance_Field__c` value) of records the user owns that are in Active Status, from any source. |
| Criteria | Count of records the user owns that match the cap's `Cap Criteria` conditions, or the team and distributor filters when `Criteria_Source__c = Distributor Filters`. |

**Cap value.** If the member has a tag listed in `Tag_Caps__c`, the first matching line's value is used; otherwise `Default_Cap__c` is used. A blank value means unlimited. *(H/weighting-and-caps/capping-by-tags)*

## 5. Methods

### Round Robin *(H/distribution-methods/algorithms-round-robin)*

- **Scope.** The scope key is `teamId|memberKey` when `Round_Robin_Level__c = Team`, and `distributorId|memberKey` when it is `Distributor`.
- **State.** `DE_Rotation_State__c` holds `Last_Sequence__c`. The team holds a monotonically increasing `Rotation_Sequence__c`, protected by the team row lock.
- **Pick.** Choose the eligible member with the lowest `Last_Sequence__c` (0, meaning never assigned, comes first). Ties break by member record Name, which is stable. This is the "longest without an assignment" rule. Members returning from absence keep their low sequence, so they are first in line.
- **After assigning.** Increment the team sequence and store it on the member's state.
- **Counting rules.**
  - Sticky assignments do not advance the sequence.
  - Pull and manual assignments advance it only when `Count_Pull_As_Hit__c` or `Count_Manual_As_Hit__c` is set. *(H/settings/distribution-settings)*

### Weighting *(H/weighting-and-caps/weighting)*

This applies when `Weighting_Enabled__c` is set and the eligible members' weights are not all equal.

- **Credits.** Each member has `Credit__c`, held in a distributor-scoped state row. (The reference: "Weighting is always calculated within the scope of a distributor".)
- **Candidates.** Members with `Credit__c >= 1`.
- **New cycle.** If no eligible member has credit of 1 or more, start a new cycle: add `weight` to every eligible member's credit, repeating until someone reaches 1. The minimum weight is 0.25, so this takes at most 4 iterations.
- **Pick.** Among the candidates, pick by round robin order. Deduct 1 credit from the member picked.
- **Result.** Weight 2 gives two assignments per cycle; weight 0.5 gives one every 2 cycles; weight 0.25 gives one every 4 cycles.
- **Tag weighting.** When `Weighting_Mode__c = Tag`, a member's weight is the highest weight among their tags in `Tag_Weights__c`, otherwise `Default_Tag_Weight__c`.

### Load Balancing *(H/distribution-methods/algorithms-load-balancing)*

- **What is counted.**
  - For Daily, Weekly and Monthly, the count is Distribution Engine assignments in the period at team or distributor level (`Load_Balancing_Level__c`). Sticky, lookup and pull assignments are included per the settings.
  - For Active, the count is the records owned in Active Status, or all owned records if no Active Status is set. With `Balance_By__c = Field Value`, the score sums the truncated integer value of `Balance_Field__c` instead of counting records.
- **Pick.** Choose the lowest `score / weight` when weighting applies, otherwise the lowest score. Ties break by round robin order.
- **During the run.** The score is incremented in memory so that one bulk run tops members up evenly ("until they all match the team member with the highest … count").

### Lookup Owner *(H/distribution-methods/algorithms-lookup-owner)*

1. Query `Lookup_Object__c WHERE Lookup_Target_Field__c IN :values`, plus the `Lookup Where` conditions, evaluated in Apex.
2. Resolve `Lookup_Assign_Field__c`, which may be a path such as `Account.OwnerId`.
3. Prefer matches whose owner is an active team member. Then sort by the tie-breaker field (default `LastModifiedDate`, newest first).
4. Assign only to team members. Caps are ignored.
5. If there is no match, the record is not assigned and overflows.

Matching is case-insensitive.

### Related Owner *(H/distribution-methods/related-owner)*

- `Related_Field__c` is either a classifier path (`DE.MatchedAccount`, `DE.MatchedContact`, `DE.MatchedLead`) or a lookup path on the record, such as `AccountId`. Its owner must be an active team member.
- If not, `Related_Secondary_Field__c` is tried.
- If neither works, the record is not assigned.

Member filters and caps are not applied.

### Dynamic Owner / Current Owner *(H/distribution-methods/distribution-algorithms)*

These are Trigger distributors only.

- **Dynamic Owner.** Assign to the active user whose Id is held in `Dynamic_Owner_Field__c`.
- **Current Owner.** Keep the owner but write a log so SLAs, tracking and caps apply. *(H/setup-examples/enforce-cap-for-manually-assigned-records)*

### Pull *(H/team-distributors/pull-distributor-settings)*

1. The user must be an active member of the team.
2. Lock the team.
3. Query the source with the sort order. Evaluate team filters, distributor filters, member filters for this user, and caps.
4. Take up to `Pull_Count__c` records. If fewer are available, take all of them.

The user's availability is **not** required, since they are asking for work. This is a design decision (inferred).

## 6. Fallbacks

| Situation | Behaviour |
|---|---|
| Standard distributor: no eligible member | The record stays at its source and overflows to later distributors and teams. It is retried next run, and after N failures it is put on hold. |
| Trigger distributor: no eligible member | Assign to `Default_Owner_Id__c` if it is set; otherwise leave the record unchanged and log `Error`. |
| Lookup or Related Owner: no match | The record overflows. To get a "catch-all", order a Round Robin distributor below it. *(H/territories/territory-distributor)* |
| Territory filter: unknown territory | The record does not match the territory member filter, so it overflows to the catch-all distributor. |

## 7. Persisting an assignment

All assignment paths go through `DE_AssignmentWriter`:

1. **Update the record.**
   - Set the record's assignment field to the assignee.
   - Apply `Field_Updates__c`.
   - For a Field Value source, set `Source_After_Value__c`.
   - Set the tracking fields when present: `DE_Is_Distributed__c = true`, `DE_Last_Distributed__c = now`, `DE_Distribution_Count__c += 1`.
   - Write with `Database.update(records, false)`. Records that fail are logged with Status `Error` and their failed-attempt count is incremented.
2. **Write the log.** Insert `DE_Assignment_Log__c` rows for successful records. Mark the previous `Current__c` logs for those records as not current. Each log carries:
   - Type, method, sticky flag, `Counts_As_Hit__c` and `Sticky_Key__c`
   - Speed-to-assign: `Assigned_At - CreatedDate`, in seconds
   - Balance value
   - The first `Next_SLA_Check__c`, when the distributor has SLAs enabled
   - The decision trace
3. **Update state.** Upsert rotation state, update the team sequence, and update details (reset failures, push the new assignee to `Previous_Assignees__c`, keeping at most 50).
4. **Notify.** Send a Salesforce in-app notification (`DE_Assignment`) and an email when `Send_Email__c` is set. Publish a `DE_Assignment_Event__e` platform event when `Publish_Platform_Events__c` is set.
5. **Object Sync.** When the team has it enabled, child records take the new owner (section 10).

## 8. SLA monitoring and auto reassign *(H/tracking-and-slas/sla, H/tracking-and-slas/auto-reassign)*

### Setting up the checks

- **At assignment.** If the distributor has `SLA_Enabled__c` and the team has active `DE_SLA__c` checkpoints, `Next_SLA_Check__c` is set to the due time of the first checkpoint and `SLA_Status__c = Pending`.
- **Due time.** `DE_ShiftCalendar.addWorkingMinutes(assignedAt, minutes, calendar)`, where the calendar depends on `SLA_Respect_Hours__c`:
  - *Team and Member*: the member's shift, falling back to the team shift.
  - *Team Only*: the team shift.
  - *None*: wall-clock time.
- **Alert types.**
  - Time Checkpoint uses the due time above.
  - Custom Date/Time uses the value of the record field.
  - Continuous Field Monitoring checks every run until `assignedAt + minutes`.

### Each monitor pass

1. **Cancel when no longer relevant.** If the record's assignment field no longer equals the log assignee, or it has left Active Status (when `Apply_Active_Status_To_SLAs__c` is set), set `SLA_Status__c = Cancelled` and clear the next check.
2. **Evaluate due checkpoints.** For each checkpoint that is now due and has not been processed, evaluate its `SLA Condition` conditions ("SLA missed if"). If they are true:
   - Increment `SLA_Missed__c`, set log Status to `SLA Alert`, and notify the assignee (and their manager when `Notify_Manager__c` is set).
   - If `Auto_Reassign__c` is set and checkpoint ≥ `Reassign_From_SLA__c`, reassign the record:
     1. Set the assignment field to `Reassign_To_Id__c`. A queue means the record will be redistributed; a user means a direct assignment, logged as Type `Reassignment`.
     2. Apply `Reassign_Field_Updates__c`.
     3. Set `DE_Is_Reassigned__c` and `DE_Last_Reassigned__c`.
     4. Mark the old log as Reassigned and not current.
     5. Add the previous assignee to tracked assignees.
     6. Remove sticky logs as configured.
     7. If `Toggle_User_Off__c` is set, set the user offline and write an availability event with Source `Auto Reassign`.
3. **Schedule the next check.** Set `Next_SLA_Check__c` to the next checkpoint. When there are none left, mark the status `Met` (no misses) or `Missed`.

**Stamp SLAs.** A checkpoint with `Stamp_Value__c` set only applies to records carrying that stamp.

**Warnings and escalation (user requirement).** These are expressed as ordered checkpoints. For example:

- Checkpoint 1 at 75% of target: notify only (warning).
- Checkpoint 2 at target: notify the manager (breach).
- Checkpoint 3: reassign from SLA 3 to an escalation queue or user.

This matches the reference's escalation pattern: SLA → auto reassign → field update such as Status = Escalated.

## 9. Rejection *(H/teams/assignment-rejection)*

- **Allowed only when:**
  - the record's current log is still current, and
  - the assignment field still equals the log assignee ("Not available if the owner changed after assignment").
- **Team limit.**
  - *Unlimited*.
  - *Manager Only*: requires the `DE_System_Manager` custom permission.
  - *Limited*: count of today's `Rejected` logs for the user must be below `Rejections_Per_Day__c`.
- **Effect.**
  1. Set the assignment field to `Reject_To_Id__c` and apply `Reject_Field_Updates__c`.
  2. Set `DE_Is_Rejected__c` and `DE_Last_Rejected__c`.
  3. Mark the log Status `Rejected` with `Reject_Reason__c` and `Current__c = false`.
  4. Add the user to tracked previous assignees.
  5. Apply the replacement option:
     - *Replace on Usual Assignment*: the user's rotation state gets `Replacement_Credits__c += 1`. The next time they are picked, they receive an extra record before the sequence advances.
     - *Replace as Next Assignment*: their `Last_Sequence__c` is set to 0, putting them at the front of the line.
     - *Don't Replace*: nothing changes.

## 10. Classifier *(H/distribution-classifier/classifier)*

The classifier runs per record, on insert and through the backfill batch, in this order:

1. **Domain and personal email.** The domain is taken from the email (or the website when there is no email). It is flagged personal if it is in `Personal_Domains__c` or the built-in list (gmail.com, yahoo.com, hotmail.com, outlook.com and others).
2. **Territory.** Take active territories for the object, ordered by `Priority__c`. The first one that matches wins, where matching means:
   - the record's country, state or postal code matches the territory's lists, with prefixes `*` and ranges `low..high`; and
   - the extra conditions match.

   **Location fields:**

   | Object | Fields used |
   |---|---|
   | Lead | Country / State / PostalCode |
   | Account | Billing* |
   | Contact | Mailing* |
   | Opportunity, Case | Account.Billing* |

   **Country detection fallbacks:** dial code (+1, +44, +33, +49, +61), then email TLD. Countries are normalised through an alias table (for example US/USA/United States → United States).

   The territory name is written to `DE_Territory__c` or to `Stamp_Field__c`.
3. **Stamps.** For each active stamp group of the object, take stamps in order. A Single group stops at the first matching stamp; a Multiple group applies every matching stamp. Results are stored as `Group:Value` on the details and optionally in `Stamp_Field__c`.
4. **Lead matching** (Leads only). Active rules are applied in order:
   - **Lead to Account:**
     - Email domain, compared with Account Website domains and with the email domains of the account's contacts. Email-domain matches outrank website matches.
     - Normalised company name. Lowercase, strip punctuation and legal suffixes (inc, ltd, llc, plc, gmbh, corp, co, company, limited, corporation), then compare with token-based Jaro-Winkler similarity against `Fuzzy_Threshold__c`.
     - Custom field pair.
   - **Lead to Contact:** exact email.
   - **Lead to Lead:** exact email against other unconverted leads.

   Candidates must pass the `Match Filter` conditions. When several candidates match, the tie-breaker decides. Results: Matched Account, Contact or Lead plus confidence (`Exact` or `Fuzzy 92%`).
5. **Auto conversion and de-duplication.** Take conversion rules by order; the `Is_Default__c` rule runs last. The first rule whose Match condition and filters both pass is applied:
   - **Auto Convert.** `Database.convertLead`, with the matched account and contact when present, opportunity creation per the setting, the owner per `Owner_Source__c`, and the converted status.
   - **De-Duplicate** (only valid with Lead Only Match). Copy values into blank fields of the surviving lead, apply the survivor field update, and merge the incoming lead into the matched lead with `Database.merge`. This is not reversible.
6. Set `Classifier_Status__c = Done`.

## 11. Object Sync *(H/configuration/object-sync)*

- After assignment, for teams with `Object_Sync_Enabled__c` set, each active `DE_Object_Sync__c` whose parent is the team object runs.
- It queries `Child_Object__c WHERE Lookup_Field__c IN :parentIds`, applies the `Sync Filter` conditions, and sets the child `OwnerId` to the parent's new user assignee.
- Children of a parent assigned to a queue are skipped.

## 12. Archive and restore *(H/advanced/auto-archive-feature)*

- **Archive.** A daily `DE_MaintenanceBatch` looks for Lead and Case records that are not distributed, are owned by a queue that is a Standard distributor source, and are older than `Archive_After_Days__c`. It stores the source queue in `DE_Source_Queue__c`, sets the owner to `Archive_Queue_Id__c`, and sets `DE_Is_Archived__c`.
- **Restore.** A before-update trigger handles a user editing an archived record: the owner returns to `DE_Source_Queue__c` and the archived flag is cleared.

## 13. Concurrency and duplicate-processing guarantees

- **Team lock.** Every path that changes rotation state or assigns records locks the team row with `FOR UPDATE` first. Transactions on the same team are serialised; the second one re-reads committed state.
- **No double processing.** Candidate records are re-queried after the lock is taken. A record already moved by a parallel transaction is no longer at the source, so it cannot be assigned twice.
- **Recursion guard.** A static `DE_TriggerHandler.bypass` flag stops the engine's own record updates from re-entering classification or trigger distribution.
- **Concurrent scheduler chains.** The health checker only enqueues the chain when no `DE_SchedulerJob` is queued or processing. A run also exits if it sees another run still active (an `AsyncApexJob` check), so at most one chain runs at a time.
