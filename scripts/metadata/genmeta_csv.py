"""Objects and fields added to cover the reference package inventory (docs/evidence/reference-package-components.csv).
Imported at the end of genmeta2.py. Each object maps to a reference object; see scripts/metadata/csvmap_objects.py."""
import os

from genmeta_lib import F, pick, write_object, write_field, ROOT, HDR, NS, escape


def vr(obj, name, formula, message, field=None):
    d = os.path.join(ROOT, obj, 'validationRules')
    os.makedirs(d, exist_ok=True)
    lines = [HDR, f'<ValidationRule xmlns="{NS}">', f'    <fullName>{name}</fullName>', '    <active>true</active>',
             f'    <errorConditionFormula>{escape(formula)}</errorConditionFormula>']
    if field:
        lines.append(f'    <errorDisplayField>{field}</errorDisplayField>')
    lines += [f'    <errorMessage>{escape(message)}</errorMessage>', '</ValidationRule>\n']
    open(os.path.join(d, name + '.validationRule-meta.xml'), 'w').write('\n'.join(lines))


LOG_STATUS = pick(['Success', 'Error', 'Skipped'], 'Success')

# ---------------------------------------------------------------- availability
holiday_region = dict(api='DE_Holiday_Region__c', label='Holiday Region', plural='Holiday Regions', name_label='Region Name', history=True,
    desc='A set of regional holidays. Each team can use one region; a holiday in the region stops distribution for the team.',
    fields=[F('Description__c', 'Description', 'TextArea')])

shift_plan = dict(api='DE_Shift_Plan__c', label='Team Shift Planner', plural='Team Shift Planners', name_label='Planner Name', history=True,
    sharing='ControlledByParent', desc='Shift planner of one team: dated shift changes per member, up to 12 weeks ahead.',
    fields=[F('Team__c', 'Team', 'MasterDetail', ref='DE_Team__c', rname='Shift_Plans', rlabel='Shift Planners')])

shift_block = dict(api='DE_Shift_Plan_Block__c', label='Shift Planner Block', plural='Shift Planner Blocks', name_label='Block Number',
    autonumber='SPB-{0000000}', history=True, sharing='ControlledByParent',
    desc='A shift change for one member: from the start date the member works the shift until the next block (or the end date).',
    fields=[
        F('Shift_Plan__c', 'Team Shift Planner', 'MasterDetail', ref='DE_Shift_Plan__c', rname='Blocks', rlabel='Blocks'),
        F('Team_Member__c', 'Team Member', 'Lookup', ref='DE_Team_Member__c', rname='Shift_Blocks', rlabel='Shift Planner Blocks'),
        F('Start_Date__c', 'Start Date', 'Date', required=True, track=True),
        F('End_Date__c', 'End Date', 'Date', help='Calculated: the day before the member\'s next block. Blank means open-ended.'),
        F('Shift__c', 'Distribution Hours', 'Lookup', ref='DE_Shift__c', rname='Shift_Blocks', rlabel='Shift Planner Blocks', delete='Restrict', track=True),
    ])

team_manager = dict(api='DE_Team_Manager__c', label='Team Manager', plural='Team Managers', name_label='Team Manager Number',
    autonumber='TMG-{000000}', history=True, sharing='ControlledByParent',
    desc='A user who manages a team (Team Manager and Custom Team Manager permission sets are scoped to these teams).',
    fields=[
        F('Team__c', 'Team', 'MasterDetail', ref='DE_Team__c', rname='Managers', rlabel='Team Managers'),
        F('User__c', 'User', 'Lookup', ref='User', rname='DE_Managed_Teams', rlabel='Managed Distribution Teams', delete='Restrict', required=True),
        F('Unique_Key__c', 'Unique Key', 'Text', length=40, unique=True, help='Team Id + User Id; prevents duplicates.'),
    ])

