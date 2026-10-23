# Target Feature Inventory

Reference application: **Distribution Engine** by NC Squared (AppExchange listing `a0N30000009x4YAEAY`, v22.4.0, last updated 10/05/2026).
This inventory lists every feature we discovered and the priority we gave it for **Distribution Engine by NC Squared**, our independent Salesforce-native build.

Every feature has an ID (`F01`…`F64`). The same IDs are used in all the other documents in `docs/`.

## Evidence keys

| Key | What it is |
|---|---|
| **L** | AppExchange listing. Captured with REA `capture_browser_scenario`. Evidence `ev_9e5476b4…` (overview), `ev_10eb8622…` (tab DOM) and `ev_4f65011b…` (tab screenshots). Screenshots are in `docs/evidence/`. |
| **H/…** | Vendor public knowledge base article `https://help.distributionengine.com/<path>`. Read in full during investigation. |
| **M** | Vendor marketing site `distributionengine.com`. Lower confidence. |
| **I** | Our inference. |

## Confidence levels

- **Verified**: observed directly by REA on the live listing.
- **Partially verified**: stated explicitly in the vendor's own documentation, but not observed running. No authorised org was available (see `evidence-and-gaps.md`).
- **Inferred**: deduced from evidence, or a design decision on our part.

## Priority levels

- **P1**: core routing.
- **P2**: territory, weighting, workload, availability, case routing, matching.
- **P3**: SLA, escalation, reassignment, history, monitoring.
- **P4**: administration UI, reports, permissions and other modules.
- **N/A**: not applicable to an independent build.

## A. Distribution core (Teams → Distributors)

