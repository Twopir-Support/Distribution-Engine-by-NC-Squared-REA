# Metadata Component Inventory

Source: `Metadata Components Included in Package - Sheet1.csv`, the component list of the reference AppExchange package "Distribution Engine" (listing a0N30000009x4YAEAY). The CSV gives component names (labels for objects and fields), parent objects and metadata types. It gives no API names, field types or source code. The managed package hides its Apex source, and no org with the package installed was available. Behaviour is therefore established from the public help centre and listing (see `evidence-and-gaps.md`), not from the package internals.

**Total components: 2597**

## 1. Components by metadata type

| Type | Count | Implemented | Implementing | Identified | Investigating | Not Started | Blocked | Not Applicable |
|---|---|---|---|---|---|---|---|---|
| Apex Class | 1341 | 728 | 367 | 81 |  |  | 89 | 76 |
| Custom Field | 871 | 561 |  | 223 |  |  | 40 | 47 |
| Custom Object | 73 | 51 |  | 16 |  |  | 3 | 3 |
| Page Layout | 71 |  |  | 46 |  |  | 3 | 22 |
| Visualforce Page | 66 | 52 |  | 10 |  |  | 1 | 3 |
| Feature Parameter Integer | 50 |  |  |  |  |  |  | 50 |
| Visualforce Component | 21 | 13 |  | 7 |  |  |  | 1 |
| Lightning Web Component Bundle | 18 | 4 |  | 13 |  |  |  | 1 |
| Document | 16 |  |  |  |  |  |  | 16 |
| Tab | 9 | 9 |  |  |  |  |  |  |
| Apex Trigger | 8 | 7 |  | 1 |  |  |  |  |
| Flow Definition | 7 | 1 |  | 4 |  |  | 2 |  |
| Permission Set | 7 | 4 |  | 2 |  |  | 1 |  |
| Static Resource | 6 | 2 |  |  |  |  |  | 4 |
| Report | 4 | 4 |  |  |  |  |  |  |
| Workflow Email Alert | 3 |  |  | 3 |  |  |  |  |
| Classic Email Template | 3 |  |  | 3 |  |  |  |  |
| Feature Parameter Date | 3 |  |  |  |  |  |  | 3 |
| Aura Component Bundle | 3 | 1 |  | 2 |  |  |  |  |
| Home Page Component | 2 |  |  | 2 |  |  |  |  |
| Workflow Rule | 2 |  |  | 2 |  |  |  |  |
| List View | 1 |  |  | 1 |  |  |  |  |
| Report Folder | 1 | 1 |  |  |  |  |  |  |
| Dashboard Folder | 1 | 1 |  |  |  |  |  |  |
| Document Folder | 1 |  |  |  |  |  |  | 1 |
| Classic Email Template Folder | 1 |  |  | 1 |  |  |  |  |
| Feature Parameter Boolean | 1 |  |  |  |  |  |  | 1 |
| App | 1 | 1 |  |  |  |  |  |  |
| Prompt | 1 |  |  |  |  |  |  | 1 |
| Home Page Layout | 1 |  |  | 1 |  |  |  |  |
| Dashboard | 1 | 1 |  |  |  |  |  |  |
| Compact Layout | 1 |  |  | 1 |  |  |  |  |
| Custom Report Type | 1 |  |  | 1 |  |  |  |  |
| Platform Cache Partition | 1 |  |  | 1 |  |  |  |  |
| **Total** | **2597** | **1441** | **367** | **421** | **0** | **0** | **139** | **229** |

## 2. Components by parent object

Custom Fields, Page Layouts, triggers, workflow items, list views and compact layouts are listed under their parent. The target column shows the replicated object.