# ---------------------------------------------------------------- assignment pipeline
reject_request = dict(api='DE_Reject_Request__c', label='Distribution Reject Log', plural='Distribution Reject Logs', name_label='Reject Log Number',
    autonumber='RJ-{00000000}', sharing='Read', desc='Every rejection request with its reason, requester and outcome.',
    fields=[
        F('Record_Id__c', 'Assigned Object Id', 'Text', length=18, external=True),
        F('Object_API_Name__c', 'Object', 'Text', length=80),
        F('Record_Name__c', 'Record Name', 'Text', length=255),
        F('Team__c', 'Team', 'Lookup', ref='DE_Team__c', rname='Reject_Requests', rlabel='Reject Logs'),
        F('Assignment_Log__c', 'Distribution Log', 'Lookup', ref='DE_Assignment_Log__c', rname='Reject_Requests', rlabel='Reject Logs'),
        F('Reason__c', 'Reason', 'Text', length=255),
        F('Requested_By__c', 'Requested By', 'Lookup', ref='User', rname='DE_Reject_Requests', rlabel='Distribution Reject Requests'),
        F('Requested_At__c', 'Request Datetime', 'DateTime'),
        F('Status__c', 'Status', 'Picklist', picklist=pick(['Approved', 'Denied'], 'Approved'),
          help='Approved requests are applied immediately; denied requests record why (limit reached, not allowed).'),
        F('Reviewed_By__c', 'Reviewed By', 'Lookup', ref='User', rname='DE_Reviewed_Reject_Requests', rlabel='Distribution Reject Reviews'),
        F('Reviewed_At__c', 'Review Datetime', 'DateTime'),
        F('Message__c', 'Message', 'TextArea'),
    ])

log_action = dict(api='DE_Log_Action__c', label='Distribution Log Action', plural='Distribution Log Actions', name_label='Action Number',
    autonumber='LA-{000000000}', sharing='ControlledByParent', desc='A tracked action on an assigned record and the time it took.',
    fields=[
        F('Assignment_Log__c', 'Distribution Log', 'MasterDetail', ref='DE_Assignment_Log__c', rname='Actions', rlabel='Actions'),
        F('Action__c', 'Action', 'Text', length=255),
        F('Action_At__c', 'Action Date', 'DateTime'),
        F('Actioned_By__c', 'Actioned By', 'Lookup', ref='User', rname='DE_Log_Actions', rlabel='Distribution Log Actions'),
        F('Time_To_Action_Mins__c', 'Time to Action (Minutes)', 'Number', precision=12, scale=1),
        F('Time_To_Action_Days__c', 'Time to Action (Days)', 'Number', precision=10, scale=2),
        F('Source__c', 'Source', 'Picklist', picklist=pick(['Field Change', 'Task', 'Event', 'API'], 'Field Change')),
    ])

# ---------------------------------------------------------------- monitoring and audit
history = dict(api='DE_History__c', label='Change History', plural='Change History', name_label='Change Number', autonumber='CH-{000000000}',
    sharing='Read', desc='Audit of configuration changes: teams, members, distributors, holidays, out of office, shifts and tag assignments.',
    fields=[
        F('Object_API_Name__c', 'Object', 'Text', length=80),
        F('Record_Id__c', 'Object Id', 'Text', length=18),
        F('Record_Name__c', 'Record Name', 'Text', length=255),
        F('Parent_Object__c', 'Parent Object Type', 'Text', length=80),
        F('Parent_Record_Id__c', 'Parent Id', 'Text', length=18, help='Team Id for team members, distributors and the like; used to show a team\'s history.'),
        F('Change_Type__c', 'Change Type', 'Picklist', picklist=pick(['Created', 'Updated', 'Deleted'], 'Updated')),
        F('Field__c', 'Field', 'Text', length=120),
        F('Old_Value__c', 'Old Value', 'LongTextArea', length=4000, lines=3),
        F('New_Value__c', 'New Value', 'LongTextArea', length=4000, lines=3),
        F('Changed_By__c', 'User', 'Lookup', ref='User', rname='DE_Changes', rlabel='Distribution Engine Changes'),
        F('Changed_At__c', 'Change Datetime', 'DateTime'),
        F('Background_Change__c', 'Background Change', 'Checkbox', default=False, help='Made by the engine (scheduler, timers, calendar sync) rather than by a user in the app.'),
    ])

