"""Data model for Distribution Engine by NC Squared (v2, modelled on the documented Teams -> Distributors design).
Run: python3 genmeta2.py <repo-root>"""
import os
from genmeta_lib import *  # noqa: F401,F403  (F, pick, write_object, write_field, ROOT, HDR, NS, escape)


def write_event(o):
    d = os.path.join(ROOT, o['api'])
    os.makedirs(d, exist_ok=True)
    xml = '\n'.join([HDR, f'<CustomObject xmlns="{NS}">',
                     '    <deploymentStatus>Deployed</deploymentStatus>',
                     f'    <description>{escape(o["desc"])}</description>',
                     '    <eventType>HighVolume</eventType>',
                     f'    <label>{escape(o["label"])}</label>',
                     f'    <pluralLabel>{escape(o["plural"])}</pluralLabel>',
                     '    <publishBehavior>PublishAfterCommit</publishBehavior>',
                     '</CustomObject>\n'])
    open(os.path.join(d, o['api'] + '.object-meta.xml'), 'w').write(xml)
    for f in o['fields']:
        f['setting'] = True
        write_field(o['api'], f)


def write_vr(obj, name, formula, message, field=None, desc=''):
    d = os.path.join(ROOT, obj, 'validationRules')
    os.makedirs(d, exist_ok=True)
    lines = [HDR, f'<ValidationRule xmlns="{NS}">', f'    <fullName>{name}</fullName>', '    <active>true</active>']
    if desc:
        lines.append(f'    <description>{escape(desc)}</description>')
    lines.append(f'    <errorConditionFormula>{escape(formula)}</errorConditionFormula>')
    if field:
        lines.append(f'    <errorDisplayField>{field}</errorDisplayField>')
    lines += [f'    <errorMessage>{escape(message)}</errorMessage>', '</ValidationRule>\n']
    open(os.path.join(d, name + '.validationRule-meta.xml'), 'w').write('\n'.join(lines))


OBJ_HELP = 'API name of the Salesforce object, e.g. Lead, Case, Opportunity or My_Object__c.'
ID_HELP = '18-character Id of a User or Queue.'
FIELD_UPD_HELP = 'One update per line: Field__c=Value. Picklist, multi-select picklist, text, number and checkbox fields are supported.'

CAP_PERIODS = ['Hourly', 'Half-hourly', 'Daily', 'Weekly', 'Monthly', 'Custom Minutes', 'Custom Hours', 'Custom Days', 'Active', 'Criteria']
METHODS = ['Round Robin', 'Load Balancing', 'Lookup Owner', 'Related Owner', 'Dynamic Owner', 'Current Owner']
DIST_TYPES = ['Standard', 'Pull', 'Manual', 'Trigger']
LOG_STATUS = ['Assigned', 'SLA Alert', 'Reassigned', 'Rejected', 'On Hold', 'Error', 'Simulated']
LOG_TYPES = ['Standard', 'Pull', 'Manual', 'Trigger', 'Flow', 'Reassignment', 'Rejection']
RESPECT_HOURS = ['Team and Member', 'Team Only', 'None']
PURPOSES = ['Team Filter', 'Distributor Filter', 'Member Filter', 'SLA Condition', 'Territory', 'Stamp', 'Conversion Filter',
            'Match Filter', 'Lookup Where', 'Cap Criteria', 'Dynamic Membership', 'Sync Filter', 'Delay Filter']
OPERATORS = ['equals', 'not equals', 'less than', 'greater than', 'less or equal', 'greater or equal', 'contains',
             'does not contain', 'starts with', 'does not start with', 'ends with', 'does not end with', 'in', 'not in',
             'includes', 'includes all', 'does not include', 'between', 'is blank', 'is not blank']

teams = dict(api='DE_Team__c', label='Distribution Team', plural='Distribution Teams', name_label='Team Name', history=True,
    desc='A team distributes one object to its members through ordered distributors. Teams run in execution order.',
    fields=[
        F('Object_API_Name__c', 'Distribution Object', 'Text', length=80, required=True, help=OBJ_HELP + ' Cannot be changed after the team is created.', track=True),
        F('Active__c', 'Active', 'Checkbox', default=False, track=True),
        F('Execution_Order__c', 'Execution Order', 'Number', precision=6, default=10, help='Teams run top to bottom by this number.', track=True),
        F('Team_Type__c', 'Team Type', 'Picklist', picklist=pick(['Standard', 'Queue to Queue'], 'Standard'), help='Queue to Queue teams assign records from a source queue to member queues instead of people.'),
        F('Assignment_Field__c', 'Assignment Field', 'Text', length=120, help='User lookup field written by this team. Defaults to OwnerId. Can only be changed while the team has no distributors.', track=True),
        F('Filter_Logic__c', 'Team Filter Logic', 'Text', length=255, help='Optional logic for team filters, e.g. (1 AND 2) OR 3. Team filters apply to every distributor.'),
        F('Team_Hours__c', 'Team Hours', 'Lookup', ref='DE_Shift__c', rname='Teams', rlabel='Teams Using This Shift', help='Distribution hours for the team. Members without their own shift inherit these hours.'),
        F('Holiday_Region__c', 'Holiday Region', 'Text', length=80, help='Regional holidays in this region stop distribution for the whole team.'),
        F('Round_Robin_Level__c', 'Round Robin Level', 'Picklist', picklist=pick(['Team', 'Distributor'], 'Team'), help='Team: one rotation shared by all distributors. Distributor: each distributor rotates independently.'),
        F('Load_Balancing_Level__c', 'Load Balancing Level', 'Picklist', picklist=pick(['Team', 'Distributor'], 'Team')),
        F('Load_Balancing_Type__c', 'Load Balancing Type', 'Picklist', picklist=pick(['Daily', 'Weekly', 'Monthly', 'Active'], 'Daily'), help='Daily, Weekly and Monthly balance Distribution Engine assignments. Active balances all owned records in Active Status (or all owned records when no Active Status is set).'),
        F('Balance_By__c', 'Active Cap and Balance By', 'Picklist', picklist=pick(['Record Count', 'Field Value'], 'Record Count')),
        F('Balance_Field__c', 'Balance Field', 'Text', length=120, help='Numeric field summed when balancing by Field Value. Values are truncated to whole numbers.'),
        F('Active_Status_Field__c', 'Active Status Field', 'Text', length=120, help='Picklist field that marks a record as active (still being worked), e.g. Status.'),
        F('Active_Status_Values__c', 'Active Status Values', 'TextArea', help='Semicolon-separated values of the Active Status Field, e.g. New;Working.'),
        F('Apply_Active_Status_To_SLAs__c', 'Apply Active Status to SLAs', 'Checkbox', default=True),
        F('Weighting_Mode__c', 'Weighting Mode', 'Picklist', picklist=pick(['Individual', 'Tag'], 'Individual')),
        F('Tag_Weights__c', 'Tag Weights', 'TextArea', help='Tag weighting, one per line: Collection:Tag=Weight. The highest weighted tag a member has is used.'),
        F('Default_Tag_Weight__c', 'Default Tag Weight', 'Number', precision=4, scale=2, default=1),
        F('Respect_Hours_For_Triggers__c', 'Respect Distribution Hours for Triggers', 'Checkbox', default=False),
        F('Rejection_Limit__c', 'Rejection Limit', 'Picklist', picklist=pick(['Unlimited', 'Manager Only', 'Limited'], 'Unlimited')),
        F('Rejections_Per_Day__c', 'Rejections Per Day', 'Number', precision=4, default=3),
        F('Action_Tracking_Enabled__c', 'Action Tracking', 'Checkbox', default=False),
        F('Action_Field__c', 'Action Field', 'Text', length=120, help='Picklist that records the action, e.g. DE_Action__c or Status.'),
        F('Tracked_Actions__c', 'Actions to Track', 'TextArea', help='Semicolon-separated values of the action field that count as actioned.'),
        F('Action_Respect_Hours__c', 'Action Tracking Hours', 'Picklist', picklist=pick(RESPECT_HOURS, 'Team and Member')),
        F('Track_Action_From_Any_User__c', 'Track Action From Any User', 'Checkbox', default=False),
        F('Auto_Action_Activity_Types__c', 'Auto Action Activity Types', 'Text', length=255, help='Semicolon-separated Task/Event Type values that set the action automatically, e.g. Call;Email.'),
        F('SLA_Respect_Hours__c', 'SLA Hours', 'Picklist', picklist=pick(RESPECT_HOURS, 'Team and Member')),
        F('Object_Sync_Enabled__c', 'Object Sync', 'Checkbox', default=False, help='Run active Object Sync actions for this object after assignment.'),
        F('Manager_User_Ids__c', 'Team Managers', 'TextArea', help='Comma-separated User Ids allowed to manage this team with the Team Manager permission set.'),
        F('Dynamic_Members_Enabled__c', 'Dynamic Team Members', 'Checkbox', default=False, help='Keep membership in sync with Dynamic Membership conditions on User fields.'),
        F('Dynamic_Members_Logic__c', 'Dynamic Member Logic', 'Text', length=255),
        F('Rotation_Sequence__c', 'Rotation Sequence', 'Number', precision=18, default=0, help='Internal counter. Do not edit.'),
        F('Total_Assignments__c', 'Total Assignments', 'Number', precision=18, default=0),
        F('Last_Assigned_At__c', 'Last Assigned At', 'DateTime'),
        F('Description__c', 'Description', 'TextArea'),
    ])

