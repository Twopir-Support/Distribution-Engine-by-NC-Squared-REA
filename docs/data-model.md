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


### Distribution Team (`DE_Team__c`)

A team distributes one object to its members through ordered distributors. Teams run in execution order.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Action_Field__c` | Action Field | Text(120) | Picklist that records the action, e.g. DE_Action__c or Status. |
| `Action_Respect_Hours__c` | Action Tracking Hours | Picklist | values: Team and Member, Team Only, None |
| `Action_Tracking_Enabled__c` | Action Tracking | Checkbox | default false |
| `Active_Status_Field__c` | Active Status Field | Text(120) | Picklist field that marks a record as active (still being worked), e.g. Status. |
| `Active_Status_Values__c` | Active Status Values | TextArea | Semicolon-separated values of the Active Status Field, e.g. New;Working. |
| `Active__c` | Active | Checkbox | default false |
| `Apply_Active_Status_To_SLAs__c` | Apply Active Status to SLAs | Checkbox | default true |
| `Assignment_Field__c` | Assignment Field | Text(120) | User lookup field written by this team. Defaults to OwnerId. Can only be changed while the team has no distributors. |
| `Auto_Action_Activity_Types__c` | Auto Action Activity Types | Text(255) | Semicolon-separated Task/Event Type values that set the action automatically, e.g. Call;Email. |
| `Balance_By__c` | Active Cap and Balance By | Picklist | values: Record Count, Field Value |
| `Balance_Field__c` | Balance Field | Text(120) | Numeric field summed when balancing by Field Value. Values are truncated to whole numbers. |
| `Default_Tag_Weight__c` | Default Tag Weight | Number | default 1 |
| `Description__c` | Description | TextArea |  |
| `Dynamic_Members_Enabled__c` | Dynamic Team Members | Checkbox | default false; Keep membership in sync with Dynamic Membership conditions on User fields. |
| `Dynamic_Members_Logic__c` | Dynamic Member Logic | Text(255) |  |
| `Execution_Order__c` | Execution Order | Number | default 10; Teams run top to bottom by this number. |
| `Filter_Logic__c` | Team Filter Logic | Text(255) | Optional logic for team filters, e.g. (1 AND 2) OR 3. Team filters apply to every distributor. |
| `Holiday_Region__c` | Holiday Region | Text(80) | Regional holidays in this region stop distribution for the whole team. |
| `Load_Balancing_Level__c` | Load Balancing Level | Picklist | values: Team, Distributor |
| `Load_Balancing_Type__c` | Load Balancing Type | Picklist | values: Daily, Weekly, Monthly, Active; Daily, Weekly and Monthly balance Distribution Engine assignments. Active balances all owned records in Active Status (or all owned records when no Active Status is set). |
| `Manager_User_Ids__c` | Team Managers | TextArea | Comma-separated User Ids allowed to manage this team with the Team Manager permission set. |
| `Object_API_Name__c` | Distribution Object | Text(80) | required; API name of the Salesforce object, e.g. Lead, Case, Opportunity or My_Object__c. Cannot be changed after the team is created. |
| `Object_Sync_Enabled__c` | Object Sync | Checkbox | default false; Run active Object Sync actions for this object after assignment. |
| `Rejection_Limit__c` | Rejection Limit | Picklist | values: Unlimited, Manager Only, Limited |
| `Rejections_Per_Day__c` | Rejections Per Day | Number | default 3 |
| `Respect_Hours_For_Triggers__c` | Respect Distribution Hours for Triggers | Checkbox | default false |
| `Rotation_Sequence__c` | Rotation Sequence | Number | default 0; Internal counter. Do not edit. |
| `Round_Robin_Level__c` | Round Robin Level | Picklist | values: Team, Distributor; Team: one rotation shared by all distributors. Distributor: each distributor rotates independently. |
| `SLA_Respect_Hours__c` | SLA Hours | Picklist | values: Team and Member, Team Only, None |
| `Tag_Weights__c` | Tag Weights | TextArea | Tag weighting, one per line: Collection:Tag=Weight. The highest weighted tag a member has is used. |
| `Team_Hours__c` | Team Hours | Lookup → DE_Shift__c | Distribution hours for the team. Members without their own shift inherit these hours. |
| `Team_Type__c` | Team Type | Picklist | values: Standard, Queue to Queue; Queue to Queue teams assign records from a source queue to member queues instead of people. |
| `Track_Action_From_Any_User__c` | Track Action From Any User | Checkbox | default false |
| `Tracked_Actions__c` | Actions to Track | TextArea | Semicolon-separated values of the action field that count as actioned. |
| `Weighting_Mode__c` | Weighting Mode | Picklist | values: Individual, Tag |

### Team Member (`DE_Team_Member__c`)

A user (or queue, for Queue to Queue teams) who receives assignments from a team.

Sharing: `ControlledByParent`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Active__c` | Active | Checkbox | default true |
| `Dynamic__c` | Added Dynamically | Checkbox | default false |
| `Member_Hours__c` | Member Hours | Lookup → DE_Shift__c | Overrides team hours for this member. |
| `Queue_Id__c` | Queue Id | Text(18) | Queue member for Queue to Queue teams. |
| `Team__c` | Team | MasterDetail → DE_Team__c |  |
| `Unique_Key__c` | Unique Key | Text(40) | unique; external id / indexed; Team Id + member Id. Prevents duplicate memberships. |
| `User__c` | User | Lookup → User |  |
| `Weight__c` | Weight | Number | default 1; 0.25 to 4. Weight 2 receives two assignments per round robin cycle; 0.5 is skipped every other cycle. |

