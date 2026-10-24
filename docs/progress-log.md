# Progress Log

A short record of what was done, how it was checked, and what remains. Times are UTC.

## Validation environment (applies to every entry)

- **No Salesforce org was available.**
  - Nothing has been deployed.
  - No Apex test has been executed.
  - Statements like "tests written" mean the test code exists and passes the offline checks below. They do not mean the tests pass in an org.
- **Offline checks used:**
  - Salesforce CLI `sf project convert source`: metadata structure.
  - apex-ls 6.4.0 `CheckForIssues -d warnings`: semantic type checking of Apex against the project's own metadata and the platform's standard types. We confirmed that it flags unknown fields and methods by planting deliberate errors.
  - PMD 7.7.0: Apex security, error-prone, performance and best-practice rules.
  - Prettier with `prettier-plugin-apex`: formatting.
  - ESLint with the LWC config.
  - The `@lwc/template-compiler`: template compile.
  - A template-reference check: every `{binding}` in a template resolves to the component.
  - An LWC↔Apex check: imported Apex methods exist, are `@AuraEnabled`, and the parameter names match.
  - Jest via `sfdx-lwc-jest`: LWC unit tests. These are the only tests actually executed.

## 2026-10-23: evidence and specification

- Captured the AppExchange listing with REA:
  - Evidence was captured for the overview, the DOM, and the tab screenshots.
  - The shadow DOM is not captured; this is recorded as an REA unknown.
- Gathered behaviour from the vendor's public help centre.
- Wrote the six specification documents in `docs/`.
  - Each feature is labelled verified or partially verified.
  - Inferred behaviour is marked as inferred.

## 2026-10-23: implementation in priority order

1. **P1 core routing and P2 services** (`cc4d864`):
   - Teams, distributors, conditions, round robin, weighting, load balancing, caps, sticky assignment, owner methods.
   - Availability, on hold, the scheduler, and trigger distribution.
   - The classifier: territories, stamps, matching, conversion.
2. **P3/P4 UI and API** (`2474204`, `35f9785`):
   - UI controllers, simulator, API, Flow actions, configuration transfer.
   - Lightning UI: tabs, widget, record component.
   - App, permission sets, reports, dashboard.
3. **Tests** (`ac147ea` → `0869e4e`):
   - Shared factory plus 38 Apex test classes, about 300 methods.
     - They were written in five parallel slices, which found and fixed three engine bugs:
       - SOQL filtered on a long-text field.
       - Matched-record fields were not loaded for classifier conditions.
       - Date values were compared as datetimes.
     - Not executed.
   - 21 Jest tests: passed.

## 2026-10-23: reference component inventory (CSV, 2,597 rows)

- `1f56df0`:
  - Generated the inventory, dependency map, replication matrix and summary from `docs/evidence/reference-package-components.csv`. The generator is `scripts/metadata/gen_matrix.py`.
  - Added help-centre evidence for components that only appear in the CSV.
- `65c8270`: data model and metadata for the gaps:
  - 15 new objects and about 60 new fields.
  - Page layouts for every object, a compact layout, and a list view.
  - A Lightning home page.
  - Visualforce email templates and components, email alerts, and four record-triggered email flows.
  - Two more permission sets and a report type.
- `3982ebf`, assignment pipeline:
  - Role assignment.
  - Rejection log.
  - Per-action tracking.
  - Email through flows.
  - Reassignment retries.
  - Campaign filter.
- `55665d0`, availability:
  - Holiday regions.
  - Team manager records.
  - Shift planner.
  - Calendar OOO sync.
- `6dac58c`, monitoring:
  - Change history.
  - Classifier and sync logs.
  - Domain index.
  - Admin alerts.
  - Platform cache.

## Open items

- **Run the tests in an org.** Deploy to a scratch org and run `RunLocalTests`. Each test-writing pass recorded assertions that depend on org configuration, for example:
  - State and Country picklists.
  - Lead duplicate rules.
  - Case picklist values.
  - Team selling enabled.
  - The converted lead status.
- **Unconfirmed deploy behaviour.** We have not confirmed that a platform cache partition with zero capacity deploys in every edition.
- **Dashboard type.** The dashboard is dynamic (`LoggedInUser`), and Enterprise edition limits the number of dynamic dashboards.
- **Blocked:** Slack integration items, which need the vendor's Slack app and middleware.
- **Trademark.** The product name matches the reference vendor's product. Rename the labels before distributing outside your own org.