sync_log = dict(api='DE_Object_Sync_Log__c', label='Object Sync Log', plural='Object Sync Logs', name_label='Sync Log Number',
    autonumber='OSL-{000000000}', sharing='Read', desc='Result of synchronising related records to a newly assigned owner.',
    fields=[
        F('Record_Id__c', 'Record Id', 'Text', length=18),
        F('Record_Name__c', 'Record Name', 'Text', length=255),
        F('Object_API_Name__c', 'Distribution Object', 'Text', length=80),
        F('Team__c', 'Team', 'Lookup', ref='DE_Team__c', rname='Object_Sync_Logs', rlabel='Object Sync Logs'),
        F('Assignee_Id__c', 'Assignee Id', 'Text', length=18),
        F('Status__c', 'Status', 'Picklist', picklist=LOG_STATUS),
        F('Actions_Performed__c', 'Actions Performed', 'LongTextArea', length=4000, lines=3, help='One line per related object: Object=records synced.'),
        F('Synced_Records__c', 'Number of Synced Records', 'Number', precision=8, default=0),
        F('Errors__c', 'Number of Errors', 'Number', precision=8, default=0),
        F('Error_Message__c', 'Error Message', 'TextArea'),
        F('Processed_At__c', 'Last Processed', 'DateTime'),
    ])


def classifier_log(api, label, plural, prefix, desc, extra):
    return dict(api=api, label=label, plural=plural, name_label='Log Number', autonumber=prefix + '-{000000000}', sharing='Read', desc=desc,
        fields=[
            F('Record_Id__c', 'Record Id', 'Text', length=18, unique=True, external=True, help='One log per classified record; the latest run overwrites it.'),
            F('Record_Name__c', 'Record Name', 'Text', length=255),
            F('Object_API_Name__c', 'Object', 'Text', length=80),
            F('In_Error__c', 'In Error', 'Checkbox', default=False),
            F('Error_Message__c', 'Error Message', 'TextArea'),
            F('Attempts__c', 'Number of Attempts', 'Number', precision=6, default=0),
            F('Processed_At__c', 'Last Processed', 'DateTime'),
        ] + extra)


territory_log = classifier_log('DE_Territory_Log__c', 'Territory Classification Log', 'Territory Classification Logs', 'TCL',
    'Latest territory classification of a record, with the cleaned address it was matched on.', [
        F('Territory__c', 'Matched Territory', 'Lookup', ref='DE_Territory__c', rname='Logs', rlabel='Classification Logs'),
        F('Match_Level__c', 'Matched Territory Level', 'Picklist', picklist=pick(['Country', 'State', 'Postal Code', 'Conditions', 'None'], 'None')),
        F('Clean_Country__c', 'Clean Country', 'Text', length=80),
        F('Clean_State__c', 'Clean State', 'Text', length=80),
        F('Clean_Postal_Code__c', 'Clean Postal Code', 'Text', length=20),
    ])

matching_log = classifier_log('DE_Matching_Log__c', 'Lead Matching Log', 'Lead Matching Logs', 'LML',
    'Latest lead-matching result of a record.', [
        F('Matched_Account__c', 'Matched Account', 'Lookup', ref='Account', rname='DE_Matching_Logs', rlabel='Distribution Engine Matching Logs'),
        F('Matched_Contact__c', 'Matched Contact', 'Lookup', ref='Contact', rname='DE_Matching_Logs', rlabel='Distribution Engine Matching Logs'),
        F('Matched_Lead__c', 'Matched Lead', 'Lookup', ref='Lead', rname='DE_Matching_Logs', rlabel='Distribution Engine Matching Logs'),
        F('Account_Rule__c', 'Account or Contact Matching Rule', 'Lookup', ref='DE_Matching_Rule__c', rname='Account_Logs', rlabel='Account Match Logs'),
        F('Account_Confidence__c', 'Account or Contact Match Confidence', 'Text', length=80),
        F('Lead_Rule__c', 'Lead Matching Rule', 'Lookup', ref='DE_Matching_Rule__c', rname='Lead_Logs', rlabel='Lead Match Logs'),
        F('Lead_Confidence__c', 'Lead Match Confidence', 'Text', length=80),
    ])