Validation rules:

- `DE_Member_User_Or_Queue`: A team member must be exactly one user or one queue.
- `DE_Weight_Range`: Weight must be between 0.25 and 4 in steps of 0.25.

### Distributor (`DE_Distributor__c`)

The rules that decide how, from where and to whom a team assigns records. Distributors run in order.

Sharing: `ControlledByParent`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Active__c` | Active | Checkbox | default false |
| `Assign_If_Offline__c` | Assign if User Is Offline in Widget | Checkbox | default false |
| `Assign_If_Unavailable__c` | Assign if User Is Unavailable | Checkbox | default false; Ignore out of office, distribution hours and toggle. Holidays are always respected. |
| `Assign_To__c` | Assign To | Picklist | values: All Team Members, Selected Members |
| `Auto_Reassign__c` | Auto Reassign | Checkbox | default false |
| `Default_Owner_Id__c` | Default Owner Id | Text(18) | Trigger distributors: owner used when no member can be assigned. |
| `Description__c` | Description | TextArea |  |
| `Dynamic_Owner_Field__c` | Dynamic Owner Field | Text(120) | Field holding the User Id to assign to (Trigger distributors). |
| `Exclude_Members_Field__c` | Exclude Members Field | Text(120) | Text or user lookup field on the record holding comma-separated User Ids that must not receive it. |
| `Field_Updates__c` | Update Fields on Assignment | TextArea | One update per line: Field__c=Value. Picklist, multi-select picklist, text, number and checkbox fields are supported. |
| `Filter_Logic__c` | Filter Logic | Text(255) |  |
| `Lookup_Assign_Field__c` | Lookup Assign To | Text(255) | User field on the matched record, e.g. OwnerId or Account.OwnerId. |
| `Lookup_Object__c` | Lookup To | Text(80) |  |
| `Lookup_Record_Field__c` | Lookup Record Field | Text(120) |  |
| `Lookup_Target_Field__c` | Lookup Target Field | Text(120) |  |
| `Lookup_Tie_Breaker_Direction__c` | Tie Breaker Direction | Picklist | values: Newest or Highest, Oldest or Lowest |
| `Lookup_Tie_Breaker_Field__c` | Tie Breaker Field | Text(120) |  |
| `Lookup_Where_Logic__c` | Lookup Where Logic | Text(255) |  |
| `Method__c` | Method | Picklist | values: Round Robin, Load Balancing, Lookup Owner, Related Owner, Dynamic Owner, Current Owner |
| `Order__c` | Order | Number | default 10 |
| `Pull_Count__c` | Number of Records to Pull | Number | default 1 |
| `Reassign_Field_Updates__c` | Update Fields on Reassignment | TextArea | One update per line: Field__c=Value. Picklist, multi-select picklist, text, number and checkbox fields are supported. |
| `Reassign_From_SLA__c` | Reassign From SLA | Number | default 1; Missing this checkpoint or any later one reassigns the record. |
| `Reassign_To_Id__c` | Reassign To | Text(18) | Queue (to redistribute) or User. 18-character Id of a User or Queue. |
| `Reject_Field_Updates__c` | Update Fields on Rejection | TextArea | One update per line: Field__c=Value. Picklist, multi-select picklist, text, number and checkbox fields are supported. |
| `Reject_To_Id__c` | Reject To | Text(18) | 18-character Id of a User or Queue. |
| `Rejection_Enabled__c` | Assignment Rejection | Checkbox | default false |
| `Related_Field__c` | Assign Using Related Object | Text(255) | Lookup path whose owner receives the record, e.g. DE.MatchedAccount or AccountId. |
| `Related_Secondary_Field__c` | Otherwise Use Related Object | Text(255) |  |
| `Remove_Sticky_On_Reassign__c` | Remove Sticky on Reassignment | Picklist | values: New Sticky Only, Always, Never |
| `Replace_Rejected__c` | Replace Rejected Records | Picklist | values: Replace on Usual Assignment, Replace as Next Assignment, Don't Replace |
| `Respect_Team_Caps__c` | Respect Team Caps | Checkbox | default true |
| `SLA_Enabled__c` | SLAs Enabled | Checkbox | default false |
| `Selected_Member_Ids__c` | Selected Members | TextArea | Comma-separated User or Queue Ids. |
| `Send_Email__c` | Email Notification | Checkbox | default false |
| `Send_Notification__c` | Salesforce Notification | Checkbox | default true |
| `Sort_Order__c` | Sort Order | Text(255) | Comma-separated fields with optional ASC or DESC, e.g. Rating DESC, CreatedDate ASC. Default is CreatedDate ASC. |
| `Source_After_Value__c` | Value After Assignment | Text(255) |  |
| `Source_Field__c` | Source Field | Text(120) | Field Value source: picklist field that marks records ready. |
| `Source_Id__c` | Source Queue or User Id | Text(18) |  |
| `Source_Ready_Value__c` | Ready Value | Text(255) |  |
| `Source_Type__c` | Source | Picklist | values: Queue, User, Field Value, Any; Where records are taken from. Any is only valid for Trigger and Manual distributors. |
| `Sticky_Cap_Behaviour__c` | Sticky Cap Behaviour | Picklist | values: Ignore Caps, Respect Caps - Assign to Next Member, Respect Caps - Don't Assign |
| `Sticky_Days__c` | Sticky Period (Days) | Number | default 90 |
| `Sticky_Enabled__c` | Sticky Assignment | Checkbox | default false |
| `Sticky_Field__c` | Sticky Match Field | Text(120) |  |
| `Sticky_Level__c` | Sticky Match Level | Picklist | values: Distributor, Team, Global |
| `Sticky_Only__c` | Disable Round Robin (Sticky Only) | Checkbox | default false |
| `Sticky_Retain_Offline__c` | Retain Sticky When Offline | Checkbox | default false |
| `Sticky_Retain_Unavailable__c` | Retain Sticky When Unavailable | Checkbox | default false |
| `Team__c` | Team | MasterDetail → DE_Team__c |  |
| `Toggle_User_Off__c` | Toggle User Off on Reassignment | Checkbox | default false |
| `Treat_Manual_As_Rejection__c` | Treat Manual Assignment as Rejection | Checkbox | default false |
| `Type__c` | Distributor Type | Picklist | values: Standard, Pull, Manual, Trigger; Standard: scheduler pushes records. Pull: members pull records. Manual: managers pick the member. Trigger: assigns immediately when the record is flagged on update. |
| `Weighting_Enabled__c` | Weighting Enabled | Checkbox | default true |

Validation rules:

- `DE_Pull_Count_Range`: Number of records to pull must be between 1 and 100.
- `DE_Reassign_Target_Required`: Choose a queue or user to reassign to.
- `DE_Reject_Target_Required`: Choose a queue or user to reject to.
- `DE_Source_Required`: Standard and Pull distributors need a source: a queue or user Id, or a field and ready value.
- `DE_Sticky_Field_Required`: Choose a sticky match field.

### Condition (`DE_Condition__c`)

One filter row (Field / Operator / Value) used by teams, distributors, SLAs, classifier rules, caps and object sync.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Cap__c` | Cap | Lookup → DE_Cap__c |  |
| `Conversion_Rule__c` | Conversion Rule | Lookup → DE_Conversion_Rule__c |  |
| `Distributor__c` | Distributor | Lookup → DE_Distributor__c |  |
| `Field_API_Name__c` | Field | Text(255) | required; Field API name or path (Account.Industry), DE classifier value (DE.Territory, DE.Stamp.Priority, DE.MatchedAccount.Type) or, for member filters, Tag:Collection / DynamicTag:Collection / Territory. |
| `Matching_Rule__c` | Matching Rule | Lookup → DE_Matching_Rule__c |  |
| `Object_Sync__c` | Object Sync | Lookup → DE_Object_Sync__c |  |
| `Operator__c` | Operator | Picklist | values: equals, not equals, less than, greater than, less or equal, greater or equal, contains, does not contain, starts with, does not start with, ends with, does not end with, in, not in, includes, includes all, does not include, between, is blank, is not blank |
| `Purpose__c` | Purpose | Picklist | values: Team Filter, Distributor Filter, Member Filter, SLA Condition, Territory, Stamp, Conversion Filter, Match Filter, Lookup Where, Cap Criteria, Dynamic Membership, Sync Filter, Delay Filter |
| `SLA__c` | SLA | Lookup → DE_SLA__c |  |
| `Sequence__c` | Sequence | Number | required; Row number referenced from filter logic. |
| `Stamp__c` | Stamp | Lookup → DE_Stamp__c |  |
| `Team__c` | Team | Lookup → DE_Team__c |  |
| `Territory__c` | Territory | Lookup → DE_Territory__c |  |
| `Value__c` | Value | Text(255) | Lists use semicolons. Dates accept TODAY, NOW, an absolute date or "n minutes/hours/days ago". between uses low..high. |