members = dict(api='DE_Team_Member__c', label='Team Member', plural='Team Members', name_label='Member Number', autonumber='TM-{000000}', history=True,
    sharing='ControlledByParent', desc='A user (or queue, for Queue to Queue teams) who receives assignments from a team.',
    fields=[
        F('Team__c', 'Team', 'MasterDetail', ref='DE_Team__c', rname='Members', rlabel='Team Members'),
        F('User__c', 'User', 'Lookup', ref='User', rname='DE_Team_Memberships', rlabel='Distribution Team Memberships'),
        F('Queue_Id__c', 'Queue Id', 'Text', length=18, help='Queue member for Queue to Queue teams.'),
        F('Active__c', 'Active', 'Checkbox', default=True, track=True),
        F('Weight__c', 'Weight', 'Number', precision=4, scale=2, default=1, help='0.25 to 4. Weight 2 receives two assignments per round robin cycle; 0.5 is skipped every other cycle.', track=True),
        F('Member_Hours__c', 'Member Hours', 'Lookup', ref='DE_Shift__c', rname='Team_Members', rlabel='Team Members Using This Shift', help='Overrides team hours for this member.'),
        F('Dynamic__c', 'Added Dynamically', 'Checkbox', default=False),
        F('Unique_Key__c', 'Unique Key', 'Text', length=40, unique=True, external=True, help='Team Id + member Id. Prevents duplicate memberships.'),
    ])