| Parent Object | Target | Kind | Fields | Layouts | Other | Total |
|---|---|---|---|---|---|---|
| Distributor | `DE_Distributor__c` | direct | 101 | 1 | 0 | 102 |
| Distribution log | `DE_Assignment_Log__c` | direct | 85 | 1 | 6 | 92 |
| Distribution Team | `DE_Team__c` | direct | 55 | 1 | 1 | 57 |
| Classifier custom classification log | `DE_Classification_Log__c` | direct | 43 | 1 | 0 | 44 |
| Distribution Engine details | `DE_Record_Detail__c` | direct | 28 | 1 | 1 | 30 |
| Slack workspace | `—` | blocked | 27 | 1 | 0 | 28 |
| Classifier Auto conversion log | `DE_Conversion_Log__c` | direct | 25 | 1 | 0 | 26 |
| Distributor schedule log | `DE_Run_Log__c` | direct | 22 | 1 | 0 | 23 |
| Classifier Auto conversion rule | `DE_Conversion_Rule__c` | direct | 20 | 1 | 0 | 21 |
| Classifier matching log | `DE_Matching_Log__c` | direct | 19 | 1 | 0 | 20 |
| Simulated distribution | `cls:DE_Simulator` | equiv | 19 | 1 | 0 | 20 |
| Lead | `Lead` | standard | 16 | 0 | 1 | 17 |
| Out of office | `DE_Out_Of_Office__c` | direct | 15 | 1 | 0 | 16 |
| Member distributor detail | `DE_Rotation_State__c` | equiv | 15 | 1 | 0 | 16 |
| Object sync log | `DE_Object_Sync_Log__c` | direct | 14 | 1 | 0 | 15 |
| Case | `Case` | standard | 14 | 0 | 1 | 15 |
| Classifier territory log | `DE_Territory_Log__c` | direct | 13 | 1 | 0 | 14 |
| History | `DE_History__c` | direct | 13 | 1 | 0 | 14 |
| Opportunity | `Opportunity` | standard | 12 | 0 | 1 | 13 |
| Distribution team member | `DE_Team_Member__c` | direct | 11 | 1 | 0 | 12 |
| Out-of-band assignment | `DE_Assignment_Log__c` | equiv | 11 | 1 | 0 | 12 |
| Distributor rr-sa | `DE_Assignment_Log__c.Sticky_Key__c` | equiv | 11 | 1 | 0 | 12 |
| Targeted message | `—` | na | 11 | 1 | 0 | 12 |
| Regional Holiday | `DE_Holiday__c` | direct | 11 | 1 | 0 | 12 |
| User messaging record | `—` | na | 10 | 1 | 0 | 11 |
| Team member runtime | `DE_Rotation_State__c` | equiv | 10 | 1 | 0 | 11 |
| User Slack Integration | `—` | blocked | 10 | 1 | 0 | 11 |
| Distribution team alert | `DE_SLA__c` | direct | 10 | 1 | 0 | 11 |
| Distribution team alert config | `DE_SLA__c` | equiv | 10 | 1 | 0 | 11 |
| Classifier territory | `DE_Territory__c` | direct | 9 | 1 | 0 | 10 |
| Distributor Tag | `DE_Condition__c` | equiv | 9 | 1 | 0 | 10 |
| Contact | `Contact` | standard | 9 | 0 | 1 | 10 |
| Classifier object | `DE_Settings__c.Classifier_Objects__c` | equiv | 8 | 1 | 0 | 9 |
| Distribution reject log | `DE_Reject_Request__c` | direct | 8 | 1 | 0 | 9 |
| Distribution team rejection config | `DE_Distributor__c.Reject_To_Id__c` | equiv | 8 | 1 | 0 | 9 |
| Migration | `—` | na | 8 | 1 | 0 | 9 |
| Object sync action | `DE_Object_Sync__c` | direct | 8 | 1 | 0 | 9 |
| Async assigner job | `cls:DE_SchedulerJob` | equiv | 8 | 1 | 0 | 9 |
| Account | `Account` | standard | 8 | 0 | 1 | 9 |
| Classifier stamp group | `DE_Stamp_Group__c` | direct | 7 | 1 | 0 | 8 |
| Classifier stamp | `DE_Stamp__c` | direct | 6 | 1 | 0 | 7 |
| Shift planner block | `DE_Shift_Plan_Block__c` | direct | 6 | 1 | 0 | 7 |
| Distributor category | `DE_Condition__c` | equiv | 6 | 1 | 0 | 7 |
| Distribution event | `DE_Assignment_Event__e` | equiv | 7 | 0 | 0 | 7 |
| User activity log | `DE_Availability_Event__c` | direct | 5 | 1 | 0 | 6 |
| Distributor runtime | `DE_Rotation_State__c` | equiv | 5 | 1 | 0 | 6 |
| User permission set assignment | `DE_User_Persona__c` | equiv | 4 | 1 | 0 | 5 |
| Classifier field | `DE_Territory__c` | equiv | 4 | 1 | 0 | 5 |
| Simulated distribution result | `cls:DE_Simulator` | equiv | 4 | 1 | 0 | 5 |
| Distribution engine profile | `DE_Persona__c` | direct | 4 | 1 | 0 | 5 |
| Distribution hours | `DE_Shift__c` | direct | 4 | 1 | 0 | 5 |
| Distribution log action | `DE_Log_Action__c` | direct | 4 | 1 | 0 | 5 |
| Team filter stamp | `DE_Condition__c` | equiv | 3 | 1 | 0 | 4 |
| Team shift planner | `DE_Shift_Plan__c` | direct | 3 | 1 | 0 | 4 |
| Team runtime | `DE_Team__c` | equiv | 3 | 1 | 0 | 4 |
| Distributor category team member | `DE_Distributor__c.Selected_Member_Ids__c` | equiv | 3 | 1 | 0 | 4 |
| Classifier territory map | `DE_Territory__c.Map__c` | equiv | 3 | 1 | 0 | 4 |
| Classifier matching object | `DE_Matching_Rule__c` | direct | 3 | 1 | 0 | 4 |
| Tag Cap | `DE_Cap__c.Tag_Caps__c` | equiv | 3 | 1 | 0 | 4 |
| Capping Pattern | `DE_Cap__c` | equiv | 3 | 1 | 0 | 4 |
| Criteria cap stamp | `DE_Condition__c` | equiv | 3 | 1 | 0 | 4 |
| Distribution tag weighting | `DE_Team__c.Tag_Weights__c` | equiv | 3 | 1 | 0 | 4 |
| Distributor notification settings | `—` | blocked | 3 | 1 | 0 | 4 |
| Async distribution event | `cls:DE_SchedulerJob` | equiv | 4 | 0 | 0 | 4 |
| User profile | `DE_User_Persona__c` | direct | 2 | 1 | 0 | 3 |
| Team manager | `DE_Team_Manager__c` | direct | 2 | 1 | 0 | 3 |
| Classifier Account Domains | `DE_Account_Domain__c` | direct | 2 | 1 | 0 | 3 |
| Distribution last assignee | `DE_Record_Detail__c.Previous_Assignees__c` | equiv | 2 | 1 | 0 | 3 |
| Distributor Tag Category | `DE_Agent__c.Tags__c` | equiv | 2 | 1 | 0 | 3 |
| Distributor Tag User | `DE_Agent__c.Tags__c` | equiv | 2 | 1 | 0 | 3 |
| Distribution tag weighting pattern | `DE_Team__c.Tag_Weights__c` | equiv | 2 | 1 | 0 | 3 |
| Team rejection config stamp | `DE_Distributor__c.Rejection_Enabled__c` | equiv | 2 | 1 | 0 | 3 |
| Team alert config stamp | `DE_SLA__c.Stamp_Value__c` | equiv | 2 | 1 | 0 | 3 |
| Distributor filter stamp | `DE_Condition__c` | equiv | 2 | 1 | 0 | 3 |
| Lock record | `cls:DE_TeamLock` | equiv | 2 | 1 | 0 | 3 |
| Distributor Tag Value | `DE_Agent__c.Tags__c` | equiv | 1 | 1 | 0 | 2 |
| Job setting | `DE_Settings__c` | equiv | 1 | 1 | 0 | 2 |
| Holiday Region | `DE_Holiday_Region__c` | direct | 0 | 1 | 0 | 1 |
| Task | `Task` | standard | 0 | 0 | 1 | 1 |
| Event | `Event` | standard | 0 | 0 | 1 | 1 |