### Cap (`DE_Cap__c`)

A team-level or distributor-level cap on the number of assignments per period, active records or records matching criteria.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Active__c` | Active | Checkbox | default true |
| `Criteria_Logic__c` | Criteria Logic | Text(255) |  |
| `Criteria_Source__c` | Criteria Source | Picklist | values: Field, Distributor Filters |
| `Custom_Length__c` | Custom Period Length | Number | Minutes 5-180, Hours 1-168 or Days 1-31. Custom caps are rolling. |
| `Default_Cap__c` | Default Cap | Number | Blank means unlimited. |
| `Distributor__c` | Distributor | Lookup → DE_Distributor__c |  |
| `Period__c` | Period | Picklist | values: Hourly, Half-hourly, Daily, Weekly, Monthly, Custom Minutes, Custom Hours, Custom Days, Active, Criteria |
| `Tag_Caps__c` | Caps by Tag | TextArea | One per line: Collection:Tag=Cap. Blank cap value means unlimited for that tag. |
| `Team__c` | Team | Lookup → DE_Team__c |  |

Validation rules:

- `DE_Cap_Owner`: A cap belongs to exactly one team or one distributor.
- `DE_Custom_Cap_Range`: Custom caps: minutes 5-180, hours 1-168, days 1-31.

### SLA Checkpoint (`DE_SLA__c`)

A team SLA checkpoint: after N minutes, if the conditions are true the SLA is missed.

Sharing: `ControlledByParent`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Active__c` | Active | Checkbox | default true |
| `Alert_Type__c` | Alert Type | Picklist | values: Time Checkpoint, Continuous Field Monitoring, Custom Date/Time |
| `Check_After_Field__c` | SLA Check After Field | Text(120) | Custom Date/Time: date/time field holding when to check. |
| `Checkpoint__c` | Checkpoint | Number | required; 1, 2 or 3 in chronological order. |
| `Condition_Logic__c` | SLA Missed If Logic | Text(255) |  |
| `Minutes_After_Assignment__c` | Time Since Assignment (Minutes) | Number | Time Checkpoint: check this many minutes after assignment. Continuous Field Monitoring: monitor for this long (max 20160). |
| `Notify_Assignee__c` | Notify Assignee | Checkbox | default true |
| `Notify_Manager__c` | Notify Manager | Checkbox | default false |
| `Stamp_Value__c` | Stamp | Text(255) | Stamp SLAs: only applies to records with this stamp, e.g. Priority:Critical. |
| `Team__c` | Team | MasterDetail → DE_Team__c |  |