distributors = dict(api='DE_Distributor__c', label='Distributor', plural='Distributors', name_label='Distributor Name', history=True,
    sharing='ControlledByParent', desc='The rules that decide how, from where and to whom a team assigns records. Distributors run in order.',
    fields=[
        F('Team__c', 'Team', 'MasterDetail', ref='DE_Team__c', rname='Distributors', rlabel='Distributors'),
        F('Order__c', 'Order', 'Number', precision=6, default=10, track=True),
        F('Active__c', 'Active', 'Checkbox', default=False, track=True),
        F('Type__c', 'Distributor Type', 'Picklist', picklist=pick(DIST_TYPES, 'Standard'), help='Standard: scheduler pushes records. Pull: members pull records. Manual: managers pick the member. Trigger: assigns immediately when the record is flagged on update.', track=True),
        F('Method__c', 'Method', 'Picklist', picklist=pick(METHODS, 'Round Robin'), track=True),
        F('Source_Type__c', 'Source', 'Picklist', picklist=pick(['Queue', 'User', 'Field Value', 'Any'], 'Queue'), help='Where records are taken from. Any is only valid for Trigger and Manual distributors.'),
        F('Source_Id__c', 'Source Queue or User Id', 'Text', length=18),
        F('Source_Field__c', 'Source Field', 'Text', length=120, help='Field Value source: picklist field that marks records ready.'),
        F('Source_Ready_Value__c', 'Ready Value', 'Text', length=255),
        F('Source_After_Value__c', 'Value After Assignment', 'Text', length=255),
        F('Filter_Logic__c', 'Filter Logic', 'Text', length=255),
        F('Sort_Order__c', 'Sort Order', 'Text', length=255, help='Comma-separated fields with optional ASC or DESC, e.g. Rating DESC, CreatedDate ASC. Default is CreatedDate ASC.'),
        F('Assign_To__c', 'Assign To', 'Picklist', picklist=pick(['All Team Members', 'Selected Members'], 'All Team Members')),
        F('Selected_Member_Ids__c', 'Selected Members', 'TextArea', help='Comma-separated User or Queue Ids.'),
        F('Exclude_Members_Field__c', 'Exclude Members Field', 'Text', length=120, help='Text or user lookup field on the record holding comma-separated User Ids that must not receive it.'),
        F('Assign_If_Unavailable__c', 'Assign if User Is Unavailable', 'Checkbox', default=False, help='Ignore out of office, distribution hours and toggle. Holidays are always respected.'),
        F('Assign_If_Offline__c', 'Assign if User Is Offline in Widget', 'Checkbox', default=False),
        F('Weighting_Enabled__c', 'Weighting Enabled', 'Checkbox', default=True),
        F('Respect_Team_Caps__c', 'Respect Team Caps', 'Checkbox', default=True),
        F('Sticky_Enabled__c', 'Sticky Assignment', 'Checkbox', default=False),
        F('Sticky_Field__c', 'Sticky Match Field', 'Text', length=120),
        F('Sticky_Days__c', 'Sticky Period (Days)', 'Number', precision=4, default=90),
        F('Sticky_Level__c', 'Sticky Match Level', 'Picklist', picklist=pick(['Distributor', 'Team', 'Global'], 'Distributor')),
        F('Sticky_Retain_Unavailable__c', 'Retain Sticky When Unavailable', 'Checkbox', default=False),
        F('Sticky_Retain_Offline__c', 'Retain Sticky When Offline', 'Checkbox', default=False),
        F('Sticky_Only__c', 'Disable Round Robin (Sticky Only)', 'Checkbox', default=False),
        F('Sticky_Cap_Behaviour__c', 'Sticky Cap Behaviour', 'Picklist', picklist=pick(['Ignore Caps', 'Respect Caps - Assign to Next Member', "Respect Caps - Don't Assign"], 'Ignore Caps')),
        F('Lookup_Object__c', 'Lookup To', 'Text', length=80),
        F('Lookup_Record_Field__c', 'Lookup Record Field', 'Text', length=120),
        F('Lookup_Target_Field__c', 'Lookup Target Field', 'Text', length=120),
        F('Lookup_Where_Logic__c', 'Lookup Where Logic', 'Text', length=255),
        F('Lookup_Assign_Field__c', 'Lookup Assign To', 'Text', length=255, help='User field on the matched record, e.g. OwnerId or Account.OwnerId.'),
        F('Lookup_Tie_Breaker_Field__c', 'Tie Breaker Field', 'Text', length=120),
        F('Lookup_Tie_Breaker_Direction__c', 'Tie Breaker Direction', 'Picklist', picklist=pick(['Newest or Highest', 'Oldest or Lowest'], 'Newest or Highest')),
        F('Related_Field__c', 'Assign Using Related Object', 'Text', length=255, help='Lookup path whose owner receives the record, e.g. DE.MatchedAccount or AccountId.'),
        F('Related_Secondary_Field__c', 'Otherwise Use Related Object', 'Text', length=255),
        F('Dynamic_Owner_Field__c', 'Dynamic Owner Field', 'Text', length=120, help='Field holding the User Id to assign to (Trigger distributors).'),
        F('Default_Owner_Id__c', 'Default Owner Id', 'Text', length=18, help='Trigger distributors: owner used when no member can be assigned.'),
        F('Pull_Count__c', 'Number of Records to Pull', 'Number', precision=3, default=1),
        F('Field_Updates__c', 'Update Fields on Assignment', 'TextArea', help=FIELD_UPD_HELP),
        F('Send_Email__c', 'Email Notification', 'Checkbox', default=False),
        F('Send_Notification__c', 'Salesforce Notification', 'Checkbox', default=True),
        F('SLA_Enabled__c', 'SLAs Enabled', 'Checkbox', default=False),
        F('Auto_Reassign__c', 'Auto Reassign', 'Checkbox', default=False),
        F('Reassign_From_SLA__c', 'Reassign From SLA', 'Number', precision=1, default=1, help='Missing this checkpoint or any later one reassigns the record.'),
        F('Reassign_To_Id__c', 'Reassign To', 'Text', length=18, help='Queue (to redistribute) or User. ' + ID_HELP),
        F('Reassign_Field_Updates__c', 'Update Fields on Reassignment', 'TextArea', help=FIELD_UPD_HELP),
        F('Toggle_User_Off__c', 'Toggle User Off on Reassignment', 'Checkbox', default=False),
        F('Remove_Sticky_On_Reassign__c', 'Remove Sticky on Reassignment', 'Picklist', picklist=pick(['New Sticky Only', 'Always', 'Never'], 'New Sticky Only')),
        F('Rejection_Enabled__c', 'Assignment Rejection', 'Checkbox', default=False),
        F('Reject_To_Id__c', 'Reject To', 'Text', length=18, help=ID_HELP),
        F('Reject_Field_Updates__c', 'Update Fields on Rejection', 'TextArea', help=FIELD_UPD_HELP),
        F('Replace_Rejected__c', 'Replace Rejected Records', 'Picklist', picklist=pick(['Replace on Usual Assignment', 'Replace as Next Assignment', "Don't Replace"], 'Replace on Usual Assignment')),
        F('Treat_Manual_As_Rejection__c', 'Treat Manual Assignment as Rejection', 'Checkbox', default=False),
        F('Description__c', 'Description', 'TextArea'),
    ])

conditions = dict(api='DE_Condition__c', label='Condition', plural='Conditions', name_label='Condition Number', autonumber='C-{0000000}',
    desc='One filter row (Field / Operator / Value) used by teams, distributors, SLAs, classifier rules, caps and object sync.',
    fields=[
        F('Team__c', 'Team', 'Lookup', ref='DE_Team__c', rname='Conditions', rlabel='Conditions'),
        F('Distributor__c', 'Distributor', 'Lookup', ref='DE_Distributor__c', rname='Conditions', rlabel='Conditions'),
        F('SLA__c', 'SLA', 'Lookup', ref='DE_SLA__c', rname='Conditions', rlabel='Conditions'),
        F('Territory__c', 'Territory', 'Lookup', ref='DE_Territory__c', rname='Conditions', rlabel='Conditions'),
        F('Stamp__c', 'Stamp', 'Lookup', ref='DE_Stamp__c', rname='Conditions', rlabel='Conditions'),
        F('Conversion_Rule__c', 'Conversion Rule', 'Lookup', ref='DE_Conversion_Rule__c', rname='Conditions', rlabel='Conditions'),
        F('Matching_Rule__c', 'Matching Rule', 'Lookup', ref='DE_Matching_Rule__c', rname='Conditions', rlabel='Conditions'),
        F('Cap__c', 'Cap', 'Lookup', ref='DE_Cap__c', rname='Conditions', rlabel='Conditions'),
        F('Object_Sync__c', 'Object Sync', 'Lookup', ref='DE_Object_Sync__c', rname='Conditions', rlabel='Conditions'),
        F('Purpose__c', 'Purpose', 'Picklist', picklist=pick(PURPOSES, 'Distributor Filter')),
        F('Sequence__c', 'Sequence', 'Number', precision=4, required=True, help='Row number referenced from filter logic.'),
        F('Field_API_Name__c', 'Field', 'Text', length=255, required=True, help='Field API name or path (Account.Industry), DE classifier value (DE.Territory, DE.Stamp.Priority, DE.MatchedAccount.Type) or, for member filters, Tag:Collection / DynamicTag:Collection / Territory.'),
        F('Operator__c', 'Operator', 'Picklist', picklist=pick(OPERATORS, 'equals')),
        F('Value__c', 'Value', 'Text', length=255, help='Lists use semicolons. Dates accept TODAY, NOW, an absolute date or "n minutes/hours/days ago". between uses low..high.'),
    ])