## 3. Components by functional area

Apex classes were classified by name with ordered rules (see `scripts/metadata/csvmap_other.py`); every other type by its metadata type. A name only suggests the area. The behaviour of each area comes from the help centre.

| Functional area | Total | Implemented | Implementing | Identified | Investigating | Not Started | Blocked | Not Applicable |
|---|---|---|---|---|---|---|---|---|
| Data model | 944 | 612 |  | 239 |  |  | 43 | 50 |
| Shared utilities and settings | 100 | 100 |  |  |  |  |  |  |
| Slack integration | 89 |  |  |  |  |  | 89 |  |
| UI (Visualforce → LWC) | 87 | 65 |  | 17 |  |  | 1 | 4 |
| UI (layouts) | 71 |  |  | 46 |  |  | 3 | 22 |
| Distribution engine | 68 | 68 |  |  |  |  |  |  |
| Configuration export/import | 67 | 67 |  |  |  |  |  |  |
| Licensing / ISV telemetry | 54 |  |  |  |  |  |  | 54 |
| Classifier framework | 52 | 52 |  |  |  |  |  |  |
| Teams and members UI/services | 49 |  | 49 |  |  |  |  |  |
| Lead matching | 40 |  | 40 |  |  |  |  |  |
| Territory classification | 39 |  | 39 |  |  |  |  |  |
| Test infrastructure | 39 | 39 |  |  |  |  |  |  |
| Licensing / ISV telemetry / package upgrades | 39 |  |  |  |  |  |  | 39 |
| Lead auto conversion and de-duplication | 37 |  | 37 |  |  |  |  |  |
| Tags | 35 | 35 |  |  |  |  |  |  |
| Distribution engine internals | 34 | 34 |  |  |  |  |  |  |
| Change history | 33 |  |  | 33 |  |  |  |  |
| Personas and permissions | 33 |  | 33 |  |  |  |  |  |
| Custom classification (stamps) | 33 |  | 33 |  |  |  |  |  |
| Assignment simulator and test tool | 30 |  | 30 |  |  |  |  |  |
| Caps | 28 | 28 |  |  |  |  |  |  |
| Health checker and monitoring | 27 |  | 27 |  |  |  |  |  |
| Object sync | 26 | 26 |  |  |  |  |  |  |
| Console and scheduler | 25 | 25 |  |  |  |  |  |  |
| Distribution hours and shifts | 25 | 25 |  |  |  |  |  |  |
| Salesforce team (role) assignment | 20 |  |  | 20 |  |  |  |  |
| Admin failure notifications | 20 |  | 20 |  |  |  |  |  |
| Trigger distribution | 18 | 18 |  |  |  |  |  |  |
| Distribution logs UI | 18 | 18 |  |  |  |  |  |  |
| Housekeeping | 18 | 18 |  |  |  |  |  |  |
| Widget and availability toggle | 18 | 18 |  |  |  |  |  |  |
| Out of office and calendar | 18 | 18 |  |  |  |  |  |  |
| UI (LWC) | 18 | 4 |  | 13 |  |  |  | 1 |
| Shift planner | 17 |  |  | 17 |  |  |  |  |
| Package data migrations | 17 |  |  |  |  |  |  | 17 |
| Branding | 16 |  |  |  |  |  |  | 16 |
| Analytics and team performance | 16 | 16 |  |  |  |  |  |  |
| Weighting | 15 | 15 |  |  |  |  |  |  |
| Assignment rejection | 15 |  | 15 |  |  |  |  |  |
| Vendor in-app messaging | 14 |  |  |  |  |  |  | 14 |
| Dynamic team members | 13 | 13 |  |  |  |  |  |  |
| Automation | 12 | 1 |  | 9 |  |  | 2 |  |
| SLAs and auto reassign | 12 | 12 |  |  |  |  |  |  |
| Holidays | 11 |  | 11 |  |  |  |  |  |
| Auto archive | 10 | 10 |  |  |  |  |  |  |
| Manual distribution | 10 |  | 10 |  |  |  |  |  |
| Platform | 9 | 1 |  | 6 |  |  |  | 2 |
| UI (navigation) | 9 | 9 |  |  |  |  |  |  |
| Events | 9 | 9 |  |  |  |  |  |  |
| Email notifications | 9 |  | 9 |  |  |  |  |  |
| Reporting | 8 | 7 |  | 1 |  |  |  |  |
| Classifier backfill | 8 | 8 |  |  |  |  |  |  |
| Triggers | 8 | 7 |  | 1 |  |  |  |  |
| Security | 7 | 4 |  | 2 |  |  | 1 |  |
| Async chaining | 7 | 7 |  |  |  |  |  |  |
| Object sync logs | 7 |  | 7 |  |  |  |  |  |
| Settings pages | 7 | 7 |  |  |  |  |  |  |
| UI (resources) | 6 | 2 |  |  |  |  |  | 4 |
| Action tracking | 6 | 6 |  |  |  |  |  |  |
| Logging and exceptions | 6 | 6 |  |  |  |  |  |  |
| Trigger framework | 5 | 5 |  |  |  |  |  |  |
| Classifier failure alerts | 5 |  |  | 5 |  |  |  |  |
| Availability calendar | 5 | 5 |  |  |  |  |  |  |
| Global API | 5 | 5 |  |  |  |  |  |  |
| Email | 4 |  |  | 4 |  |  |  |  |
| Vendor support | 4 |  |  |  |  |  |  | 4 |
| Record history (inline) | 4 |  | 4 |  |  |  |  |  |
| Pull distribution | 4 | 4 |  |  |  |  |  |  |
| Out-of-band (manual/pull) assignment accounting | 4 | 4 |  |  |  |  |  |  |
| Assignment process view | 3 | 3 |  |  |  |  |  |  |
| UI (Aura → LWC) | 3 | 1 |  | 2 |  |  |  |  |
| Record inline component | 3 |  | 3 |  |  |  |  |  |
| Usage analytics | 2 |  |  |  |  |  |  | 2 |
| Auto conversion logs | 2 |  |  | 2 |  |  |  |  |
| Platform cache | 2 |  |  | 2 |  |  |  |  |
| VF controller base classes | 2 | 2 |  |  |  |  |  |  |
| Locking | 2 | 2 |  |  |  |  |  |  |
| Custom classification logs | 2 |  |  | 2 |  |  |  |  |

