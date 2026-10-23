# Parity Matrix

The status of every reference feature from [`target-feature-inventory.md`](target-feature-inventory.md).

## Legend

**Evidence**
- **V**: verified on the public AppExchange listing (REA capture).
- **PV**: partially verified. The behaviour is documented in the vendor's public help centre, but the running product was not observed.
- **NA**: not applicable.

**Implementation**
- **Done**: implemented in this repository.
- **Partial**: implemented with documented differences.
- **Gap**: not implemented.

**Tests**
- **Written**: Apex or Jest tests exist.
- **Jest pass**: LWC Jest tests executed and passed in this environment.
- **Not run**: Apex tests have **not** been executed, because no Salesforce org was available. They pass apex-ls semantic checks only.

> No Apex test has been executed and nothing has been deployed. "Written" means test code exists and compiles under the offline apex-ls checker. It does not mean the tests pass.

## Matrix

| ID | Reference feature | Evidence | Implementation (main components) | Impl. | Tests | Remaining gaps | Next action |
|---|---|---|---|---|---|---|---|
| F01 | Distribution teams, execution order, active/inactive, clone, re-order | PV | `DE_Team__c`, `DE_ConfigRepository`, `DE_AdminController`, `deTeams` | Done | __T_ADMIN__ | — | Run tests in an org |
| F02 | Team members | PV | `DE_Team_Member__c`, `deTeamWorkspace` | Done | __T_ADMIN__ | — | Run tests |
| F03 | Queue-to-Queue teams | PV | `Team_Type__c = Queue to Queue`, `DE_Model.Member.isQueue` | Done | __T_ROUTING__ | — | Run tests |
| F04 | Dynamic team members | PV | `DE_DynamicMembers`, `Dynamic Membership` conditions | Done | __T_SERVICES__ | — | Run tests |
| F05 | Distributors (Standard/Pull/Manual/Trigger), overflow | PV | `DE_Distributor__c`, `DE_DistributionRunner`, `DE_DistributionCore` | Done | __T_ROUTING__ | — | Run tests |
| F06 | Sources (queue, user, field value with ready/after values) | PV | `DE_DistributionRunner.atSource`, `DE_RecordQuery.sourceCandidates` | Done | __T_ROUTING__ | — | Run tests |
| F07 | Assign to any user lookup field | PV | `Assignment_Field__c`, `DE_AssignmentWriter` | Done | __T_ROUTING__ | — | Run tests |
| F08 | Field filters: operators, logic, relative dates, paths | PV | `DE_Conditions`, `DE_Logic`, `deConditionBuilder` | Done | __T_UNIT__; Jest pass | — | Run tests |
| F09 | Custom sort order | PV | `Sort_Order__c`, `DE_RecordQuery` | Done | __T_ROUTING__ | — | Run tests |
| F10 | Member filters (tags, dynamic tags, territory, stamps, selected, exclude field) | PV | `DE_DistributionCore.memberFiltersPass`, `DE_Agent__c.Tags__c`, `deTags` | Done | __T_ROUTING__ | — | Run tests |
| F11 | Round robin (team or distributor level) | PV | `DE_RotationService` (`DE_Rotation_State__c` sequence) | Done | __T_ROUTING__ | Tie-break for never-assigned members is inferred (name order) | Compare with the reference in an org |
| F12 | Load balancing (daily, weekly, monthly, active, field value) | PV | `DE_LoadBalancer`, `DE_CapService.ownedCounts` | Done | __T_ROUTING__ | Tie-break inferred (round robin order) | Run tests |
| F13 | Weighting 0.25–4, individual or tag | PV | `DE_RotationService.pickWeighted`, `DE_ConfigRepository.memberWeight` | Partial | __T_ROUTING__ | Cycle algorithm inferred from documented examples | Run tests |
| F14 | Caps (periods, custom rolling, active, criteria, by tag, distributor caps) | PV | `DE_Cap__c`, `DE_CapService` | Done | __T_UNIT__; __T_ROUTING__ | — | Run tests |
| F15 | Sticky assignment (field, period, level, retain, sticky-only, cap behaviour) | PV | `DE_StickyService`, `Sticky_Key__c` on logs | Done | __T_ROUTING__ | — | Run tests |
| F16 | Lookup owner with tie-breaker | PV | `DE_OwnerResolver` | Done | __T_ROUTING__ | — | Run tests |
| F17 | Related owner (matched account etc.) | PV | `DE_OwnerResolver`, `DE_LeadMatcher` | Done | __T_ROUTING__ | — | Run tests |
| F18 | Dynamic owner, current owner (trigger) | PV | `DE_OwnerResolver`, `DE_TriggerDistribution` | Done | __T_ROUTING__ | — | Run tests |
| F19 | Pull ("get next") 1–100 | PV | `DE_PullService`, `deWidget` | Done | __T_SERVICES__; Jest pass | Pull ignores availability (documented choice) | Run tests |
| F20 | Manual distribution | PV | `DE_ManualAssignService`, `deRecordDetail` | Done | __T_SERVICES__ | — | Run tests |
| F21 | Trigger distribution | PV | `DE_TriggerDistribution`, `DE_Trigger_Distribution__c` | Done | __T_ROUTING__ | — | Run tests |
| F22 | Flow and Apex API | PV | `DE_FlowActions`, `DE_ToggleUsersAction`, `DE_RejectRecordAction`, `DE_Api` | Done | __T_CONTROLLERS__ | API surface is independent (the reference's names are not used) | Run tests |
| F23 | Scheduler (~1 min, 500 per run), health checker | PV | `DE_SchedulerJob`, `DE_HealthChecker`, `DE_Settings` | Done | __T_CONTROLLERS__ | — | Run tests |
| F24 | On hold and automatic retry | PV | `DE_DistributionRunner.recordFailures`, `DE_Record_Detail__c.On_Hold_Until__c` | Partial | __T_ROUTING__ | Thresholds unknown; configurable (defaults 10 failures, 60 min) | Run tests |
| F25 | Post-assignment field updates, tracking fields, email | PV | `DE_FieldUpdates`, `DE_AssignmentWriter`, `DE_Notifier` | Done | __T_ROUTING__; __T_SERVICES__ | Email content is our own plain-text summary | Run tests |
| F26 | Role assignment (team roles) | PV | — | Gap | — | Not implemented | Future: AccountTeamMember / CaseTeamMember / OpportunityTeamMember writer |
| F27 | Team hours, member hours | PV | `DE_ShiftCalendar`, `DE_AvailabilityService` | Done | __T_UNIT__; __T_ROUTING__ | — | Run tests |
| F28 | Shifts (3 blocks/day, overnight) | PV | `DE_Shift__c`, `DE_ShiftCalendar`, `deAvailability` | Done | __T_UNIT__ | — | Run tests |
| F29 | Holiday regions | PV | `DE_Holiday__c`, `DE_AvailabilityService.holidayFor` | Done | __T_ROUTING__ | — | Run tests |
| F30 | Out of office (users and queues; managers for others) | PV | `DE_Out_Of_Office__c`, `DE_AvailabilityController` | Done | __T_ROUTING__; __T_CONTROLLERS__ | — | Run tests |
| F31 | Availability toggle (reasons, timers, start/end of day, history) | PV | `DE_AgentService`, `DE_Availability_Event__c`, `deWidget` | Done | __T_SERVICES__; Jest pass | — | Run tests |
| F32 | Availability evaluation order and overrides | PV | `DE_AvailabilityService.unavailableReason` | Done | __T_ROUTING__ | — | Run tests |
| F33 | Shift planner (12 weeks) | PV | — | Gap | — | Not implemented | Future: dated shift assignments |
| F34 | Calendar integration (Events create OOO) | PV | `DE_CalendarSync`, `DE_EventTrigger` | Done | __T_SERVICES__ | — | Run tests |
| F35 | Territories | PV | `DE_Territory__c`, `DE_TerritoryClassifier` | Partial | __T_CLASSIFIER__ | List-based instead of the map UI | Run tests |
| F36 | Lead matching | PV | `DE_Matching_Rule__c`, `DE_LeadMatcher`, `DE_TextMatch` | Partial | __T_CLASSIFIER__; __T_UNIT__ | Built-in matcher instead of Salesforce Duplicate Rules | Run tests |
| F37 | Auto-conversion and de-duplication | PV | `DE_Conversion_Rule__c`, `DE_LeadConversion` | Done | __T_CLASSIFIER__ | — | Run tests |
| F38 | Stamp groups (custom classification) | PV | `DE_Stamp_Group__c`, `DE_Stamp__c`, `DE_StampClassifier` | Done | __T_CLASSIFIER__ | — | Run tests |
| F39 | Delay filters | PV | Distributor filter on `CreatedDate` with a relative value | Partial | __T_UNIT__ | No dedicated UI | Optional |
| F40 | Backfill | PV | `DE_BackfillBatch`, `deClassifier` | Done | __T_CLASSIFIER__ | — | Run tests |
| F41 | Action tracking | PV | `DE_ActionTracking`, `DE_TaskTrigger` | Done | __T_SERVICES__ | — | Run tests |
| F42 | SLAs (checkpoints, continuous, custom date/time, stamp, active status) | PV | `DE_SLA__c`, `DE_SlaService` | Done | __T_SERVICES__ | Continuous-monitoring frequency = scheduler interval (inferred) | Run tests |
| F43 | Auto reassign, tracked assignees | PV | `DE_SlaService`, `Previous_Assignees_Tracked__c` | Done | __T_SERVICES__ | — | Run tests |
| F44 | Rejection (limits, reasons, reject-to, replacement) | PV | `DE_RejectionService`, `deWidget` | Done | __T_SERVICES__ | — | Run tests |
| F45 | Notifications (email, in-app, platform events, Slack) | PV | `DE_Notifier`, `DE_Assignment_Event__e`, `DE_Assignment` notification type | Partial | __T_SERVICES__ | Slack not implemented | Future |
| F46 | Object sync | PV | `DE_Object_Sync__c`, `DE_ObjectSyncService` | Done | __T_SERVICES__ | — | Run tests |
| F47 | Auto-archive and restore | PV | `DE_ArchiveService`, `DE_MaintenanceBatch` | Done | __T_SERVICES__ | — | Run tests |
| F48 | Distribution logs, retry / retry all | PV | `DE_Assignment_Log__c`, `deLogs`, `DE_ConsoleController` | Done | __T_CONTROLLERS__ | — | Run tests |
| F49 | Monitoring, run logs, health checker | PV | `DE_Run_Log__c`, `DE_RunLogger`, `DE_HealthChecker`, `deConsole` | Done | __T_CONTROLLERS__ | — | Run tests |
| F50 | Distribution console | PV | `deConsole`, `DE_ConsoleController` | Done | __T_CONTROLLERS__ | — | Run tests |
| F51 | Analytics and team performance | PV | `deAnalytics`, `DE_ConsoleController.getAnalytics` | Partial | __T_CONTROLLERS__; Jest pass | "Distribution Fidelity" metric not defined publicly; omitted | Run tests |
| F52 | Reports and dashboard | PV | 3 report types, 9 reports, *Distribution Engine Overview* dashboard | Done | Not testable offline (metadata) | Dashboard is dynamic (LoggedInUser); EE limits dynamic dashboards | Deploy and verify rendering |
| F53 | Change history | PV | Field History Tracking on 13 configuration objects (team, member, distributor, SLA, agent, OOO, holiday, shift and others), plus `DE_Availability_Event__c`, `DE_Assignment_Log__c` and `DE_Run_Log__c` | Partial | — | No in-app change-history viewer; history is shown in the standard related lists | Future: history tab in `deTeamWorkspace` |
| F54 | Simulator, distributor test, distribution viewer | PV | `DE_Simulator`, `deSimulator`, decision trace | Done | __T_CONTROLLERS__ | — | Run tests |
| F55 | Widget (utility bar) | PV | `deWidget`, `DE_WidgetController`, `DE_Utility_Bar` flexipage | Done | __T_CONTROLLERS__; Jest pass | — | Run tests |
| F56 | Record detail component | PV | `deRecordDetail`, `DE_RecordDetailController` | Done | __T_CONTROLLERS__ | — | Run tests |
| F57 | Permission sets and team manager scoping | PV | 4 custom permissions, 4 permission sets, `DE_Permissions` | Done | __T_CONTROLLERS__ | — | Deploy and assign |
| F58 | Settings | PV | `DE_Settings__c`, `DE_Settings`, `deSettings` | Done | __T_CONTROLLERS__ | — | Run tests |
| F59 | Configuration export and import (JSON) | PV | `DE_ConfigTransfer` | Done | __T_CONTROLLERS__ | Format is our own (not compatible with the reference's files) | Run tests |
| F60 | Supported objects (Lead, Case, Opportunity, Account, Contact, custom) | V | Triggers on 5 standard objects plus `DE_TriggerHandler` one-liner for custom objects | Done | __T_ROUTING__ | Task routing not included | Run tests |
| F61 | Mobile | PV | Widget exposed for the utility bar; the app supports the Small form factor | Partial | — | Not verified on a device | Verify on mobile |
| F62 | Licensing per member | PV | — | NA | — | Independent build | — |
| F63 | Personas / custom team manager | PV | — | Gap | — | Four fixed roles only | Future |
| F64 | Third-party integrations (Slack, InsideSales, Pardot) | PV | — | Gap | — | Not implemented | Future |

## Summary

__SUMMARY__