sla = dict(api='DE_SLA__c', label='SLA Checkpoint', plural='SLA Checkpoints', name_label='SLA Name', history=True, sharing='ControlledByParent',
    desc='A team SLA checkpoint: after N minutes, if the conditions are true the SLA is missed.',
    fields=[
        F('Team__c', 'Team', 'MasterDetail', ref='DE_Team__c', rname='SLAs', rlabel='SLA Checkpoints'),
        F('Checkpoint__c', 'Checkpoint', 'Number', precision=1, required=True, help='1, 2 or 3 in chronological order.'),
        F('Alert_Type__c', 'Alert Type', 'Picklist', picklist=pick(['Time Checkpoint', 'Continuous Field Monitoring', 'Custom Date/Time'], 'Time Checkpoint')),
        F('Minutes_After_Assignment__c', 'Time Since Assignment (Minutes)', 'Number', precision=8, help='Time Checkpoint: check this many minutes after assignment. Continuous Field Monitoring: monitor for this long (max 20160).'),
        F('Check_After_Field__c', 'SLA Check After Field', 'Text', length=120, help='Custom Date/Time: date/time field holding when to check.'),
        F('Condition_Logic__c', 'SLA Missed If Logic', 'Text', length=255),
        F('Stamp_Value__c', 'Stamp', 'Text', length=255, help='Stamp SLAs: only applies to records with this stamp, e.g. Priority:Critical.'),
        F('Notify_Assignee__c', 'Notify Assignee', 'Checkbox', default=True),
        F('Notify_Manager__c', 'Notify Manager', 'Checkbox', default=False),
        F('Active__c', 'Active', 'Checkbox', default=True),
    ])

caps = dict(api='DE_Cap__c', label='Cap', plural='Caps', name_label='Cap Name',
    desc='A team-level or distributor-level cap on the number of assignments per period, active records or records matching criteria.',
    fields=[
        F('Team__c', 'Team', 'Lookup', ref='DE_Team__c', rname='Caps', rlabel='Team Caps'),
        F('Distributor__c', 'Distributor', 'Lookup', ref='DE_Distributor__c', rname='Caps', rlabel='Distributor Caps'),
        F('Period__c', 'Period', 'Picklist', picklist=pick(CAP_PERIODS, 'Daily')),
        F('Custom_Length__c', 'Custom Period Length', 'Number', precision=4, help='Minutes 5-180, Hours 1-168 or Days 1-31. Custom caps are rolling.'),
        F('Default_Cap__c', 'Default Cap', 'Number', precision=8, help='Blank means unlimited.'),
        F('Tag_Caps__c', 'Caps by Tag', 'TextArea', help='One per line: Collection:Tag=Cap. Blank cap value means unlimited for that tag.'),
        F('Criteria_Logic__c', 'Criteria Logic', 'Text', length=255),
        F('Criteria_Source__c', 'Criteria Source', 'Picklist', picklist=pick(['Field', 'Distributor Filters'], 'Field')),
        F('Active__c', 'Active', 'Checkbox', default=True),
    ])

rotation = dict(api='DE_Rotation_State__c', label='Rotation State', plural='Rotation States', name_label='Scope Key',
    desc='Internal round robin and weighting state per scope (team or distributor) and member.',
    fields=[
        F('Team__c', 'Team', 'Lookup', ref='DE_Team__c', rname='Rotation_States', rlabel='Rotation States'),
        F('Scope_Key__c', 'Scope Key', 'Text', length=60, unique=True, external=True),
        F('Member_Key__c', 'Member Id', 'Text', length=18),
        F('Last_Sequence__c', 'Last Sequence', 'Number', precision=18, default=0),
        F('Credit__c', 'Weighting Credit', 'Number', precision=10, scale=4, default=0),
        F('Cycle__c', 'Cycle', 'Number', precision=18, default=0),
        F('Replacement_Credits__c', 'Replacement Credits', 'Number', precision=6, default=0, help='Rejected records owed back to this member (Replace on Usual Assignment).'),
    ])

shift = dict(api='DE_Shift__c', label='Shift', plural='Shifts', name_label='Shift Name', history=True,
    desc='Reusable weekly working pattern in a timezone with up to three blocks per day.',
    fields=[
        F('Timezone__c', 'Timezone', 'Text', length=60, required=True, help='IANA timezone, e.g. Europe/London or America/New_York.'),
        F('Schedule__c', 'Schedule', 'LongTextArea', length=4000, lines=8, help='JSON: {"MON":["09:00-12:00","13:00-17:30"],"TUE":[...]} . Use +1 for blocks ending after midnight, e.g. 22:00-06:00+1.'),
        F('Description__c', 'Description', 'TextArea'),
    ])

holiday = dict(api='DE_Holiday__c', label='Regional Holiday', plural='Regional Holidays', name_label='Holiday Name', history=True,
    desc='A holiday in a holiday region. Teams in the region do not distribute during it.',
    fields=[
        F('Region__c', 'Region', 'Text', length=80, required=True),
        F('All_Day__c', 'All Day', 'Checkbox', default=True),
        F('Start__c', 'Starts', 'DateTime', required=True),
        F('End__c', 'Ends', 'DateTime', required=True),
        F('Timezone__c', 'Timezone', 'Text', length=60),
    ])

ooo = dict(api='DE_Out_Of_Office__c', label='Out of Office', plural='Out of Office', name_label='OOO Number', autonumber='OOO-{000000}', history=True,
    desc='A period when a user (or queue) receives no assignments from any team.',
    fields=[
        F('User__c', 'User', 'Lookup', ref='User', rname='DE_Out_Of_Office', rlabel='Distribution Out of Office'),
        F('Queue_Id__c', 'Queue Id', 'Text', length=18),
        F('Start__c', 'Start', 'DateTime', required=True),
        F('End__c', 'End', 'DateTime', required=True),
        F('All_Day__c', 'All Day', 'Checkbox', default=False),
        F('Reason__c', 'Reason', 'Text', length=80),
        F('Source__c', 'Source', 'Picklist', picklist=pick(['Manual', 'Calendar', 'API'], 'Manual')),
    ])