conversion_log = classifier_log('DE_Conversion_Log__c', 'Auto Conversion Log', 'Auto Conversion Logs', 'ACL',
    'Latest auto-conversion or de-duplication of a lead.', [
        F('Result__c', 'Type', 'Picklist', picklist=pick(['Converted', 'De-duplicated', 'Not Converted'], 'Not Converted')),
        F('Conversion_Rule__c', 'Auto Conversion Rule', 'Lookup', ref='DE_Conversion_Rule__c', rname='Logs', rlabel='Auto Conversion Logs'),
        F('Account_Id__c', 'Account Id', 'Text', length=18),
        F('Contact_Id__c', 'Contact Id', 'Text', length=18),
        F('Opportunity_Id__c', 'Opportunity Id', 'Text', length=18),
        F('Matched_Lead_Id__c', 'Matched Lead Id', 'Text', length=18),
        F('Owner_Id__c', 'Owner Id', 'Text', length=18),
    ])

classification_log = classifier_log('DE_Classification_Log__c', 'Custom Classification Log', 'Custom Classification Logs', 'CCL',
    'Latest custom classification (stamps) of a record.', [
        F('Stamps__c', 'Stamps', 'LongTextArea', length=4000, lines=3, help='One Group:Stamp line per stamp awarded.'),
    ])

account_domain = dict(api='DE_Account_Domain__c', label='Classifier Account Domain', plural='Classifier Account Domains', name_label='Domain',
    desc='Index of account website and contact email domains used by lead matching.',
    fields=[
        F('Account__c', 'Account', 'Lookup', ref='Account', rname='DE_Domains', rlabel='Distribution Engine Domains'),
        F('Domain_Type__c', 'Domain Type', 'Picklist', picklist=pick(['Website', 'Contact Email'], 'Website')),
        F('Unique_Key__c', 'Unique Key', 'Text', length=120, unique=True),
    ])

# ---------------------------------------------------------------- personas
persona = dict(api='DE_Persona__c', label='Distribution Engine Persona', plural='Distribution Engine Personas', name_label='Persona Name', history=True,
    desc='A set of capabilities for users with the Custom Team Manager permission set.',
    fields=[
        F('Is_Default__c', 'Is Default', 'Checkbox', default=False, help='The default persona applies to custom team managers without a persona. It cannot be renamed or deleted.'),
        F('Capabilities__c', 'Capabilities', 'LongTextArea', length=32768, lines=8, help='JSON: capability key to access level.'),
        F('Base_Permission_Set__c', 'Permission Set', 'Text', length=80, help='Permission set the persona builds on.'),
        F('Unique_Name__c', 'Unique Name', 'Text', length=80, unique=True),
    ])

user_persona = dict(api='DE_User_Persona__c', label='User Persona', plural='User Personas', name_label='Assignment Number', autonumber='UP-{000000}',
    history=True, desc='The persona of one custom team manager.',
    fields=[
        F('User__c', 'User', 'Lookup', ref='User', rname='DE_Personas', rlabel='Distribution Engine Personas', delete='Restrict', required=True),
        F('Persona__c', 'Persona', 'Lookup', ref='DE_Persona__c', rname='User_Assignments', rlabel='User Assignments', delete='Restrict', required=True),
        F('Unique_User__c', 'Unique User', 'Text', length=18, unique=True),
    ])

for o in [holiday_region, shift_plan, shift_block, team_manager, reject_request, log_action, history, sync_log, territory_log, matching_log,
          conversion_log, classification_log, account_domain, persona, user_persona]:
    write_object(o)