### Apex class roles (by naming convention)

| Role (suffix/prefix) | Count |
|---|---|
| Test classes (*_Tests) | 479 |
| Value/transfer objects (*VO, *UIVO, *DTO) | 197 |
| Other (executors, jobs, batches, queueables) | 193 |
| Utilities and helpers | 122 |
| Test mocks and builders (Mock*, TestUtils_*) | 88 |
| Controllers (VF/LWC) | 74 |
| Data access (*DAO) | 58 |
| Services (*Service) | 55 |
| Email builders | 22 |
| Interfaces (I*) | 20 |
| Trigger handlers (Trigger*) | 18 |
| Housekeeping tasks | 15 |

Apex: 1341 classes, of which 479 are test classes. The reference uses a layered design: VF/LWC controller → UIVO/DTO → service → DAO. The target keeps the layering lighter: LWC → `*Controller` → services (`DE_*Service`, `DE_Distribution*`) → `DE_ConfigRepository`/`DE_RecordQuery`. Replicating 1,341 class names one to one would mean writing classes whose internals are unknown, so each reference class is mapped to the target class that carries the same responsibility.

## 4. Duplicate and similar component names

**Exact duplicates (same type, parent and case-insensitive name).** These are separate fields that share a label (different API names):

- Custom Field `reject to user` on *Distribution team rejection config* × 2
- Custom Field `reject to user` on *Distributor* × 2
- Custom Field `log type` on *Distributor schedule log* × 3
- Custom Field `record name` on *History* × 2