agent = dict(api='DE_Agent__c', label='User Availability', plural='User Availability', name_label='Name', history=True,
    desc='Availability toggle and tags for one user.',
    fields=[
        F('User__c', 'User', 'Lookup', ref='User', rname='DE_Availability', rlabel='Distribution Availability'),
        F('Online__c', 'Online', 'Checkbox', default=True, track=True),
        F('Toggle_Reason__c', 'Toggle Off Reason', 'Text', length=80, track=True),
        F('Toggle_Until__c', 'Toggled Off Until', 'DateTime', help='Timer toggle: the user comes back online automatically at this time.'),
        F('Tags__c', 'Tags', 'LongTextArea', length=4000, lines=3, help='Semicolon-separated Collection:Tag values, e.g. Language:English;Tier:Gold.'),
        F('Last_Status_Change__c', 'Last Status Change', 'DateTime'),
        F('Unique_User__c', 'Unique User', 'Text', length=18, unique=True, external=True),
    ])

avail_event = dict(api='DE_Availability_Event__c', label='Availability History', plural='Availability History', name_label='Event Number', autonumber='AV-{00000000}',
    sharing='Read', desc='Audit of every availability toggle: who, when, by whom and why.',
    fields=[
        F('User__c', 'User', 'Lookup', ref='User', rname='DE_Availability_Events', rlabel='Distribution Availability History'),
        F('Online__c', 'Online', 'Checkbox', default=False),
        F('Reason__c', 'Reason', 'Text', length=80),
        F('Changed_By__c', 'Changed By', 'Lookup', ref='User', rname='DE_Availability_Changes', rlabel='Availability Changes Made'),
        F('Changed_At__c', 'Changed At', 'DateTime'),
        F('Source__c', 'Source', 'Picklist', picklist=pick(['User', 'Manager', 'Timer', 'Start of Day', 'End of Day', 'Auto Reassign', 'API'], 'User')),
    ])

territory = dict(api='DE_Territory__c', label='Territory', plural='Territories', name_label='Territory Name', history=True,
    desc='Classifier territory. Records are stamped with the first matching territory (smallest first). Member filters route by territory.',
    fields=[
        F('Object_API_Name__c', 'Object', 'Text', length=80, required=True, help=OBJ_HELP),
        F('Map__c', 'Map', 'Text', length=80, help='Group of territories. Leave blank for the default map.'),
        F('Status__c', 'Status', 'Picklist', picklist=pick(['Draft', 'Active'], 'Draft'), track=True),
        F('Priority__c', 'Order', 'Number', precision=6, required=True, help='Evaluated smallest number first. Put postal-code territories before states and states before countries.'),
        F('Condition_Logic__c', 'Condition Logic', 'Text', length=255),
        F('Countries__c', 'Countries', 'TextArea', help='Semicolon-separated country names or ISO codes.'),
        F('States__c', 'States', 'TextArea', help='Semicolon-separated state names or codes.'),
        F('Postal_Codes__c', 'Postal Codes', 'LongTextArea', length=32768, lines=4, help='Semicolon-separated postal codes, prefixes ending in * or ranges low..high.'),
        F('Stamp_Field__c', 'Stamp Field', 'Text', length=120, help='Optional field on the record that also receives the territory name. Defaults to DE_Territory__c when present.'),
        F('Description__c', 'Description', 'TextArea'),
    ])

matching = dict(api='DE_Matching_Rule__c', label='Lead Matching Rule', plural='Lead Matching Rules', name_label='Rule Name', history=True,
    desc='Classifier lead matching to accounts, contacts or existing leads.',
    fields=[
        F('Active__c', 'Active', 'Checkbox', default=True, track=True),
        F('Match_Type__c', 'Match Type', 'Picklist', picklist=pick(['Lead to Account', 'Lead to Contact', 'Lead to Lead'], 'Lead to Account')),
        F('Priority__c', 'Order', 'Number', precision=6, required=True),
        F('Match_Email_Domain__c', 'Email Domain Matching', 'Checkbox', default=True, help='Lead to Account: lead email domain matches account website or contact email domains. Email domain takes priority over website. Personal domains never match.'),
        F('Match_Company_Name__c', 'Company Name Matching', 'Checkbox', default=True, help='Normalised: case, punctuation and suffixes like Inc, Ltd, LLC are ignored. Fuzzy similarity is scored.'),
        F('Fuzzy_Threshold__c', 'Fuzzy Match Threshold (%)', 'Number', precision=3, default=85),
        F('Match_Email__c', 'Email Address Matching', 'Checkbox', default=True, help='Lead to Contact / Lead to Lead: exact email.'),
        F('Source_Field__c', 'Custom Lead Field', 'Text', length=120),
        F('Target_Field__c', 'Custom Target Field', 'Text', length=120),
        F('Filter_Logic__c', 'Match Filter Logic', 'Text', length=255, help='Logic for Match Filter conditions applied to the candidate records.'),
        F('Tie_Breaker_Field__c', 'Multiple Match Order Field', 'Text', length=120, help='Default LastModifiedDate.'),
        F('Tie_Breaker_Direction__c', 'Multiple Match Direction', 'Picklist', picklist=pick(['Newest or Highest', 'Oldest or Lowest'], 'Newest or Highest')),
        F('Description__c', 'Description', 'TextArea'),
    ])

conversion = dict(api='DE_Conversion_Rule__c', label='Auto-Conversion Rule', plural='Auto-Conversion Rules', name_label='Rule Name', history=True,
    desc='Ordered lead auto-conversion and de-duplication rules. The default rule runs last.',
    fields=[
        F('Active__c', 'Active', 'Checkbox', default=True, track=True),
        F('Order__c', 'Order', 'Number', precision=6, required=True),
        F('Is_Default__c', 'Default Rule', 'Checkbox', default=False),
        F('Match__c', 'Match', 'Picklist', picklist=pick(['Any', 'No Match', 'Account and Contact Match', 'Account Only Match', 'Lead Only Match'], 'Any')),
        F('Filter_Logic__c', 'Filter Logic', 'Text', length=255),
        F('Action__c', 'Action', 'Picklist', picklist=pick(['Do Not Convert', 'Auto Convert', 'De-Duplicate'], 'Do Not Convert'), track=True),
        F('Create_Opportunity__c', 'Create Opportunity', 'Picklist', picklist=pick(['Never', 'Always', 'Only When No Open Opportunity'], 'Never')),
        F('Owner_Source__c', 'Owner', 'Picklist', picklist=pick(['Matched Record Owner', 'Retain Lead Owner', 'Default User'], 'Matched Record Owner')),
        F('Default_User_Id__c', 'Default User Id', 'Text', length=18),
        F('Converted_Status__c', 'Converted Lead Status', 'Text', length=80),
        F('Account_Field_Update__c', 'Account Field Update', 'Text', length=255, help='Field__c=Value'),
        F('Contact_Field_Update__c', 'Contact Field Update', 'Text', length=255),
        F('Opportunity_Field_Update__c', 'Opportunity Field Update', 'Text', length=255),
        F('Copy_Blank_Fields__c', 'Copy Values Into Blank Fields', 'Checkbox', default=True, help='De-duplicate: copy values from the duplicate into blank fields on the surviving lead.'),
        F('Survivor_Field_Update__c', 'Surviving Lead Field Update', 'Text', length=255),
        F('Description__c', 'Description', 'TextArea'),
    ])