Validation rules:

- `DE_Checkpoint_Range`: Checkpoint must be 1, 2 or 3.
- `DE_Monitor_Max`: Continuous monitoring is limited to two weeks (20160 minutes).

### Rotation State (`DE_Rotation_State__c`)

Internal round robin and weighting state per scope (team or distributor) and member.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Credit__c` | Weighting Credit | Number | default 0 |
| `Cycle__c` | Cycle | Number | default 0 |
| `Last_Sequence__c` | Last Sequence | Number | default 0 |
| `Member_Key__c` | Member Id | Text(18) |  |
| `Replacement_Credits__c` | Replacement Credits | Number | default 0; Rejected records owed back to this member (Replace on Usual Assignment). |
| `Scope_Key__c` | Scope Key | Text(60) | unique; external id / indexed |
| `Team__c` | Team | Lookup → DE_Team__c |  |

### Shift (`DE_Shift__c`)

Reusable weekly working pattern in a timezone with up to three blocks per day.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Description__c` | Description | TextArea |  |
| `Schedule__c` | Schedule | LongTextArea | JSON: {"MON":["09:00-12:00","13:00-17:30"],"TUE":[...]} . Use +1 for blocks ending after midnight, e.g. 22:00-06:00+1. |
| `Timezone__c` | Timezone | Text(60) | required; IANA timezone, e.g. Europe/London or America/New_York. |

### Regional Holiday (`DE_Holiday__c`)

A holiday in a holiday region. Teams in the region do not distribute during it.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `All_Day__c` | All Day | Checkbox | default true |
| `End__c` | Ends | DateTime | required |
| `Region__c` | Region | Text(80) | required |
| `Start__c` | Starts | DateTime | required |
| `Timezone__c` | Timezone | Text(60) |  |

Validation rules:

- `DE_Holiday_End_After_Start`: Ends must be after Starts.

### Out of Office (`DE_Out_Of_Office__c`)

A period when a user (or queue) receives no assignments from any team.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `All_Day__c` | All Day | Checkbox | default false |
| `End__c` | End | DateTime | required |
| `Queue_Id__c` | Queue Id | Text(18) |  |
| `Reason__c` | Reason | Text(80) |  |
| `Source__c` | Source | Picklist | values: Manual, Calendar, API |
| `Start__c` | Start | DateTime | required |
| `User__c` | User | Lookup → User |  |

Validation rules:

- `DE_OOO_End_After_Start`: End must be after Start.
- `DE_OOO_Reason_Length`: Reason is limited to 80 characters.

### User Availability (`DE_Agent__c`)