**Near duplicates (same letters, different case or punctuation):**


**Families of numbered components:** `Stamp group 0–9` (and their `name`/`stamps` variants) on *Classifier custom classification log* and *Distribution Engine details*; `Order field/Order by 1–3 (deprecated)` and `Lookup match/unique field 2–3` on *Distributor*; `Log type` ×3 on *Distributor schedule log*.

## 5. Components that need further investigation

None. Every row is mapped.

## 6. Components that cannot be recreated one to one, and their equivalents

| Reference component(s) | Type | Equivalent in the target | Why |
|---|---|---|---|
| Async assigner job | Custom Object | `cls:DE_SchedulerJob` | Async work is the self-chaining scheduler queueable. |
| Async distribution event | Custom Object | `cls:DE_SchedulerJob` |  |
| Capping Pattern | Custom Object | `DE_Cap__c` |  |
| Classifier field | Custom Object | `DE_Territory__c` | Territory input fields are resolved by DE_TerritoryClassifier.requiredPaths. |
| Classifier object | Custom Object | `DE_Settings__c.Classifier_Objects__c` | Per-object classifier enablement is a setting; processing filters are DE_Condition__c rows. |
| Classifier territory map | Custom Object | `DE_Territory__c.Map__c` | Territories are grouped by the Map__c value per object instead of a map record. |
| Criteria cap stamp | Custom Object | `DE_Condition__c` | Cap criteria rows (Purpose = Cap Criteria). |
| Distribution event | Custom Object | `DE_Assignment_Event__e` | Platform event instead of a custom object. |
| Distribution last assignee | Custom Object | `DE_Record_Detail__c.Previous_Assignees__c` |  |
| Distribution tag weighting | Custom Object | `DE_Team__c.Tag_Weights__c` | One Collection:Tag=weight line per tag. |
| Distribution tag weighting pattern | Custom Object | `DE_Team__c.Tag_Weights__c` |  |
| Distribution team alert config | Custom Object | `DE_SLA__c` | SLA checkpoints carry their reassignment settings with the distributor. |
| Distribution team rejection config | Custom Object | `DE_Distributor__c.Reject_To_Id__c` | Rejection settings are per distributor. |
| Distributor Tag | Custom Object | `DE_Condition__c` | Member filter rows (Tag:, DynamicTag:, Territory, Stamp:). |
| Distributor Tag Category | Custom Object | `DE_Agent__c.Tags__c` | Tag collections are the Collection part of Collection:Tag values. |
| Distributor Tag User | Custom Object | `DE_Agent__c.Tags__c` |  |
| Distributor Tag Value | Custom Object | `DE_Agent__c.Tags__c` |  |
| Distributor category | Custom Object | `DE_Condition__c` | Distributor filter rows (Purpose = Distributor Filter). |
| Distributor category team member | Custom Object | `DE_Distributor__c.Selected_Member_Ids__c` | Selected members are stored on the distributor. |
| Distributor filter stamp | Custom Object | `DE_Condition__c` | Distributor filters on DE.Stamp.<Group> paths. |
| Distributor rr-sa | Custom Object | `DE_Assignment_Log__c.Sticky_Key__c` | Sticky assignments are looked up from current logs by sticky key. |
| Distributor runtime | Custom Object | `DE_Rotation_State__c` | Per-scope rotation state. |
| Job setting | Custom Object | `DE_Settings__c` |  |
| Lock record | Custom Object | `cls:DE_TeamLock` | Row lock on the team record (FOR UPDATE). |
| Member distributor detail | Custom Object | `DE_Rotation_State__c` | Per member and scope: sequence, weighting credit, replacement credit. |
| Out-of-band assignment | Custom Object | `DE_Assignment_Log__c` | Manual and pull assignments are logs with Type Manual/Pull; Counts_As_Hit__c controls rotation. |
| Simulated distribution | Custom Object | `cls:DE_Simulator` | Simulations run synchronously and return results to the UI; nothing is persisted. |
| Simulated distribution result | Custom Object | `cls:DE_Simulator` | Per-distributor results are returned in DE_Simulator.Result. |
| Tag Cap | Custom Object | `DE_Cap__c.Tag_Caps__c` |  |
| Team alert config stamp | Custom Object | `DE_SLA__c.Stamp_Value__c` |  |
| Team filter stamp | Custom Object | `DE_Condition__c` | Team filters on DE.Stamp.<Group> paths. |
| Team member runtime | Custom Object | `DE_Rotation_State__c` | Per-member sequence; period counts are computed from logs (DE_CapService.logCounts). |
| Team rejection config stamp | Custom Object | `DE_Distributor__c.Rejection_Enabled__c` | Rejection settings are per distributor; stamp-scoped rejection configs are not modelled. |
| Team runtime | Custom Object | `DE_Team__c` | Rotation_Sequence__c / Total_Assignments__c / Last_Assigned_At__c on the team; balances are computed from logs. |
| User permission set assignment | Custom Object | `DE_User_Persona__c` | Permission set assignment is done with the persona; the standard PermissionSetAssignment is the record. |
| 66 Visualforce pages, 21 Visualforce components | Visualforce | Lightning web components (tabs, widget, record component) | Lightning Experience UI; see the matrix for the page-by-page mapping. |
| 3 Aura bundles (Lightning Out wrappers) | Aura | The LWCs they wrapped | Not needed once the UI is LWC. |
| 2 Workflow Rules | Workflow | Record-triggered flows that call the same email alerts | Salesforce has retired workflow rules for new automation. |
| 2 Home Page Components, 1 Home Page Layout | Classic home | Lightning home page `DE_Home` with the widget | Classic-only metadata. |
| 1,341 Apex classes | Apex | 70+ target classes by responsibility | Reference internals are not visible; behaviour is rebuilt from documentation. |