stamp_group = dict(api='DE_Stamp_Group__c', label='Stamp Group', plural='Stamp Groups', name_label='Group Name', history=True,
    desc='Custom classification category, e.g. Priority, whose stamps are evaluated in order.',
    fields=[
        F('Object_API_Name__c', 'Object', 'Text', length=80, required=True),
        F('Active__c', 'Active', 'Checkbox', default=True),
        F('Group_Type__c', 'Group Type', 'Picklist', picklist=pick(['Single', 'Multiple'], 'Single'), help='Single stops at the first matching stamp. Multiple applies every matching stamp.'),
        F('Stamp_Field__c', 'Stamp Field', 'Text', length=120, help='Optional record field that also receives the stamp value(s).'),
        F('Description__c', 'Description', 'TextArea'),
    ])

stamp = dict(api='DE_Stamp__c', label='Stamp', plural='Stamps', name_label='Stamp Value', sharing='ControlledByParent',
    desc='A value of a stamp group with the filters that award it.',
    fields=[
        F('Stamp_Group__c', 'Stamp Group', 'MasterDetail', ref='DE_Stamp_Group__c', rname='Stamps', rlabel='Stamps'),
        F('Order__c', 'Order', 'Number', precision=6, required=True),
        F('Condition_Logic__c', 'Condition Logic', 'Text', length=255),
    ])

objsync = dict(api='DE_Object_Sync__c', label='Object Sync Action', plural='Object Sync Actions', name_label='Action Name', history=True,
    desc='When a parent record is assigned, child records related by a lookup take the new owner.',
    fields=[
        F('Parent_Object__c', 'Distribution Object', 'Text', length=80, required=True),
        F('Child_Object__c', 'Related Object', 'Text', length=80, required=True),
        F('Lookup_Field__c', 'Related Lookup Field', 'Text', length=120, required=True, help='Lookup on the related object pointing at the distribution object, e.g. WhoId or AccountId.'),
        F('Filter_Logic__c', 'Filter Logic', 'Text', length=255),
        F('Active__c', 'Active', 'Checkbox', default=False, track=True),
    ])

details = dict(api='DE_Record_Detail__c', label='Distribution Engine Details', plural='Distribution Engine Details', name_label='Detail Number', autonumber='DD-{00000000}',
    desc='Classifier output and distribution state for one routed record.',
    fields=[
        F('Record_Id__c', 'Record Id', 'Text', length=18, unique=True, external=True),
        F('Object_API_Name__c', 'Object', 'Text', length=80),
        F('Classifier_Status__c', 'Classifier Status', 'Picklist', picklist=pick(['Waiting', 'Matching', 'Done'], 'Waiting')),
        F('Territory__c', 'Territory', 'Lookup', ref='DE_Territory__c', rname='Record_Details', rlabel='Classified Records'),
        F('Territory_Name__c', 'Territory Name', 'Text', length=80),
        F('Matched_Account__c', 'Matched Account', 'Lookup', ref='Account', rname='DE_Matched_Records', rlabel='Distribution Engine Matches'),
        F('Matched_Contact__c', 'Matched Contact', 'Lookup', ref='Contact', rname='DE_Matched_Records', rlabel='Distribution Engine Matches'),
        F('Matched_Lead__c', 'Matched Lead', 'Lookup', ref='Lead', rname='DE_Matched_Records', rlabel='Distribution Engine Matches'),
        F('Match_Confidence__c', 'Match Confidence', 'Text', length=80),
        F('Domain__c', 'Domain', 'Text', length=255),
        F('Personal_Email__c', 'Personal Email', 'Checkbox', default=False),
        F('Stamps__c', 'Stamps', 'LongTextArea', length=4000, lines=3, help='Group:Value pairs separated by semicolons.'),
        F('Conversion_Result__c', 'Conversion Result', 'Text', length=255),
        F('Failed_Attempts__c', 'Failed Attempts', 'Number', precision=6, default=0),
        F('On_Hold_Until__c', 'On Hold Until', 'DateTime'),
        F('Last_Error__c', 'Last Error', 'TextArea'),
        F('Previous_Assignees__c', 'Previous Assignees', 'LongTextArea', length=2000, lines=3, help='Most recent first, up to 50 User Ids.'),
        F('Source_Queue_Id__c', 'Source Queue Id', 'Text', length=18),
        F('Is_Archived__c', 'Archived', 'Checkbox', default=False),
        F('Archived_At__c', 'Archived At', 'DateTime'),
    ])

log = dict(api='DE_Assignment_Log__c', label='Distribution Log', plural='Distribution Logs', name_label='Log Number', autonumber='DL-{000000000}',
    sharing='Read', desc='One row per assignment, reassignment or rejection. The full audit trail for routing.',
    fields=[
        F('Record_Id__c', 'Record Id', 'Text', length=18, external=True),
        F('Object_API_Name__c', 'Object', 'Text', length=80),
        F('Record_Name__c', 'Record Name', 'Text', length=255),
        F('Team__c', 'Team', 'Lookup', ref='DE_Team__c', rname='Logs', rlabel='Distribution Logs'),
        F('Distributor__c', 'Distributor', 'Lookup', ref='DE_Distributor__c', rname='Logs', rlabel='Distribution Logs'),
        F('Assigned_User__c', 'Assignee', 'Lookup', ref='User', rname='DE_Logs', rlabel='Distribution Logs'),
        F('Assignee_Id__c', 'Assignee Id', 'Text', length=18, help='User or queue Id.'),
        F('Previous_Owner_Id__c', 'Previous Owner Id', 'Text', length=18),
        F('Method__c', 'Method', 'Text', length=80),
        F('Type__c', 'Type', 'Picklist', picklist=pick(LOG_TYPES, 'Standard')),
        F('Status__c', 'Status', 'Picklist', picklist=pick(LOG_STATUS, 'Assigned')),
        F('Is_Sticky__c', 'Sticky', 'Checkbox', default=False),
        F('Sticky_Key__c', 'Sticky Key', 'Text', length=255, external=True),
        F('Counts_As_Hit__c', 'Counts for Rotation', 'Checkbox', default=True),
        F('Current__c', 'Current Assignment', 'Checkbox', default=True),
        F('Assigned_At__c', 'Assignment Date', 'DateTime'),
        F('Record_Created_At__c', 'Record Created', 'DateTime'),
        F('Speed_To_Assign_Seconds__c', 'Speed to Assign (Seconds)', 'Number', precision=12),
        F('Balance_Value__c', 'Balance Value', 'Number', precision=16),
        F('Next_SLA_Check__c', 'Next SLA Check', 'DateTime'),
        F('Last_SLA_Checkpoint__c', 'Last SLA Checkpoint', 'Number', precision=1, default=0),
        F('SLA_Missed__c', 'SLAs Missed', 'Number', precision=2, default=0),
        F('SLA_Status__c', 'SLA Status', 'Picklist', picklist=pick(['Not Applicable', 'Pending', 'Met', 'Missed', 'Cancelled'], 'Not Applicable')),
        F('Action_At__c', 'Actioned At', 'DateTime'),
        F('Time_To_Action_Mins__c', 'Time to Action (Minutes)', 'Number', precision=12, scale=1),
        F('Reject_Reason__c', 'Reject Reason', 'Text', length=255),
        F('Rejected_At__c', 'Rejected At', 'DateTime'),
        F('Rejected_By__c', 'Rejected By', 'Lookup', ref='User', rname='DE_Rejected_Logs', rlabel='Distribution Logs Rejected'),
        F('Message__c', 'Message', 'TextArea'),
        F('Decision_Trace__c', 'Decision Trace', 'LongTextArea', length=32768, lines=10),
    ])