| ID | Feature | Evidence | Confidence | Priority |
|---|---|---|---|---|
| F01 | **Distribution Teams.** One object per team (fixed after creation). Execution order runs top to bottom. Teams can be active or inactive, cloned and re-ordered. | H/teams/distribution-teams, H/team-settings-page/team-settings | Partially verified | P1 |
| F02 | **Team members.** Users who receive assignments; add or remove them, active or inactive. | H/teams/adding-and-removing-team-members | Partially verified | P1 |
| F03 | **Queue-to-Queue (Q2Q) teams.** Members are queues. | H/advanced/q-2-q-teams | Partially verified | P2 |
| F04 | **Dynamic team members.** Membership comes from User field rules. | H/teams/dynamic-team-members | Partially verified | P4 |
| F05 | **Distributors.** Ordered rules in four types (Standard, Pull, Manual, Trigger). A record that is not assigned overflows to the next distributor. | H/team-distributors/distributors, H/team-distributors/distributor-types | Partially verified | P1 |
| F06 | **Sources.** Queue, holding user or field value (ready value and after value). | H/team-distributors/distributor-sources | Partially verified | P1 |
| F07 | **Assignment field.** Assign to any user lookup field, not only OwnerId. | H/team-settings-page/assign-to-field | Partially verified | P2 |
| F08 | **Team and distributor field filters.** 15+ case-insensitive operators, AND/OR logic, relative dates, relationship paths, stamp and matched-account filters. | H/team-distributors/filters | Partially verified | P1 |
| F09 | **Custom sort order.** Multiple fields, each ascending or descending. | H/team-distributors/distributor-sort-order | Partially verified | P2 |
| F10 | **Team member filters.** Static and dynamic tags, territory, stamps, selected members, and an "exclude members" field. | H/team-distributors/team-member-filters | Partially verified | P2 |
| F11 | **Round robin.** Least-recently-assigned eligible member goes first; team-level or distributor-level scope. | H/distribution-methods/algorithms-round-robin, L ("Round robin lead routing to keep distribution fair") | Partially verified | P1 |
| F12 | **Load balancing.** Daily, weekly, monthly or active-status count, or field value; team or distributor level. | H/distribution-methods/algorithms-load-balancing, L ("Match leads by skill, workload or territory") | Partially verified | P2 |
| F13 | **Weighting.** Individual weights or tag weights from 0.25 to 4, applied as a ratio per cycle. | H/weighting-and-caps/weighting, L ("Weighted round robin routing") | Partially verified | P2 |
| F14 | **Caps.** Team-level caps (up to 3 periods, can vary by tag) and distributor-level caps. Periods: hourly, half-hourly, daily, weekly, monthly, custom rolling, active and criteria. | H/weighting-and-caps/caps, H/weighting-and-caps/capping-by-tags | Partially verified | P2 |
| F15 | **Sticky assignment.** Match field, period and level; retain options; sticky-only mode; cap behaviour. | H/distribution-methods/distribution-algorithms-sticky | Partially verified | P2 |
| F16 | **Lookup owner.** Assign to the owner of a matching record on another object, with a tie-breaker. | H/distribution-methods/algorithms-lookup-owner | Partially verified | P2 |
| F17 | **Related owner.** Assign to the owner of the matched account, contact or lead, or another related record. | H/distribution-methods/related-owner, L ("Account-based assignment for ABM") | Partially verified | P2 |
| F18 | **Dynamic owner and current owner.** Trigger-only methods. | H/distribution-methods/distribution-algorithms | Partially verified | P3 |
| F19 | **Pull distribution ("get next").** Pull 1–100 records from the widget. | H/team-distributors/pull-distributor-settings | Partially verified | P2 |
| F20 | **Manual distribution.** A manager picks the member from the record page; allowed even at cap; can be treated as a rejection. | H/team-distributors/manual-distributor-settings | Partially verified | P3 |
| F21 | **Trigger distribution.** Immediate on update via a flag checkbox; no retry; default owner. | H/team-distributors/trigger-distributor-settings, H/settings/trigger-settings | Partially verified | P2 |
| F22 | **Flow and Apex API.** Distribute records, toggle users, reject records. | H/api/*, H/flow-examples/assign-on-action | Partially verified | P3 |
| F23 | **Scheduler.** Runs about every minute, 500 records per run, with a Health Checker. | H/settings/advanced-settings, H/settings/distribution-settings | Partially verified | P1 |
| F24 | **On hold.** Records that fail repeatedly are held, then retried automatically. | H/warnings-and-errors/distributorfailures, H/logs/distribution-logs | Partially verified | P3 |
| F25 | **Post assignment.** Field updates, Is distributed / Last distributed / count fields, email notification. | H/teams/post-assignment, H/installation/whats-in-the-package | Partially verified | P1 |
| F26 | **Role assignment.** Account, Case or Opportunity team roles. | H/team-distributors/distributor-saleforce-teams | Partially verified | P4 |

## B. Availability

| ID | Feature | Evidence | Confidence | Priority |
|---|---|---|---|---|
| F27 | **Team distribution hours and member hours.** Member hours override team hours. | H/hours/team-hours, H/hours/team-member-distribution-hours | Partially verified | P2 |
| F28 | **Shifts.** Reusable patterns in a timezone, up to 3 blocks per day, overnight blocks. | H/distribution-availability/shift-hours | Partially verified | P2 |
| F29 | **Holiday regions and regional holidays.** A holiday shuts down the whole team. | H/distribution-availability/regional-holidays, H/distribution-availability/holiday-regions | Partially verified | P2 |
| F30 | **Out of office.** For users and queues; managers can enter it for others. | H/distribution-availability/distribution-ooo, L ("Skip unavailable agents automatically") | Partially verified | P2 |
| F31 | **Availability toggle.** Reasons, timer toggles, start-of-day and end-of-day reset, history. | H/distribution-availability/user-availability-toggle | Partially verified | P2 |
| F32 | **Availability evaluation order.** Holidays, then OOO, then hours, then toggle; "assign if unavailable" and "assign if offline" overrides. | H/distribution-methods/algorithms-round-robin | Partially verified | P2 |
| F33 | **Shift planner.** Plan up to 12 weeks ahead. | H/hours/shift-planner | Partially verified | P4 |
| F34 | **Calendar integration.** Events create OOO. | H/settings/calendar-integration | Partially verified | P4 |

## C. Classify (data quality and matching)

| ID | Feature | Evidence | Confidence | Priority |
|---|---|---|---|---|
| F35 | **Territories.** Country, state and postcode territories in order; stamp records. | H/territories/*, L ("Territory assignment by geography, zip code & region") | Partially verified | P2 |
| F36 | **Lead matching.** Lead to account, contact or lead; email domain; fuzzy company name; personal domains excluded; tie-breaker. | H/matching/*, L ("Automatic lead-to-account matching") | Partially verified | P2 |
| F37 | **Lead auto-conversion and de-duplication rules.** | H/auto-conversion/*, L ("De-duplicate leads before routing") | Partially verified | P2 |
| F38 | **Custom classification (stamp groups).** | H/custom-classification/* | Partially verified | P3 |
| F39 | **Delay filters.** | H/distribution-classifier/delay-filters | Partially verified | P4 |
| F40 | **Backfill wizard.** Classify existing records. | H/distribution-classifier/backfill | Partially verified | P4 |

## D. Track (SLA, escalation, reassignment)

| ID | Feature | Evidence | Confidence | Priority |
|---|---|---|---|---|
| F41 | **Action tracking.** Time to action, respect hours, auto-action from activities. | H/tracking-and-slas/action-tracking, L ("speed to lead") | Partially verified | P3 |
| F42 | **SLAs.** Up to 3 time checkpoints; continuous monitoring; custom date/time; stamp SLAs; active status. | H/tracking-and-slas/sla, L ("Track and enforce SLAs on every case") | Partially verified | P3 |
| F43 | **Auto reassign.** Reassign from SLA n; reassign to; field updates; toggle the user off; tracked previous assignees. | H/tracking-and-slas/auto-reassign, H/tracking-and-slas/tracked-assignees, L ("Auto-escalate overdue or breached cases") | Partially verified | P3 |
| F44 | **Assignment rejection.** Limits, reasons, reject-to, replacement options. | H/teams/assignment-rejection | Partially verified | P3 |
| F45 | **Notifications.** Email, in-app, platform events, Slack. | H/emails/*, H/integrations/slack-* | Partially verified | P3 |

## E. Operate, monitor and administer

| ID | Feature | Evidence | Confidence | Priority |
|---|---|---|---|---|
| F46 | **Object sync.** Child records follow the parent's new owner. | H/configuration/object-sync | Partially verified | P4 |
| F47 | **Auto-archive and restore.** | H/advanced/auto-archive-feature | Partially verified | P4 |
| F48 | **Distribution logs.** Statuses and filters; Retry and Retry all. | H/logs/*, L ("Full routing audit trail on every record") | Partially verified | P3 |
| F49 | **Application monitoring, run logs and Health Checker.** | H/consoles/application-monitoring | Partially verified | P3 |
| F50 | **Distribution console.** Today's distributions, sources, availability calendar. | H/consoles/* | Partially verified | P4 |
| F51 | **Analytics charts and team performance metrics.** | H/managing-and-monitoring/distribution-analytics, H/teams/team-performance | Partially verified | P4 |
| F52 | **Packaged reports and dashboard.** | H/managing-and-monitoring/distribution-engine-dashboard | Partially verified | P4 |
| F53 | **Change history.** For teams, members, distributors and availability. | H/managing-and-monitoring/change-history | Partially verified | P4 |
| F54 | **Assignment simulator, distributor test tool and distribution viewer.** | H/assignmentsimulator/*, H/team-distributors/distributor-test-new, H/teams/distribution-process-view | Partially verified | P4 |
| F55 | **Widget (utility bar).** Toggle, pull, assigned to me, missed SLAs, toasts. | H/de-widget/* | Partially verified | P2 |
| F56 | **Record detail component.** History, test, assign, reject. | H/de-widget/lightning-inline | Partially verified | P3 |
| F57 | **Permission sets.** Admin, System Manager, Team Manager, User; team manager scoping. | H/permissions/* | Partially verified | P4 |
| F58 | **Distribution settings.** Scheduler, retention, tracked assignees, reasons and similar. | H/settings/distribution-settings | Partially verified | P4 |
| F59 | **Export and import of configuration (JSON).** | H/settings/import-export | Partially verified | P4 |
| F60 | **Supported objects.** Lead, Case, Opportunity, Account, Contact, Task and custom objects. | L ("Route Leads, Cases, Contacts, Accounts, Opportunities and even Custom Objects"), H/getting-started/distribution-engine-overview | Verified (L) | P1 |
| F61 | **Mobile support.** Widget on the Salesforce mobile app. | H/de-widget/widget-mobile, H/advanced/salesforce-mobile | Partially verified | P4 |
| F62 | **Licensing per team member.** | H/installation/licences | Partially verified | N/A (independent build, no ISV licensing) |
| F63 | **Personas and the custom team manager.** | H/permissions/persona-management | Partially verified | P4 |
| F64 | **Third-party integrations.** Slack, InsideSales, Pardot. | H/integrations/*, H/advanced/pardot | Partially verified | P4 |

## Listing-level facts (Verified with REA)

Source: `docs/evidence/appexchange-specs.png`, `appexchange-overview.png`, `appexchange-resources.png` and `appexchange-support.png`.

- **Package contents.** 92 custom objects, 9 custom tabs, 1 custom app, 3 global Lightning components, 0 App Builder and 0 Community Builder components.
- **Compatibility.**
  - Required products: Sales Cloud and Service Cloud.
  - Compatible products: Revenue Cloud, Financial Services Cloud and Education Cloud.
  - Editions: Enterprise and Unlimited.
  - Language: English.
- **Vendor.** NC Squared, London, UK, 25 employees. Listed on 02/06/2013.
- **Positioning claims.**
  - "No-code automated lead routing"
  - "Round robin lead routing to keep distribution fair"
  - "Assign based on any Salesforce field"
  - "Account-based assignment for ABM"
  - "Automate case routing by priority, skill, availability"
  - "Auto-escalate overdue or breached cases"
  - "Define and manage sales territories inside Salesforce"
  - "Works with Salesforce Enterprise Territory Management"
  - "Full routing audit trail on every record"
  - "Auto-reassign overdue records"
  - "Monitor SLAs, response times and speed to lead in real time"
  - "Omni-channel routing … with availability-aware assignment"
  - "shift-based assignment"
- **Resources.** Install Guide, Setup Guide, a whitepaper, 5 comparison datasheets and 6 case studies. Only link titles were captured; the documents themselves were not opened.
