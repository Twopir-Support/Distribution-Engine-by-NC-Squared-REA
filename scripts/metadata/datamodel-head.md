# Data Model

This is an independent data model for **Distribution Engine by NC Squared**.

- **API prefix.** Every component uses the `DE_` prefix. There is no namespace, so the project deploys to any org.
- **Not a copy of the reference.** The vendor's internal model is not public. The only parts the listing and documentation reveal are the `n2de__Distribution_Log__c` and `Distribution Engine Details` objects, plus the fields packaged onto standard objects. We designed our own model to reproduce the documented *behaviour*. Names and structures are ours.

> The field tables below are generated from `force-app/main/default/objects`, so they match the deployable source exactly.

## Entity overview

```
DE_Team__c (Distribution Team) ──< DE_Team_Member__c >── User | Queue
   │  ├──< DE_Distributor__c ──< DE_Condition__c (Distributor Filter / Member Filter / Lookup Where)
   │  │                      └──< DE_Cap__c (distributor-level)
   │  ├──< DE_Condition__c (Team Filter, Dynamic Membership)
   │  ├──< DE_Cap__c (team-level) ──< DE_Condition__c (Cap Criteria)
   │  ├──< DE_SLA__c (checkpoints 1-3) ──< DE_Condition__c (SLA Condition)
   │  ├──< DE_Rotation_State__c (round robin sequence and weighting credit, per scope + member)
   │  └── Team_Hours__c → DE_Shift__c <── DE_Team_Member__c.Member_Hours__c
DE_Holiday__c (by Region; matched to DE_Team__c.Holiday_Region__c)
DE_Out_Of_Office__c → User | Queue        DE_Agent__c (toggle and tags) → User ──< DE_Availability_Event__c
Classifier:  DE_Territory__c ──< DE_Condition__c (Territory)
             DE_Stamp_Group__c ──< DE_Stamp__c ──< DE_Condition__c (Stamp)
             DE_Matching_Rule__c ──< DE_Condition__c (Match Filter)
             DE_Conversion_Rule__c ──< DE_Condition__c (Conversion Filter)
             DE_Record_Detail__c (one per routed record: territory, stamps, matches, hold state, previous assignees)
Operate:     DE_Object_Sync__c ──< DE_Condition__c (Sync Filter)
Audit:       DE_Assignment_Log__c (Distribution Log)   DE_Run_Log__c (engine runs)   DE_Assignment_Event__e (platform event)
Settings:    DE_Settings__c (hierarchy custom setting)
```

## Design notes

- **One generic condition object.** `DE_Condition__c` is shared by every feature that needs a "Field / Operator / Value" filter row. `Purpose__c` together with the parent lookup tells it which list a row belongs to. This keeps one UI, the condition builder, and one evaluator, `DE_ConditionEvaluator`.
- **Classifier output lives off-record.** It is stored on `DE_Record_Detail__c`, keyed by `Record_Id__c`, which is unique and indexed. Any object can therefore be classified without adding fields to it. Filters reference the output with the pseudo-paths `DE.Territory`, `DE.Stamp.<Group>`, `DE.MatchedAccount.<Field>`, `DE.Domain` and `DE.PersonalEmail`.
- **Round robin state is persisted.** It is kept in `DE_Rotation_State__c` rather than derived from logs, so purging logs never resets rotation. Writes to it are serialised by a `FOR UPDATE` lock on the parent team row.
- **Logs are the source for caps and load balancing.** Cap and load-balancing counts are aggregate queries on `DE_Assignment_Log__c`. `Assigned_At__c`, `Assigned_User__c` and the team and distributor lookups are all indexed, and so is `Record_Id__c` (external id).
- **Ids are stored as text.** User and Queue Ids live in `Text(18)` fields because the target can be either kind. Admin screens use a combined user/queue picker, and the controllers validate the Id prefix: `005` for a user, `00G` for a queue.
- **Fields on standard objects** mirror the documented packaged fields (H/installation/whats-in-the-package): is/last distributed, distribution count, reassigned, time to action, trigger flag, rejected, archived, source queue and action.

## Indexes and selectivity

| Query | Selective field(s) |
|---|---|
| Source candidates | `OwnerId` (standard index) or the source field. Sort fields are user-defined. |
| Caps and balancing counts | `DE_Assignment_Log__c.Assigned_At__c` filtered together with `Team__c` or `Distributor__c` (lookups are indexed) and `Assigned_User__c`. |
| SLA monitor | `Next_SLA_Check__c` with `Current__c`. Ask Salesforce Support for a custom index on `Next_SLA_Check__c` in orgs with high volume. |
| Sticky lookup | `Sticky_Key__c` (external id, indexed). |
| Details per record | `Record_Id__c` (unique, indexed). |

## Objects and fields