runlog = dict(api='DE_Run_Log__c', label='Engine Run Log', plural='Engine Run Logs', name_label='Run Number', autonumber='RUN-{000000000}',
    sharing='Read', desc='Scheduler, classifier, SLA, object sync, archive and health checker runs.',
    fields=[
        F('Process__c', 'Process', 'Picklist', picklist=pick(['Scheduler', 'Classifier', 'SLA Monitor', 'Object Sync', 'Archive', 'Health Checker', 'Dynamic Members', 'Purge'], 'Scheduler')),
        F('Status__c', 'Status', 'Picklist', picklist=pick(['Success', 'Warning', 'Error'], 'Success')),
        F('Started_At__c', 'Started At', 'DateTime'),
        F('Duration_Ms__c', 'Duration (ms)', 'Number', precision=12),
        F('Records_Processed__c', 'Records Processed', 'Number', precision=10, default=0),
        F('Assignments__c', 'Assignments', 'Number', precision=10, default=0),
        F('Errors__c', 'Errors', 'Number', precision=10, default=0),
        F('Message__c', 'Message', 'LongTextArea', length=32768, lines=6),
    ])

settings = dict(api='DE_Settings__c', label='Distribution Engine Settings', setting=True,
    desc='Org-wide settings for Distribution Engine by NC Squared.',
    fields=[
        F('Engine_Enabled__c', 'Engine Enabled', 'Checkbox', default=True),
        F('Scheduler_Interval_Minutes__c', 'Scheduler Interval (Minutes)', 'Number', precision=2, default=1),
        F('Records_Per_Run__c', 'Records per Run', 'Number', precision=5, default=500),
        F('Classifier_Enabled__c', 'Classifier Enabled', 'Checkbox', default=True),
        F('Classifier_Objects__c', 'Classifier Objects', 'Text', length=255, help='Comma-separated objects classified on insert, e.g. Lead,Case,Account'),
        F('Distribute_After_Classify__c', 'Distribute Immediately After Classification', 'Checkbox', default=True),
        F('Trigger_Distribution_Enabled__c', 'Process Trigger Distributors', 'Checkbox', default=True),
        F('Previous_Assignees_Tracked__c', 'Number of Previous Assignees Tracked', 'Number', precision=2, default=1),
        F('Hold_After_Failures__c', 'Hold After Failed Attempts', 'Number', precision=3, default=10),
        F('Hold_Minutes__c', 'Hold Duration (Minutes)', 'Number', precision=5, default=60),
        F('Log_Retention_Days__c', 'Log Retention (Days)', 'Number', precision=4, default=30),
        F('Decision_Trace_Enabled__c', 'Record Decision Trace', 'Checkbox', default=True),
        F('Reject_Reasons__c', 'Reject Reasons', 'Text', length=255),
        F('Allow_Other_Reject_Reason__c', 'Allow Other Reject Reason', 'Checkbox', default=True),
        F('Toggle_Reasons__c', 'Toggle Off Reasons', 'Text', length=255),
        F('Require_Toggle_Reason__c', 'Require Toggle Off Reason', 'Checkbox', default=False),
        F('Timer_Durations__c', 'Timer Durations (Minutes)', 'Text', length=100),
        F('Timer_Toggles_Only__c', 'Timer Toggles Only', 'Checkbox', default=False),
        F('Toggle_At_Start_Of_Day__c', 'Toggle Status at Start of Day', 'Text', length=20, help='No Change, Always On or Always Off'),
        F('Toggle_At_End_Of_Day__c', 'Toggle Status at End of Day', 'Text', length=20, help='No Change, Always On or Always Off'),
        F('Personal_Domains__c', 'Personal Email Domains', 'Text', length=255),
        F('Count_Pull_As_Hit__c', 'Count Pull Assignments in Rotation', 'Checkbox', default=True),
        F('Count_Manual_As_Hit__c', 'Count Manual Assignments in Rotation', 'Checkbox', default=False),
        F('Count_Sticky_In_Balance__c', 'Include Sticky in Load Balancing', 'Checkbox', default=True),
        F('Count_Lookup_In_Balance__c', 'Include Lookup Owner in Load Balancing', 'Checkbox', default=True),
        F('Archive_Enabled__c', 'Auto Archive Enabled', 'Checkbox', default=False),
        F('Archive_After_Days__c', 'Archive After (Days)', 'Number', precision=4, default=90),
        F('Archive_Queue_Id__c', 'Archive Queue Id', 'Text', length=18),
        F('Publish_Platform_Events__c', 'Publish Platform Events on Assignment', 'Checkbox', default=True),
        F('Default_Weekday_Start__c', 'Week Starts On', 'Text', length=10, help='Monday or Sunday'),
    ])

event = dict(api='DE_Assignment_Event__e', label='DE Assignment Event', plural='DE Assignment Events',
    desc='Published after each assignment so widgets and integrations can react in real time.',
    fields=[
        F('Record_Id__c', 'Record Id', 'Text', length=18),
        F('Object_API_Name__c', 'Object', 'Text', length=80),
        F('Record_Name__c', 'Record Name', 'Text', length=255),
        F('Assignee_Id__c', 'Assignee Id', 'Text', length=18),
        F('Team_Name__c', 'Team', 'Text', length=80),
        F('Event_Type__c', 'Event Type', 'Text', length=40),
    ])