Availability toggle and tags for one user.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Last_Status_Change__c` | Last Status Change | DateTime |  |
| `Online__c` | Online | Checkbox | default true |
| `Tags__c` | Tags | LongTextArea | Semicolon-separated Collection:Tag values, e.g. Language:English;Tier:Gold. |
| `Toggle_Reason__c` | Toggle Off Reason | Text(80) |  |
| `Toggle_Until__c` | Toggled Off Until | DateTime | Timer toggle: the user comes back online automatically at this time. |
| `Unique_User__c` | Unique User | Text(18) | unique; external id / indexed |
| `User__c` | User | Lookup → User |  |

### Availability History (`DE_Availability_Event__c`)

Audit of every availability toggle: who, when, by whom and why.

Sharing: `Read`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Changed_At__c` | Changed At | DateTime |  |
| `Changed_By__c` | Changed By | Lookup → User |  |
| `Online__c` | Online | Checkbox | default false |
| `Reason__c` | Reason | Text(80) |  |
| `Source__c` | Source | Picklist | values: User, Manager, Timer, Start of Day, End of Day, Auto Reassign, API |
| `User__c` | User | Lookup → User |  |

### Territory (`DE_Territory__c`)

Classifier territory. Records are stamped with the first matching territory (smallest first). Member filters route by territory.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Condition_Logic__c` | Condition Logic | Text(255) |  |
| `Countries__c` | Countries | TextArea | Semicolon-separated country names or ISO codes. |
| `Description__c` | Description | TextArea |  |
| `Map__c` | Map | Text(80) | Group of territories. Leave blank for the default map. |
| `Object_API_Name__c` | Object | Text(80) | required; API name of the Salesforce object, e.g. Lead, Case, Opportunity or My_Object__c. |
| `Postal_Codes__c` | Postal Codes | LongTextArea | Semicolon-separated postal codes, prefixes ending in * or ranges low..high. |
| `Priority__c` | Order | Number | required; Evaluated smallest number first. Put postal-code territories before states and states before countries. |
| `Stamp_Field__c` | Stamp Field | Text(120) | Optional field on the record that also receives the territory name. Defaults to DE_Territory__c when present. |
| `States__c` | States | TextArea | Semicolon-separated state names or codes. |
| `Status__c` | Status | Picklist | values: Draft, Active |

### Stamp Group (`DE_Stamp_Group__c`)

Custom classification category, e.g. Priority, whose stamps are evaluated in order.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Active__c` | Active | Checkbox | default true |
| `Description__c` | Description | TextArea |  |
| `Group_Type__c` | Group Type | Picklist | values: Single, Multiple; Single stops at the first matching stamp. Multiple applies every matching stamp. |
| `Object_API_Name__c` | Object | Text(80) | required |
| `Stamp_Field__c` | Stamp Field | Text(120) | Optional record field that also receives the stamp value(s). |

### Stamp (`DE_Stamp__c`)

A value of a stamp group with the filters that award it.

Sharing: `ControlledByParent`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Condition_Logic__c` | Condition Logic | Text(255) |  |
| `Order__c` | Order | Number | required |
| `Stamp_Group__c` | Stamp Group | MasterDetail → DE_Stamp_Group__c |  |

### Lead Matching Rule (`DE_Matching_Rule__c`)

Classifier lead matching to accounts, contacts or existing leads.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Active__c` | Active | Checkbox | default true |
| `Description__c` | Description | TextArea |  |
| `Filter_Logic__c` | Match Filter Logic | Text(255) | Logic for Match Filter conditions applied to the candidate records. |
| `Fuzzy_Threshold__c` | Fuzzy Match Threshold (%) | Number | default 85 |
| `Match_Company_Name__c` | Company Name Matching | Checkbox | default true; Normalised: case, punctuation and suffixes like Inc, Ltd, LLC are ignored. Fuzzy similarity is scored. |
| `Match_Email_Domain__c` | Email Domain Matching | Checkbox | default true; Lead to Account: lead email domain matches account website or contact email domains. Email domain takes priority over website. Personal domains never match. |
| `Match_Email__c` | Email Address Matching | Checkbox | default true; Lead to Contact / Lead to Lead: exact email. |
| `Match_Type__c` | Match Type | Picklist | values: Lead to Account, Lead to Contact, Lead to Lead |
| `Priority__c` | Order | Number | required |
| `Source_Field__c` | Custom Lead Field | Text(120) |  |
| `Target_Field__c` | Custom Target Field | Text(120) |  |
| `Tie_Breaker_Direction__c` | Multiple Match Direction | Picklist | values: Newest or Highest, Oldest or Lowest |
| `Tie_Breaker_Field__c` | Multiple Match Order Field | Text(120) | Default LastModifiedDate. |

### Auto-Conversion Rule (`DE_Conversion_Rule__c`)

