# Distribution Engine by NC Squared (independent rebuild)

A Salesforce-native lead, case and opportunity routing application, written in Apex and Lightning Web Components. It reproduces the externally documented behaviour of the AppExchange product *Distribution Engine* (listing `a0N30000009x4YAEAY`). It is a clean-room design: none of the reference package's code, metadata or internal data model was used. See [`docs/evidence-and-gaps.md`](docs/evidence-and-gaps.md).

> **Name and trademark.** The working name matches the reference product's name and vendor. Rename the app label, package name and tab labels before distributing it outside your own org. See [Renaming](#renaming).

## What is in the box

| Area | Contents |
|---|---|
| Routing engine | Teams, then ordered distributors: Standard, Pull, Manual and Trigger types, with Queue, User or Field Value sources. Methods: round robin, load balancing, lookup owner, related owner, dynamic owner and current owner. Also weighting, caps, sticky assignment, filters, member filters, availability, on-hold and retry. |
| Availability | Shifts with team and member hours, holiday regions, out of office, the online/offline toggle with reasons and timers, start-of-day and end-of-day reset, and calendar Events creating OOO. |
| Classifier | Territories, stamp groups, lead-to-account matching, auto-conversion and de-duplication, and a backfill batch. |
| Tracking | Action tracking (time to action), SLA checkpoints, auto reassign, rejection, object sync, auto-archive and restore. |
| UI | Tabs: Distribution Console, Teams, Availability, Tags, Classifier, Sync, Logs, Analytics and Settings. Also a utility-bar widget, the record detail component and the simulator. |
| Automation API | Flow actions (*DE Distribute Records*, *DE Toggle Users*, *DE Reject Record*) and the global Apex class `DE_Api`. |
| Reporting | Report types on Assignment Logs, Availability Events and Run Logs, nine reports, and the *Distribution Engine Overview* dashboard. |
| Security | Custom permissions plus four permission sets: Admin, System Manager, Team Manager and User. |

Design documents are in [`docs/`](docs). Feature-by-feature status is in [`docs/parity-matrix.md`](docs/parity-matrix.md).

## Deploy

Requirements: Sales Cloud or Service Cloud, Enterprise edition or higher, and API version 66.0.

```bash
# scratch org
sf org create scratch -f config/project-scratch-def.json -a de -d -y 7
sf project deploy start -o de
sf apex run test -o de -l RunLocalTests -w 30 -r human

# or an existing sandbox
sf project deploy start -o <alias> -l RunLocalTests
```

## Set up

1. **Assign permission sets.** `sf org assign permset -n DE_Admin -o de`. Then give each agent `DE_User`, team leads `DE_Team_Manager`, and operations staff `DE_System_Manager`.
2. **Start the scheduler.** As an admin, open *Distribution Console*. On the *Application Monitoring* tab, click **Start**. This also schedules the hourly health checker. Or run this anonymous Apex:
   ```apex
   DE_SchedulerJob.start();          // self-chaining queueable, runs every Scheduler_Interval_Minutes__c (default 1)
   DE_HealthChecker.schedule(60);    // restarts the chain if it ever stops
   ```
3. **Create a team.** In *Distribution Teams*, choose an object. Add members. Add a **Standard** distributor whose source is the queue where new records land. Choose a method and activate the team.
4. **Add the widget.** It ships in the *Distribution Engine by NC Squared* app's utility bar. To add it to other apps, use App Manager → Utility Items → *DE Widget*.
5. **Add the record component (optional).** Put *DE Record Detail* on Lead, Case or Opportunity record pages for history, assign, reject and test actions.
6. **Assignment notifications.** These use the custom notification type `DE_Assignment`. Email notifications use the running user's org-wide email settings.

### Routing a custom object

Add a one-line trigger, and give the object a queue:

```apex
trigger Project_DE on Project__c (before update, after insert) {
    DE_TriggerHandler.handle('Project__c');
}
```

Trigger distributors also need a checkbox named `DE_Trigger_Distribution__c` on the object. Field updates use `DE_Is_Distributed__c` and the other `DE_*` tracking fields if they exist. Every one of these fields is optional.

### Real-time widget updates

The widget subscribes to `/event/DE_Assignment_Event__e` through `lightning/empApi`. If streaming is unavailable, it falls back to polling every 15 seconds. To turn events off, use *Settings → Publish platform events*.

## Development

```bash
npm install
npm run lint              # ESLint on LWC
npm run test:unit         # Jest (sfdx-lwc-jest)
npx prettier --check "force-app/**/*.{cls,trigger,js,html,css}"
sf project convert source -r force-app -d /tmp/mdapi   # metadata sanity check
```

Conventions:
- Everything uses the `DE_` prefix.
- Engine classes run `without sharing`, because routing is a system process.
- Controllers are `with sharing`, check custom permissions, and do DML in `USER_MODE`.
- All DML uses the three-argument `Database.*` form.

## Renaming

The app label is in `applications/DE_Distribution_Engine.app-meta.xml`. The package name is in `sfdx-project.json`. Tab labels are in `tabs/*.tab-meta.xml`. Permission set labels are in `permissionsets/*.permissionset-meta.xml`. API names do not depend on the product name, so renaming is label-only.