objects = [teams, members, distributors, conditions, sla, caps, rotation, shift, holiday, ooo, agent, avail_event, territory,
           matching, conversion, stamp_group, stamp, objsync, details, log, runlog, settings]
for o in objects:
    write_object(o)
write_event(event)

COMMON = ['Lead', 'Case', 'Opportunity', 'Contact', 'Account']
for obj in COMMON:
    fs = [F('DE_Is_Distributed__c', 'Is Distributed', 'Checkbox', default=False),
          F('DE_Last_Distributed__c', 'Last Distributed', 'DateTime'),
          F('DE_Distribution_Count__c', 'Distribution Count', 'Number', precision=6, default=0),
          F('DE_Is_Reassigned__c', 'Is Reassigned', 'Checkbox', default=False),
          F('DE_Last_Reassigned__c', 'Last Reassigned', 'DateTime'),
          F('DE_Time_To_Action__c', 'Time to Action (Minutes)', 'Number', precision=10, scale=1),
          F('DE_Territory__c', 'DE Territory', 'Text', length=80)]
    if obj in ('Lead', 'Case', 'Opportunity'):
        fs += [F('DE_Trigger_Distribution__c', 'Distribute Now', 'Checkbox', default=False, help='Check to run trigger distributors for this record on save.'),
               F('DE_Is_Triggered__c', 'Is Triggered', 'Checkbox', default=False),
               F('DE_Is_Rejected__c', 'Is Rejected', 'Checkbox', default=False),
               F('DE_Last_Rejected__c', 'Last Rejected', 'DateTime')]
    if obj in ('Lead', 'Case'):
        fs += [F('DE_Action__c', 'Distribution Action', 'Picklist', picklist=pick(['Contacted', 'Responded', 'Qualified', 'Not Reached'], restricted=False)),
               F('DE_Is_Archived__c', 'Is Archived', 'Checkbox', default=False),
               F('DE_Last_Archive_Date__c', 'Last Archive Date', 'DateTime'),
               F('DE_Source_Queue__c', 'Source Queue Id', 'Text', length=18)]
    for f in fs:
        write_field(obj, f)

# Validation rules
write_vr('DE_Team_Member__c', 'DE_Member_User_Or_Queue', 'OR(AND(ISBLANK(User__c), ISBLANK(Queue_Id__c)), AND(NOT(ISBLANK(User__c)), NOT(ISBLANK(Queue_Id__c))))',
         'A team member must be exactly one user or one queue.')
write_vr('DE_Team_Member__c', 'DE_Weight_Range', 'OR(Weight__c < 0.25, Weight__c > 4, MOD(Weight__c * 4, 1) <> 0)',
         'Weight must be between 0.25 and 4 in steps of 0.25.', 'Weight__c')
write_vr('DE_Distributor__c', 'DE_Pull_Count_Range', 'AND(ISPICKVAL(Type__c, "Pull"), OR(ISBLANK(Pull_Count__c), Pull_Count__c < 1, Pull_Count__c > 100))',
         'Number of records to pull must be between 1 and 100.', 'Pull_Count__c')
write_vr('DE_Distributor__c', 'DE_Source_Required', 'AND(OR(ISPICKVAL(Type__c, "Standard"), ISPICKVAL(Type__c, "Pull")), OR(AND(OR(ISPICKVAL(Source_Type__c, "Queue"), ISPICKVAL(Source_Type__c, "User")), ISBLANK(Source_Id__c)), AND(ISPICKVAL(Source_Type__c, "Field Value"), OR(ISBLANK(Source_Field__c), ISBLANK(Source_Ready_Value__c))), ISPICKVAL(Source_Type__c, "Any")))',
         'Standard and Pull distributors need a source: a queue or user Id, or a field and ready value.')
write_vr('DE_Distributor__c', 'DE_Sticky_Field_Required', 'AND(Sticky_Enabled__c, ISBLANK(Sticky_Field__c))', 'Choose a sticky match field.', 'Sticky_Field__c')
write_vr('DE_Distributor__c', 'DE_Reassign_Target_Required', 'AND(Auto_Reassign__c, ISBLANK(Reassign_To_Id__c))', 'Choose a queue or user to reassign to.', 'Reassign_To_Id__c')
write_vr('DE_Distributor__c', 'DE_Reject_Target_Required', 'AND(Rejection_Enabled__c, ISBLANK(Reject_To_Id__c))', 'Choose a queue or user to reject to.', 'Reject_To_Id__c')
write_vr('DE_Cap__c', 'DE_Cap_Owner', 'OR(AND(ISBLANK(Team__c), ISBLANK(Distributor__c)), AND(NOT(ISBLANK(Team__c)), NOT(ISBLANK(Distributor__c))))', 'A cap belongs to exactly one team or one distributor.')
write_vr('DE_Cap__c', 'DE_Custom_Cap_Range', 'OR(AND(ISPICKVAL(Period__c, "Custom Minutes"), OR(Custom_Length__c < 5, Custom_Length__c > 180)), AND(ISPICKVAL(Period__c, "Custom Hours"), OR(Custom_Length__c < 1, Custom_Length__c > 168)), AND(ISPICKVAL(Period__c, "Custom Days"), OR(Custom_Length__c < 1, Custom_Length__c > 31)), AND(BEGINS(TEXT(Period__c), "Custom"), ISBLANK(Custom_Length__c)))',
         'Custom caps: minutes 5-180, hours 1-168, days 1-31.', 'Custom_Length__c')
write_vr('DE_SLA__c', 'DE_Checkpoint_Range', 'OR(Checkpoint__c < 1, Checkpoint__c > 3)', 'Checkpoint must be 1, 2 or 3.', 'Checkpoint__c')
write_vr('DE_SLA__c', 'DE_Monitor_Max', 'AND(ISPICKVAL(Alert_Type__c, "Continuous Field Monitoring"), Minutes_After_Assignment__c > 20160)', 'Continuous monitoring is limited to two weeks (20160 minutes).', 'Minutes_After_Assignment__c')
write_vr('DE_Holiday__c', 'DE_Holiday_End_After_Start', 'End__c < Start__c', 'Ends must be after Starts.', 'End__c')
write_vr('DE_Out_Of_Office__c', 'DE_OOO_End_After_Start', 'End__c < Start__c', 'End must be after Start.', 'End__c')
write_vr('DE_Out_Of_Office__c', 'DE_OOO_Reason_Length', 'LEN(Reason__c) > 80', 'Reason is limited to 80 characters.', 'Reason__c')
print('ok')