Ordered lead auto-conversion and de-duplication rules. The default rule runs last.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Account_Field_Update__c` | Account Field Update | Text(255) | Field__c=Value |
| `Action__c` | Action | Picklist | values: Do Not Convert, Auto Convert, De-Duplicate |
| `Active__c` | Active | Checkbox | default true |
| `Contact_Field_Update__c` | Contact Field Update | Text(255) |  |
| `Converted_Status__c` | Converted Lead Status | Text(80) |  |
| `Copy_Blank_Fields__c` | Copy Values Into Blank Fields | Checkbox | default true; De-duplicate: copy values from the duplicate into blank fields on the surviving lead. |
| `Create_Opportunity__c` | Create Opportunity | Picklist | values: Never, Always, Only When No Open Opportunity |
| `Default_User_Id__c` | Default User Id | Text(18) |  |
| `Description__c` | Description | TextArea |  |
| `Filter_Logic__c` | Filter Logic | Text(255) |  |
| `Is_Default__c` | Default Rule | Checkbox | default false |
| `Match__c` | Match | Picklist | values: Any, No Match, Account and Contact Match, Account Only Match, Lead Only Match |
| `Opportunity_Field_Update__c` | Opportunity Field Update | Text(255) |  |
| `Order__c` | Order | Number | required |
| `Owner_Source__c` | Owner | Picklist | values: Matched Record Owner, Retain Lead Owner, Default User |
| `Survivor_Field_Update__c` | Surviving Lead Field Update | Text(255) |  |

### Object Sync Action (`DE_Object_Sync__c`)

When a parent record is assigned, child records related by a lookup take the new owner.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Active__c` | Active | Checkbox | default false |
| `Child_Object__c` | Related Object | Text(80) | required |
| `Filter_Logic__c` | Filter Logic | Text(255) |  |
| `Lookup_Field__c` | Related Lookup Field | Text(120) | required; Lookup on the related object pointing at the distribution object, e.g. WhoId or AccountId. |
| `Parent_Object__c` | Distribution Object | Text(80) | required |

### Distribution Engine Details (`DE_Record_Detail__c`)

Classifier output and distribution state for one routed record.

Sharing: `ReadWrite`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Archived_At__c` | Archived At | DateTime |  |
| `Classifier_Status__c` | Classifier Status | Picklist | values: Waiting, Matching, Done |
| `Conversion_Result__c` | Conversion Result | Text(255) |  |
| `Domain__c` | Domain | Text(255) |  |
| `Failed_Attempts__c` | Failed Attempts | Number | default 0 |
| `Is_Archived__c` | Archived | Checkbox | default false |
| `Last_Error__c` | Last Error | TextArea |  |
| `Match_Confidence__c` | Match Confidence | Text(80) |  |
| `Matched_Account__c` | Matched Account | Lookup → Account |  |
| `Matched_Contact__c` | Matched Contact | Lookup → Contact |  |
| `Matched_Lead__c` | Matched Lead | Lookup → Lead |  |
| `Object_API_Name__c` | Object | Text(80) |  |
| `On_Hold_Until__c` | On Hold Until | DateTime |  |
| `Personal_Email__c` | Personal Email | Checkbox | default false |
| `Previous_Assignees__c` | Previous Assignees | LongTextArea | Most recent first, up to 50 User Ids. |
| `Record_Id__c` | Record Id | Text(18) | unique; external id / indexed |
| `Source_Queue_Id__c` | Source Queue Id | Text(18) |  |
| `Stamps__c` | Stamps | LongTextArea | Group:Value pairs separated by semicolons. |
| `Territory_Name__c` | Territory Name | Text(80) |  |
| `Territory__c` | Territory | Lookup → DE_Territory__c |  |

### Distribution Log (`DE_Assignment_Log__c`)

One row per assignment, reassignment or rejection. The full audit trail for routing.

Sharing: `Read`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Action_At__c` | Actioned At | DateTime |  |
| `Assigned_At__c` | Assignment Date | DateTime |  |
| `Assigned_User__c` | Assignee | Lookup → User |  |
| `Assignee_Id__c` | Assignee Id | Text(18) | User or queue Id. |
| `Balance_Value__c` | Balance Value | Number |  |
| `Counts_As_Hit__c` | Counts for Rotation | Checkbox | default true |
| `Current__c` | Current Assignment | Checkbox | default true |
| `Decision_Trace__c` | Decision Trace | LongTextArea |  |
| `Distributor__c` | Distributor | Lookup → DE_Distributor__c |  |
| `Is_Sticky__c` | Sticky | Checkbox | default false |
| `Last_SLA_Checkpoint__c` | Last SLA Checkpoint | Number | default 0 |
| `Message__c` | Message | TextArea |  |
| `Method__c` | Method | Text(80) |  |
| `Next_SLA_Check__c` | Next SLA Check | DateTime |  |
| `Object_API_Name__c` | Object | Text(80) |  |
| `Previous_Owner_Id__c` | Previous Owner Id | Text(18) |  |
| `Record_Created_At__c` | Record Created | DateTime |  |
| `Record_Id__c` | Record Id | Text(18) | external id / indexed |
| `Record_Name__c` | Record Name | Text(255) |  |
| `Reject_Reason__c` | Reject Reason | Text(255) |  |
| `SLA_Missed__c` | SLAs Missed | Number | default 0 |
| `SLA_Status__c` | SLA Status | Picklist | values: Not Applicable, Pending, Met, Missed, Cancelled |
| `Speed_To_Assign_Seconds__c` | Speed to Assign (Seconds) | Number |  |
| `Status__c` | Status | Picklist | values: Assigned, SLA Alert, Reassigned, Rejected, On Hold, Error, Simulated |
| `Sticky_Key__c` | Sticky Key | Text(255) | external id / indexed |
| `Team__c` | Team | Lookup → DE_Team__c |  |
| `Time_To_Action_Mins__c` | Time to Action (Minutes) | Number |  |
| `Type__c` | Type | Picklist | values: Standard, Pull, Manual, Trigger, Flow, Reassignment, Rejection |