# ---------------------------------------------------------------- fields on existing objects
ACCESS = ['Read', 'Edit']
EXTRA = {
    'DE_Team__c': [
        F('Widget_Active_Only__c', 'Show Only Active Records in Widget', 'Checkbox', default=False,
          help='The widget\'s Assigned to me list only shows records in an active status (Active Status Field / Values).'),
        F('Use_Shift_Planner__c', 'Use Shift Planner', 'Checkbox', default=False, track=True,
          help='Member hours come from the shift planner (dated shift changes) instead of member or team hours.'),
        F('Logging_Disabled__c', 'Distribution Logging Disabled', 'Checkbox', default=False, track=True,
          help='Stops distribution logs and standard emails for this team. Not allowed with action tracking or SLAs.'),
    ],
    'DE_Distributor__c': [
        F('Salesforce_Team_Enabled__c', 'Role Assignment', 'Checkbox', default=False, track=True,
          help='Adds the selected member to the Account, Opportunity or Case team with a role instead of changing the owner. Requires a Field Value source.'),
        F('Team_Role__c', 'Team Role', 'Text', length=80, help='Account/Opportunity team role, or Case team role name.'),
        F('Team_Access_Level__c', 'Team Access Levels', 'Text', length=120,
          help='Account teams: Account=Edit;Opportunity=Read;Case=Read. Opportunity teams: Opportunity=Edit. Case teams use the case team role access.'),
        F('Assign_Default_Team__c', 'Add Default Team', 'Checkbox', default=False, help='Also add the assignee\'s default Account or Opportunity team.'),
        F('Remove_Sticky_On_Reject__c', 'Remove Sticky from Rejected Records', 'Picklist', picklist=pick(['New Sticky Only', 'Always', 'Never'], 'New Sticky Only')),
        F('Related_Role__c', 'Related Owner Role', 'Text', length=80, help='Optional Account or Opportunity team role: assign to the team member with this role instead of the related record owner.'),
        F('Campaign_Ids__c', 'Filter by Campaign', 'TextArea', help='Campaign Ids (one per line). Only leads or contacts that are members of one of these campaigns are distributed.'),
    ],
    'DE_Assignment_Log__c': [
        F('Assignee_Name__c', 'Assigned Owner Name', 'Text', length=121),
        F('Status_On_Assignment__c', 'Status on Assignment', 'Text', length=255),
        F('Send_Email__c', 'Send Standard Email', 'Checkbox', default=False, help='Set from the distributor; the email notification flows only send when checked.'),
        F('Team_Role__c', 'Team Member Role', 'Text', length=80),
        F('Team_Member_Record_Id__c', 'Team Member Record Id', 'Text', length=18, help='AccountTeamMember, OpportunityTeamMember or CaseTeamMember created by role assignment.'),
        F('Reassign_Attempts__c', 'Auto Reassign Attempts', 'Number', precision=2, default=0),
        F('Reassign_Error_At__c', 'Auto Reassign Error Date', 'DateTime'),
        F('Actions_Complete__c', 'Actions Complete', 'Number', precision=4, default=0),
        F('Last_Action_At__c', 'Last Action Date', 'DateTime'),
        F('Reject_Request__c', 'Distribution Reject Log', 'Lookup', ref='DE_Reject_Request__c', rname='Logs', rlabel='Distribution Logs'),
    ] + [F(o + '__c', o, 'Lookup', ref=o, rname='DE_Distribution_Logs', rlabel='Distribution Logs',
           help='Set when the routed record is a ' + o + '; used by email templates, reports and related lists.')
         for o in ['Lead', 'Case', 'Contact', 'Account', 'Opportunity']],
    'DE_Record_Detail__c': [
        F('Trigger_Last_Attempt__c', 'Trigger Distribution Last Attempt', 'DateTime'),
    ],
    'DE_Out_Of_Office__c': [
        F('Timezone__c', 'Timezone', 'Text', length=60, help='Timezone used for all-day entries. Defaults to the user\'s timezone.'),
        F('Activity_Id__c', 'Activity Id', 'Text', length=18, help='Calendar Event that created this entry.'),
    ],
    'DE_Territory__c': [F('Color__c', 'Color', 'Text', length=7, help='Hex colour used in lists and charts, e.g. #2a78d6.')],
    'DE_Stamp__c': [
        F('Active__c', 'Active', 'Checkbox', default=True),
        F('Is_Default__c', 'Default Stamp', 'Checkbox', default=False, help='Awarded when no other stamp in the group matches.'),
    ],
    'DE_Conversion_Rule__c': [
        F('Account_Record_Type__c', 'Account Record Type', 'Text', length=80),
        F('Contact_Record_Type__c', 'Contact Record Type', 'Text', length=80),
        F('Opportunity_Record_Type__c', 'Opportunity Record Type', 'Text', length=80),
        F('Distribute_After__c', 'Distribute After De-duplication', 'Checkbox', default=False,
          help='After a merge, distribute the surviving lead again.'),
        F('Overwrite_Lead_Source__c', 'Overwrite Lead Source', 'Checkbox', default=False, help='Copy the converted lead\'s Lead Source onto the contact and opportunity.'),
        F('Send_Email__c', 'Send Email to Owner', 'Checkbox', default=False, help='Email the owner of the converted records.'),
    ],
    'DE_Run_Log__c': [
        F('Heap_Used__c', 'Max Heap Usage (Bytes)', 'Number', precision=12),
        F('Job_Id__c', 'Apex Job Id', 'Text', length=18),
    ],
    'DE_Object_Sync__c': [
        F('Order__c', 'Execution Order', 'Number', precision=4, default=10),
        F('Action_Type__c', 'Action Type', 'Picklist', picklist=pick(['Change Owner'], 'Change Owner')),
    ],
    'DE_Settings__c': [
        F('History_Retention_Days__c', 'Change History Retention (Days)', 'Number', precision=4, default=90, setting=True),
        F('Classifier_Log_Retention_Days__c', 'Classifier and Sync Log Retention (Days)', 'Number', precision=4, default=30, setting=True),
        F('Admin_Alert_Emails__c', 'Admin Alert Emails', 'Text', length=255, setting=True,
          help='Comma-separated addresses for failure alerts (classifier, distribution, reassignment, health checker). Blank = no alert emails.'),
        F('Failure_Alert_Threshold__c', 'Failure Alert Threshold', 'Number', precision=3, default=5, setting=True,
          help='Alert after a record fails this many times in a row.'),
        F('Use_Platform_Cache__c', 'Use Platform Cache', 'Checkbox', default=True, setting=True),
    ],
}
for obj, fs in EXTRA.items():
    for f in fs:
        if obj == 'DE_Settings__c':
            f['setting'] = True
        write_field(obj, f)