## 7. Not applicable and blocked

| Group | Count | Reason |
|---|---|---|
| Blocked: Slack integration | 89 | Needs the vendor Slack app, OAuth tokens and middleware endpoint; not reproducible by an independent build. |
| Not Applicable: Licensing / ISV telemetry | 54 | LMA feature parameter; only meaningful in a managed package connected to a License Management App. |
| Not Applicable: Data model | 50 | Parent object: Per-user state of vendor in-app messages. |
| Blocked: Data model | 43 | Parent object: Slack user mapping requires the Slack integration. |
| Not Applicable: Licensing / ISV telemetry / package upgrades | 39 | Managed-package licensing, LMA feature parameters and version upgrade scripts; not applicable to an unmanaged independent build. |
| Not Applicable: UI (layouts) | 22 | Parent object is covered by an equivalent design without its own object. |
| Not Applicable: Package data migrations | 17 | Internal data migrations between package versions. |
| Not Applicable: Branding | 16 | Vendor logo image; not copied. SLDS icons are used. |
| Not Applicable: Vendor in-app messaging | 14 | Vendor in-app marketing/onboarding messages. |
| Not Applicable: UI (Visualforce → LWC) | 4 | Vendor logo in emails. |
| Not Applicable: UI (resources) | 4 | Vendor JS/CSS bundle for the VF assignment process view; replaced by LWC. |
| Not Applicable: Vendor support | 4 | Sends diagnostics to the vendor support team. |
| Blocked: UI (layouts) | 3 | Parent object is not replicated. |
| Blocked: Automation | 2 | Slack integration. |
| Not Applicable: Platform | 2 | Vendor branding images; SLDS icons are used. |
| Not Applicable: Usage analytics | 2 | Vendor product-usage analytics. |
| Blocked: Security | 1 | Slack integration. |
| Blocked: UI (Visualforce → LWC) | 1 | Slack integration settings. |
| Not Applicable: UI (LWC) | 1 | Vendor SVG sprite; lightning-icon and SLDS icons are used. |