### Engine Run Log (`DE_Run_Log__c`)

Scheduler, classifier, SLA, object sync, archive and health checker runs.

Sharing: `Read`.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Assignments__c` | Assignments | Number | default 0 |
| `Duration_Ms__c` | Duration (ms) | Number |  |
| `Errors__c` | Errors | Number | default 0 |
| `Message__c` | Message | LongTextArea |  |
| `Process__c` | Process | Picklist | values: Scheduler, Classifier, SLA Monitor, Object Sync, Archive, Health Checker, Dynamic Members, Purge |
| `Records_Processed__c` | Records Processed | Number | default 0 |
| `Started_At__c` | Started At | DateTime |  |
| `Status__c` | Status | Picklist | values: Success, Warning, Error |

### Distribution Engine Settings (`DE_Settings__c`)

Org-wide settings for Distribution Engine by NC Squared.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Allow_Other_Reject_Reason__c` | Allow Other Reject Reason | Checkbox | default true |
| `Archive_After_Days__c` | Archive After (Days) | Number | default 90 |
| `Archive_Enabled__c` | Auto Archive Enabled | Checkbox | default false |
| `Archive_Queue_Id__c` | Archive Queue Id | Text(18) |  |
| `Classifier_Enabled__c` | Classifier Enabled | Checkbox | default true |
| `Classifier_Objects__c` | Classifier Objects | Text(255) | Comma-separated objects classified on insert, e.g. Lead,Case,Account |
| `Count_Lookup_In_Balance__c` | Include Lookup Owner in Load Balancing | Checkbox | default true |
| `Count_Manual_As_Hit__c` | Count Manual Assignments in Rotation | Checkbox | default false |
| `Count_Pull_As_Hit__c` | Count Pull Assignments in Rotation | Checkbox | default true |
| `Count_Sticky_In_Balance__c` | Include Sticky in Load Balancing | Checkbox | default true |
| `Decision_Trace_Enabled__c` | Record Decision Trace | Checkbox | default true |
| `Default_Weekday_Start__c` | Week Starts On | Text(10) | Monday or Sunday |
| `Distribute_After_Classify__c` | Distribute Immediately After Classification | Checkbox | default true |
| `Engine_Enabled__c` | Engine Enabled | Checkbox | default true |
| `Hold_After_Failures__c` | Hold After Failed Attempts | Number | default 10 |
| `Hold_Minutes__c` | Hold Duration (Minutes) | Number | default 60 |
| `Log_Retention_Days__c` | Log Retention (Days) | Number | default 30 |
| `Personal_Domains__c` | Personal Email Domains | Text(255) |  |
| `Previous_Assignees_Tracked__c` | Number of Previous Assignees Tracked | Number | default 1 |
| `Publish_Platform_Events__c` | Publish Platform Events on Assignment | Checkbox | default true |
| `Records_Per_Run__c` | Records per Run | Number | default 500 |
| `Reject_Reasons__c` | Reject Reasons | Text(255) |  |
| `Require_Toggle_Reason__c` | Require Toggle Off Reason | Checkbox | default false |
| `Scheduler_Interval_Minutes__c` | Scheduler Interval (Minutes) | Number | default 1 |
| `Timer_Durations__c` | Timer Durations (Minutes) | Text(100) |  |
| `Timer_Toggles_Only__c` | Timer Toggles Only | Checkbox | default false |
| `Toggle_At_End_Of_Day__c` | Toggle Status at End of Day | Text(20) | No Change, Always On or Always Off |
| `Toggle_At_Start_Of_Day__c` | Toggle Status at Start of Day | Text(20) | No Change, Always On or Always Off |
| `Toggle_Reasons__c` | Toggle Off Reasons | Text(255) |  |
| `Trigger_Distribution_Enabled__c` | Process Trigger Distributors | Checkbox | default true |

### DE Assignment Event (`DE_Assignment_Event__e`)

Published after each assignment so widgets and integrations can react in real time.

| Field | Label | Type | Notes |
|---|---|---|---|
| `Assignee_Id__c` | Assignee Id | Text(18) |  |
| `Event_Type__c` | Event Type | Text(40) |  |
| `Object_API_Name__c` | Object | Text(80) |  |
| `Record_Id__c` | Record Id | Text(18) |  |
| `Record_Name__c` | Record Name | Text(255) |  |
| `Team_Name__c` | Team | Text(80) |  |

### Lead (standard object, fields added)