for obj in ['Lead', 'Case', 'Opportunity', 'Contact', 'Account']:
    write_field(obj, F('DE_Classifier_Status__c', 'DE Classifier Status', 'Picklist', picklist=pick(['Waiting', 'Done', 'Error'], restricted=False),
                       help='Classifier progress for this record (mirrors Distribution Engine Details).'))
write_field('Contact', F('DE_Email_Domain__c', 'DE Account Match Email Domain', 'Text', length=255,
                         help='Email domain used to match leads to this contact\'s account; maintained by Distribution Engine.'))

# ---------------------------------------------------------------- validation rules
vr('DE_Shift_Plan_Block__c', 'DE_Block_End_After_Start', 'AND(NOT(ISBLANK(End_Date__c)), End_Date__c < Start_Date__c)', 'End date must be on or after the start date.', 'End_Date__c')
vr('DE_Shift_Plan_Block__c', 'DE_Block_Within_Horizon', 'Start_Date__c > TODAY() + 84', 'Shifts can be planned up to 12 weeks ahead.', 'Start_Date__c')
vr('DE_Shift_Plan_Block__c', 'DE_Block_Member_Required', 'ISBLANK(Team_Member__c)', 'Choose a team member.', 'Team_Member__c')
vr('DE_Distributor__c', 'DE_Role_Assignment_Field_Value_Source',
   'AND(Salesforce_Team_Enabled__c, NOT(ISPICKVAL(Source_Type__c, "Field Value")))',
   'Role assignment distributors must use a Field Value source.', 'Source_Type__c')
vr('DE_Distributor__c', 'DE_Role_Assignment_Role_Required', 'AND(Salesforce_Team_Enabled__c, ISBLANK(Team_Role__c), NOT(Assign_Default_Team__c))',
   'Choose a team role or add the default team.', 'Team_Role__c')
vr('DE_Distributor__c', 'DE_Role_Assignment_No_Rejection', 'AND(Salesforce_Team_Enabled__c, OR(Rejection_Enabled__c, SLA_Enabled__c))',
   'Rejection and SLAs are not available for role assignment distributors.')
vr('DE_Team__c', 'DE_Logging_Required_For_Tracking', 'AND(Logging_Disabled__c, OR(Action_Tracking_Enabled__c, Object_Sync_Enabled__c))',
   'Distribution logging is required for action tracking and object sync.', 'Logging_Disabled__c')
vr('DE_Persona__c', 'DE_Default_Persona_Name_Locked', 'AND(Is_Default__c, ISCHANGED(Name))', 'The default persona cannot be renamed.', 'Name')