## 8. Naming strategy and object name map

- **Prefix.** Every target component uses the `DE_` prefix and no namespace (unmanaged). A namespace can be added when the project is packaged (2GP), and the `DE_` names still avoid clashes with standard metadata.
- **Functional names.** Target API names say what a component does, for example `DE_Assignment_Log__c` for the reference "Distribution log". Labels follow the reference labels where the meaning is the same.
- **No copied identifiers.** No reference IDs, namespaces or package-specific identifiers are copied.

| Reference object (label) | Target | Kind | Reason |
|---|---|---|---|
| Async assigner job | `cls:DE_SchedulerJob` | equiv | Async work is the self-chaining scheduler queueable. |
| Async distribution event | `cls:DE_SchedulerJob` | equiv |  |
| Capping Pattern | `DE_Cap__c` | equiv |  |
| Classifier Account Domains | `DE_Account_Domain__c` | direct | Domain index maintained from Account and Contact changes, used by lead matching. |
| Classifier Auto conversion log | `DE_Conversion_Log__c` | direct |  |
| Classifier Auto conversion rule | `DE_Conversion_Rule__c` | direct |  |
| Classifier custom classification log | `DE_Classification_Log__c` | direct | Stamps are stored as one text field per run instead of 10 numbered group columns. |
| Classifier field | `DE_Territory__c` | equiv | Territory input fields are resolved by DE_TerritoryClassifier.requiredPaths. |
| Classifier matching log | `DE_Matching_Log__c` | direct |  |
| Classifier matching object | `DE_Matching_Rule__c` | direct |  |
| Classifier object | `DE_Settings__c.Classifier_Objects__c` | equiv | Per-object classifier enablement is a setting; processing filters are DE_Condition__c rows. |
| Classifier stamp | `DE_Stamp__c` | direct |  |
| Classifier stamp group | `DE_Stamp_Group__c` | direct |  |
| Classifier territory | `DE_Territory__c` | direct |  |
| Classifier territory log | `DE_Territory_Log__c` | direct |  |
| Classifier territory map | `DE_Territory__c.Map__c` | equiv | Territories are grouped by the Map__c value per object instead of a map record. |
| Criteria cap stamp | `DE_Condition__c` | equiv | Cap criteria rows (Purpose = Cap Criteria). |
| Distribution Engine details | `DE_Record_Detail__c` | direct | Keyed by Record_Id__c instead of a lookup on every record. |
| Distribution Team | `DE_Team__c` | direct |  |
| Distribution engine profile | `DE_Persona__c` | direct | Persona (custom permission profile). |
| Distribution event | `DE_Assignment_Event__e` | equiv | Platform event instead of a custom object. |
| Distribution hours | `DE_Shift__c` | direct | Reusable shift (distribution hours) with a JSON weekly schedule. |
| Distribution last assignee | `DE_Record_Detail__c.Previous_Assignees__c` | equiv |  |
| Distribution log | `DE_Assignment_Log__c` | direct | Label "Distribution Log". |
| Distribution log action | `DE_Log_Action__c` | direct |  |
| Distribution reject log | `DE_Reject_Request__c` | direct |  |
| Distribution tag weighting | `DE_Team__c.Tag_Weights__c` | equiv | One Collection:Tag=weight line per tag. |
| Distribution tag weighting pattern | `DE_Team__c.Tag_Weights__c` | equiv |  |
| Distribution team alert | `DE_SLA__c` | direct |  |
| Distribution team alert config | `DE_SLA__c` | equiv | SLA checkpoints carry their reassignment settings with the distributor. |
| Distribution team member | `DE_Team_Member__c` | direct |  |
| Distribution team rejection config | `DE_Distributor__c.Reject_To_Id__c` | equiv | Rejection settings are per distributor. |
| Distributor | `DE_Distributor__c` | direct |  |
| Distributor Tag | `DE_Condition__c` | equiv | Member filter rows (Tag:, DynamicTag:, Territory, Stamp:). |
| Distributor Tag Category | `DE_Agent__c.Tags__c` | equiv | Tag collections are the Collection part of Collection:Tag values. |
| Distributor Tag User | `DE_Agent__c.Tags__c` | equiv |  |
| Distributor Tag Value | `DE_Agent__c.Tags__c` | equiv |  |
| Distributor category | `DE_Condition__c` | equiv | Distributor filter rows (Purpose = Distributor Filter). |
| Distributor category team member | `DE_Distributor__c.Selected_Member_Ids__c` | equiv | Selected members are stored on the distributor. |
| Distributor filter stamp | `DE_Condition__c` | equiv | Distributor filters on DE.Stamp.<Group> paths. |
| Distributor notification settings | — | blocked | Slack notifications per distributor require the Slack integration. |
| Distributor rr-sa | `DE_Assignment_Log__c.Sticky_Key__c` | equiv | Sticky assignments are looked up from current logs by sticky key. |
| Distributor runtime | `DE_Rotation_State__c` | equiv | Per-scope rotation state. |
| Distributor schedule log | `DE_Run_Log__c` | direct |  |
| History | `DE_History__c` | direct |  |
| Holiday Region | `DE_Holiday_Region__c` | direct | Holidays and teams reference a region record. |
| Job setting | `DE_Settings__c` | equiv |  |
| Lock record | `cls:DE_TeamLock` | equiv | Row lock on the team record (FOR UPDATE). |
| Member distributor detail | `DE_Rotation_State__c` | equiv | Per member and scope: sequence, weighting credit, replacement credit. |
| Migration | — | na | Vendor package upgrade/data migration bookkeeping; configuration moves between orgs use DE_ConfigTransfer. |
| Object sync action | `DE_Object_Sync__c` | direct |  |
| Object sync log | `DE_Object_Sync_Log__c` | direct |  |
| Out of office | `DE_Out_Of_Office__c` | direct |  |
| Out-of-band assignment | `DE_Assignment_Log__c` | equiv | Manual and pull assignments are logs with Type Manual/Pull; Counts_As_Hit__c controls rotation. |
| Regional Holiday | `DE_Holiday__c` | direct |  |
| Shift planner block | `DE_Shift_Plan_Block__c` | direct |  |
| Simulated distribution | `cls:DE_Simulator` | equiv | Simulations run synchronously and return results to the UI; nothing is persisted. |
| Simulated distribution result | `cls:DE_Simulator` | equiv | Per-distributor results are returned in DE_Simulator.Result. |
| Slack workspace | — | blocked | Requires a Slack app, OAuth and the vendor middleware. |
| Tag Cap | `DE_Cap__c.Tag_Caps__c` | equiv |  |
| Targeted message | — | na | Vendor in-app marketing/onboarding messages. |
| Team alert config stamp | `DE_SLA__c.Stamp_Value__c` | equiv |  |
| Team filter stamp | `DE_Condition__c` | equiv | Team filters on DE.Stamp.<Group> paths. |
| Team manager | `DE_Team_Manager__c` | direct |  |
| Team member runtime | `DE_Rotation_State__c` | equiv | Per-member sequence; period counts are computed from logs (DE_CapService.logCounts). |
| Team rejection config stamp | `DE_Distributor__c.Rejection_Enabled__c` | equiv | Rejection settings are per distributor; stamp-scoped rejection configs are not modelled. |
| Team runtime | `DE_Team__c` | equiv | Rotation_Sequence__c / Total_Assignments__c / Last_Assigned_At__c on the team; balances are computed from logs. |
| Team shift planner | `DE_Shift_Plan__c` | direct |  |
| User Slack Integration | — | blocked | Slack user mapping requires the Slack integration. |
| User Slack Integration  | — | blocked |  |
| User activity log | `DE_Availability_Event__c` | direct |  |
| User messaging record | — | na | Per-user state of vendor in-app messages. |
| User permission set assignment | `DE_User_Persona__c` | equiv | Permission set assignment is done with the persona; the standard PermissionSetAssignment is the record. |
| User profile | `DE_User_Persona__c` | direct | Persona assignment per user. |