| Field | Label | Type | Notes |
|---|---|---|---|
| `DE_Action__c` | Distribution Action | Picklist | values: Contacted, Responded, Qualified, Not Reached |
| `DE_Distribution_Count__c` | Distribution Count | Number | default 0 |
| `DE_Is_Archived__c` | Is Archived | Checkbox | default false |
| `DE_Is_Distributed__c` | Is Distributed | Checkbox | default false |
| `DE_Is_Reassigned__c` | Is Reassigned | Checkbox | default false |
| `DE_Is_Rejected__c` | Is Rejected | Checkbox | default false |
| `DE_Is_Triggered__c` | Is Triggered | Checkbox | default false |
| `DE_Last_Archive_Date__c` | Last Archive Date | DateTime |  |
| `DE_Last_Distributed__c` | Last Distributed | DateTime |  |
| `DE_Last_Reassigned__c` | Last Reassigned | DateTime |  |
| `DE_Last_Rejected__c` | Last Rejected | DateTime |  |
| `DE_Source_Queue__c` | Source Queue Id | Text(18) |  |
| `DE_Territory__c` | DE Territory | Text(80) |  |
| `DE_Time_To_Action__c` | Time to Action (Minutes) | Number |  |
| `DE_Trigger_Distribution__c` | Distribute Now | Checkbox | default false; Check to run trigger distributors for this record on save. |

### Case (standard object, fields added)

| Field | Label | Type | Notes |
|---|---|---|---|
| `DE_Action__c` | Distribution Action | Picklist | values: Contacted, Responded, Qualified, Not Reached |
| `DE_Distribution_Count__c` | Distribution Count | Number | default 0 |
| `DE_Is_Archived__c` | Is Archived | Checkbox | default false |
| `DE_Is_Distributed__c` | Is Distributed | Checkbox | default false |
| `DE_Is_Reassigned__c` | Is Reassigned | Checkbox | default false |
| `DE_Is_Rejected__c` | Is Rejected | Checkbox | default false |
| `DE_Is_Triggered__c` | Is Triggered | Checkbox | default false |
| `DE_Last_Archive_Date__c` | Last Archive Date | DateTime |  |
| `DE_Last_Distributed__c` | Last Distributed | DateTime |  |
| `DE_Last_Reassigned__c` | Last Reassigned | DateTime |  |
| `DE_Last_Rejected__c` | Last Rejected | DateTime |  |
| `DE_Source_Queue__c` | Source Queue Id | Text(18) |  |
| `DE_Territory__c` | DE Territory | Text(80) |  |
| `DE_Time_To_Action__c` | Time to Action (Minutes) | Number |  |
| `DE_Trigger_Distribution__c` | Distribute Now | Checkbox | default false; Check to run trigger distributors for this record on save. |

### Opportunity (standard object, fields added)

| Field | Label | Type | Notes |
|---|---|---|---|
| `DE_Distribution_Count__c` | Distribution Count | Number | default 0 |
| `DE_Is_Distributed__c` | Is Distributed | Checkbox | default false |
| `DE_Is_Reassigned__c` | Is Reassigned | Checkbox | default false |
| `DE_Is_Rejected__c` | Is Rejected | Checkbox | default false |
| `DE_Is_Triggered__c` | Is Triggered | Checkbox | default false |
| `DE_Last_Distributed__c` | Last Distributed | DateTime |  |
| `DE_Last_Reassigned__c` | Last Reassigned | DateTime |  |
| `DE_Last_Rejected__c` | Last Rejected | DateTime |  |
| `DE_Territory__c` | DE Territory | Text(80) |  |
| `DE_Time_To_Action__c` | Time to Action (Minutes) | Number |  |
| `DE_Trigger_Distribution__c` | Distribute Now | Checkbox | default false; Check to run trigger distributors for this record on save. |

### Account (standard object, fields added)

| Field | Label | Type | Notes |
|---|---|---|---|
| `DE_Distribution_Count__c` | Distribution Count | Number | default 0 |
| `DE_Is_Distributed__c` | Is Distributed | Checkbox | default false |
| `DE_Is_Reassigned__c` | Is Reassigned | Checkbox | default false |
| `DE_Last_Distributed__c` | Last Distributed | DateTime |  |
| `DE_Last_Reassigned__c` | Last Reassigned | DateTime |  |
| `DE_Territory__c` | DE Territory | Text(80) |  |
| `DE_Time_To_Action__c` | Time to Action (Minutes) | Number |  |

### Contact (standard object, fields added)

| Field | Label | Type | Notes |
|---|---|---|---|
| `DE_Distribution_Count__c` | Distribution Count | Number | default 0 |
| `DE_Is_Distributed__c` | Is Distributed | Checkbox | default false |
| `DE_Is_Reassigned__c` | Is Reassigned | Checkbox | default false |
| `DE_Last_Distributed__c` | Last Distributed | DateTime |  |
| `DE_Last_Reassigned__c` | Last Reassigned | DateTime |  |
| `DE_Territory__c` | DE Territory | Text(80) |  |
| `DE_Time_To_Action__c` | Time to Action (Minutes) | Number |  |
