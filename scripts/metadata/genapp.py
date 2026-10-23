"""Generates app, tabs, utility bar, custom permissions, notification type,
permission sets, report types, reports and the dashboard from the object metadata."""
import os
import re
import sys
from xml.sax.saxutils import escape

ROOT = os.path.join(sys.argv[1], 'force-app/main/default')
NS = 'http://soap.sforce.com/2006/04/metadata'
HDR = '<?xml version="1.0" encoding="UTF-8"?>\n'


def write(rel, body):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as fh:
        fh.write(HDR + body.strip() + '\n')


def tag(name, value, indent=4):
    return ' ' * indent + '<%s>%s</%s>' % (name, escape(str(value)), name)


# ------------------------------------------------------------------ custom permissions
PERMS = [
    ('DE_Admin', 'DE Admin', 'Full control of Distribution Engine, including global settings, classifier and data maintenance.'),
    ('DE_System_Manager', 'DE System Manager', 'Manage every team, distributor, SLA, cap, availability and tag in Distribution Engine.'),
    ('DE_Team_Manager', 'DE Team Manager', 'Manage the teams that list the user as a manager, and their members\' availability.'),
    ('DE_User', 'DE User', 'Use the Distribution Engine widget, toggle own availability, pull work and reject records.'),
    ('DE_Custom_Team_Manager', 'DE Custom Team Manager', 'Team manager whose access to each page and feature is set by their persona.'),
]
for name, label, desc in PERMS:
    write('customPermissions/%s.customPermission-meta.xml' % name, '''
<CustomPermission xmlns="%s">
    <description>%s</description>
    <isLicensed>false</isLicensed>
    <label>%s</label>
</CustomPermission>''' % (NS, escape(desc), escape(label)))

# ------------------------------------------------------------------ notification type
write('notificationtypes/DE_Assignment.notiftype-meta.xml', '''
<CustomNotificationType xmlns="%s">
    <customNotifTypeName>DE Assignment</customNotifTypeName>
    <description>Distribution Engine: record assigned, SLA alert or reassignment.</description>
    <desktop>true</desktop>
    <masterLabel>DE Assignment</masterLabel>
    <mobile>true</mobile>
</CustomNotificationType>''' % NS)

# ------------------------------------------------------------------ tabs
LWC_TABS = [
    ('DE_Console', 'Distribution Console', 'deConsole', 'Custom55: Gears'),
    ('DE_Classifier', 'Record Classification', 'deClassifier', 'Custom27: Laptop'),
    ('DE_Teams', 'Distribution Team', 'deTeams', 'Custom15: People'),
    ('DE_Tags', 'Distribution Tags', 'deTags', 'Custom59: Ribbon'),
    ('DE_Sync', 'Distribution Sync', 'deObjectSync', 'Custom62: Link'),
    ('DE_Availability', 'Distribution Availability', 'deAvailability', 'Custom95: Clock'),
    ('DE_Logs', 'Distribution Logs', 'deLogs', 'Custom18: Form'),
    ('DE_Analytics', 'Distribution Analytics', 'deAnalytics', 'Custom16: Chart'),
    ('DE_Settings', 'Distribution Settings', 'deSettings', 'Custom19: Wrench'),
]
for name, label, cmp, motif in LWC_TABS:
    write('tabs/%s.tab-meta.xml' % name, '''
<CustomTab xmlns="%s">
    <label>%s</label>
    <lwcComponent>%s</lwcComponent>
    <motif>%s</motif>
</CustomTab>''' % (NS, escape(label), cmp, motif))

OBJECT_TABS = [('DE_Assignment_Log__c', 'Custom18: Form'), ('DE_Run_Log__c', 'Custom62: Link')]
for obj, motif in OBJECT_TABS:
    write('tabs/%s.tab-meta.xml' % obj, '''
<CustomTab xmlns="%s">
    <customObject>true</customObject>
    <motif>%s</motif>
</CustomTab>''' % (NS, motif))

ALL_TABS = [t[0] for t in LWC_TABS] + [o for o, _ in OBJECT_TABS]

# ------------------------------------------------------------------ utility bar and app
def prop(name, value):
    return '''                <componentInstanceProperties>
                    <name>%s</name>
                    <type>decorator</type>
                    <value>%s</value>
                </componentInstanceProperties>''' % (name, value)


write('flexipages/DE_Utility_Bar.flexipage-meta.xml', '''
<FlexiPage xmlns="%s">
    <flexiPageRegions>
        <itemInstances>
            <componentInstance>
%s
                <componentName>deWidget</componentName>
                <identifier>deWidget</identifier>
            </componentInstance>
        </itemInstances>
        <mode>Replace</mode>
        <name>utilityItems</name>
        <type>Region</type>
    </flexiPageRegions>
    <flexiPageRegions>
        <mode>Replace</mode>
        <name>backgroundComponents</name>
        <type>Background</type>
    </flexiPageRegions>
    <masterLabel>Distribution Engine Utility Bar</masterLabel>
    <template>
        <name>one:utilityBarTemplateDesktop</name>
        <properties>
            <name>isLeftAligned</name>
            <value>true</value>
        </properties>
    </template>
    <type>UtilityBar</type>
</FlexiPage>''' % (NS, '\n'.join([prop('eager', 'true'), prop('height', '520'), prop('icon', 'routing_offline'),
                                  prop('label', 'Distribution'), prop('scrollable', 'true'), prop('width', '360')])))

APP_TABS = ['DE_Console', 'DE_Teams', 'DE_Availability', 'DE_Tags', 'DE_Classifier', 'DE_Sync', 'DE_Logs',
            'DE_Analytics', 'DE_Settings', 'standard-Lead', 'standard-Case', 'standard-report', 'standard-Dashboard']
write('applications/DE_Distribution_Engine.app-meta.xml', '''
<CustomApplication xmlns="%s">
    <brand>
        <headerColor>#2A78D6</headerColor>
        <shouldOverrideOrgTheme>false</shouldOverrideOrgTheme>
    </brand>
    <description>Distribution Engine by NC Squared: lead, case and opportunity routing, availability, SLAs and classification.</description>
    <formFactors>Small</formFactors>
    <formFactors>Large</formFactors>
    <isNavAutomaticallyAdded>true</isNavAutomaticallyAdded>
    <isNavPersonalizationDisabled>false</isNavPersonalizationDisabled>
    <isNavTabPersistenceDisabled>false</isNavTabPersistenceDisabled>
    <label>Distribution Engine by NC Squared</label>
    <navType>Standard</navType>
%s
    <uiType>Lightning</uiType>
    <utilityBar>DE_Utility_Bar</utilityBar>
</CustomApplication>''' % (NS, '\n'.join(tag('tabs', t) for t in APP_TABS)))

# ------------------------------------------------------------------ field inventory
OBJ_DIR = os.path.join(ROOT, 'objects')


def fields_of(obj):
    out = []
    fdir = os.path.join(OBJ_DIR, obj, 'fields')
    if not os.path.isdir(fdir):
        return out
    for f in sorted(os.listdir(fdir)):
        src = open(os.path.join(fdir, f)).read()
        name = f.replace('.field-meta.xml', '')
        ftype = re.search(r'<type>([^<]+)</type>', src)
        ftype = ftype.group(1) if ftype else ''
        required = '<required>true</required>' in src
        if ftype == 'MasterDetail' or required:
            continue  # no field permissions for required or master-detail fields
        if obj.endswith('__c') and not name.endswith('__c'):
            continue
        if not obj.endswith('__c') and not name.startswith('DE_'):
            continue
        out.append((name, '<formula>' in src or ftype in ('Summary', 'AutoNumber')))
    return out


CUSTOM = sorted(o for o in os.listdir(OBJ_DIR) if o.startswith('DE_') and o.endswith('__c') and o != 'DE_Settings__c')
STANDARD = ['Account', 'Case', 'Contact', 'Lead', 'Opportunity']

CONFIG = ['DE_Team__c', 'DE_Team_Member__c', 'DE_Distributor__c', 'DE_Condition__c', 'DE_SLA__c', 'DE_Cap__c',
          'DE_Shift__c', 'DE_Holiday__c', 'DE_Territory__c', 'DE_Matching_Rule__c', 'DE_Conversion_Rule__c',
          'DE_Stamp_Group__c', 'DE_Stamp__c', 'DE_Object_Sync__c', 'DE_Holiday_Region__c', 'DE_Shift_Plan__c',
          'DE_Shift_Plan_Block__c', 'DE_Team_Manager__c', 'DE_Persona__c', 'DE_User_Persona__c']
LOGS = ['DE_Reject_Request__c', 'DE_Log_Action__c', 'DE_History__c', 'DE_Object_Sync_Log__c', 'DE_Territory_Log__c', 'DE_Matching_Log__c',
        'DE_Conversion_Log__c', 'DE_Classification_Log__c', 'DE_Account_Domain__c']

FULL = 'CREDVM'
# object -> access letters (C create, R read, E edit, D delete, V view all, M modify all)
ACCESS = {
    'DE_Admin': {o: FULL for o in CUSTOM},
    'DE_System_Manager': {o: FULL for o in CUSTOM},
    'DE_Team_Manager': dict(
        {o: 'RV' for o in CONFIG},
        **{
            'DE_Team__c': 'REV',
            'DE_Team_Member__c': 'CREDV',
            'DE_Distributor__c': 'REV',
            'DE_Condition__c': 'CREDV',
            'DE_Cap__c': 'CREDV',
            'DE_SLA__c': 'CREDV',
            'DE_Out_Of_Office__c': 'CREDVM',
            'DE_Agent__c': 'CREVM',
            'DE_Availability_Event__c': 'CRV',
            'DE_Assignment_Log__c': 'REV',
            'DE_Record_Detail__c': 'RV',
            'DE_Rotation_State__c': 'RV',
            'DE_Run_Log__c': 'RV',
            'DE_Shift_Plan__c': 'CREDV',
            'DE_Shift_Plan_Block__c': 'CREDV',
        },
        **{o: 'RV' for o in LOGS}),
    'DE_User': {
        'DE_Team__c': 'R', 'DE_Team_Member__c': 'R', 'DE_Distributor__c': 'R', 'DE_Condition__c': 'R',
        'DE_SLA__c': 'R', 'DE_Cap__c': 'R', 'DE_Shift__c': 'R', 'DE_Holiday__c': 'R', 'DE_Territory__c': 'R',
        'DE_Stamp_Group__c': 'R', 'DE_Stamp__c': 'R',
        'DE_Out_Of_Office__c': 'CRED', 'DE_Agent__c': 'CRE', 'DE_Availability_Event__c': 'CR',
        'DE_Assignment_Log__c': 'RE', 'DE_Record_Detail__c': 'R',
        'DE_Holiday_Region__c': 'R', 'DE_Shift_Plan__c': 'R', 'DE_Shift_Plan_Block__c': 'R', 'DE_Team_Manager__c': 'R',
        'DE_Reject_Request__c': 'R', 'DE_Log_Action__c': 'R',
    },
}
ACCESS['DE_Custom_Team_Manager'] = dict(ACCESS['DE_Team_Manager'])
ACCESS['DE_Community_User'] = dict(ACCESS['DE_User'])
# permission set -> custom permission it grants
CUSTOM_PERMISSION = {'DE_Admin': 'DE_Admin', 'DE_System_Manager': 'DE_System_Manager', 'DE_Team_Manager': 'DE_Team_Manager',
                     'DE_User': 'DE_User', 'DE_Custom_Team_Manager': 'DE_Custom_Team_Manager', 'DE_Community_User': 'DE_User'}
STANDARD_EDIT = {'DE_Admin': True, 'DE_System_Manager': True, 'DE_Team_Manager': False, 'DE_User': False, 'DE_Custom_Team_Manager': False, 'DE_Community_User': False}
USER_EDITABLE_STANDARD = {'DE_Trigger_Distribution__c'}

TAB_ACCESS = {
    'DE_Admin': ALL_TABS,
    'DE_System_Manager': ALL_TABS,
    'DE_Team_Manager': ['DE_Console', 'DE_Teams', 'DE_Availability', 'DE_Tags', 'DE_Logs', 'DE_Analytics',
                        'DE_Assignment_Log__c'],
    'DE_User': ['DE_Availability'],
}
TAB_ACCESS['DE_Custom_Team_Manager'] = TAB_ACCESS['DE_Team_Manager']
TAB_ACCESS['DE_Community_User'] = []
CLASS_DIR = os.path.join(ROOT, 'classes')
CONTROLLERS = sorted(c[:-4] for c in os.listdir(CLASS_DIR) if c.endswith('Controller.cls')) + [
    'DE_Simulator', 'DE_FlowActions', 'DE_ToggleUsersAction', 'DE_RejectRecordAction']
CLASS_ACCESS = {
    'DE_Admin': CONTROLLERS + ['DE_Api'],
    'DE_System_Manager': CONTROLLERS + ['DE_Api'],
    'DE_Team_Manager': CONTROLLERS,
    'DE_User': ['DE_WidgetController', 'DE_RecordDetailController', 'DE_AvailabilityController', 'DE_FlowActions',
                'DE_ToggleUsersAction', 'DE_RejectRecordAction'],
}
CLASS_ACCESS['DE_Custom_Team_Manager'] = CONTROLLERS
CLASS_ACCESS['DE_Community_User'] = CLASS_ACCESS['DE_User']
LABELS = {
    'DE_Admin': ('Distribution Engine Admin', 'Everything in Distribution Engine, including global settings, classifier configuration and data maintenance.'),
    'DE_System_Manager': ('Distribution Engine System Manager', 'Manage all teams, distributors, SLAs, caps, availability, tags and logs.'),
    'DE_Team_Manager': ('Distribution Engine Team Manager', 'Manage the teams you are listed on as manager and your team members\' availability.'),
    'DE_User': ('Distribution Engine User', 'Widget, own availability and out of office, pull work, reject records and view distribution details.'),
    'DE_Custom_Team_Manager': ('Distribution Engine Custom Team Manager', 'Team manager whose access to each page and feature comes from their persona.'),
    'DE_Community_User': ('Distribution Engine Community User', 'Experience Cloud users who receive assignments: widget, own availability and out of office.'),
}

for ps, (label, desc) in LABELS.items():
    parts = []
    parts.append('''    <applicationVisibilities>
        <application>DE_Distribution_Engine</application>
        <visible>true</visible>
    </applicationVisibilities>''')
    for cls in sorted(CLASS_ACCESS[ps]):
        parts.append('''    <classAccesses>
        <apexClass>%s</apexClass>
        <enabled>true</enabled>
    </classAccesses>''' % cls)
    parts.append('''    <customPermissions>
        <enabled>true</enabled>
        <name>%s</name>
    </customPermissions>''' % CUSTOM_PERMISSION[ps])
    if ps in ('DE_Admin', 'DE_System_Manager'):
        parts.append('''    <customSettingAccesses>
        <enabled>true</enabled>
        <name>DE_Settings__c</name>
    </customSettingAccesses>''')
    parts.append('    <description>%s</description>' % escape(desc))
    field_rows = []
    for obj in sorted(ACCESS[ps]):
        letters = ACCESS[ps][obj]
        for fname, readonly in fields_of(obj):
            edit = 'E' in letters and not readonly
            field_rows.append((obj + '.' + fname, edit))
    for obj in STANDARD:
        for fname, readonly in fields_of(obj):
            edit = not readonly and (STANDARD_EDIT[ps] or fname in USER_EDITABLE_STANDARD)
            field_rows.append((obj + '.' + fname, edit))
    for field, edit in sorted(field_rows):
        parts.append('''    <fieldPermissions>
        <editable>%s</editable>
        <field>%s</field>
        <readable>true</readable>
    </fieldPermissions>''' % ('true' if edit else 'false', field))
    parts.append('    <hasActivationRequired>false</hasActivationRequired>')
    parts.append('    <label>%s</label>' % escape(label))
    obj_rows = dict(ACCESS[ps])
    obj_rows['DE_Assignment_Event__e'] = 'CR' if ps in ('DE_Admin', 'DE_System_Manager') else 'R'
    for obj in sorted(obj_rows):
        letters = obj_rows[obj]
        parts.append('''    <objectPermissions>
        <allowCreate>%s</allowCreate>
        <allowDelete>%s</allowDelete>
        <allowEdit>%s</allowEdit>
        <allowRead>true</allowRead>
        <modifyAllRecords>%s</modifyAllRecords>
        <object>%s</object>
        <viewAllRecords>%s</viewAllRecords>
    </objectPermissions>''' % tuple(['true' if c in letters else 'false' for c in 'CDE'] +
                                    ['true' if 'M' in letters else 'false', obj, 'true' if 'V' in letters else 'false']))
    for t in sorted(TAB_ACCESS[ps]):
        parts.append('''    <tabSettings>
        <tab>%s</tab>
        <visibility>Visible</visibility>
    </tabSettings>''' % t)
    write('permissionsets/%s.permissionset-meta.xml' % ps,
          '<PermissionSet xmlns="%s">\n%s\n</PermissionSet>' % (NS, '\n'.join(parts)))

# ------------------------------------------------------------------ report types
def report_type(name, base, label, desc):
    cols = ['Id', 'Name', 'CreatedDate'] + [f for f, _ in fields_of(base)]
    body = '\n'.join('''        <columns>
            <checkedByDefault>%s</checkedByDefault>
            <field>%s</field>
            <table>%s</table>
        </columns>''' % ('true' if c in ('Name', 'CreatedDate') else 'false', c, base) for c in cols if c != 'Id')
    write('reportTypes/%s.reportType-meta.xml' % name, '''
<ReportType xmlns="%s">
    <baseObject>%s</baseObject>
    <category>other</category>
    <deployed>true</deployed>
    <description>%s</description>
    <label>%s</label>
    <sections>
%s
        <masterLabel>%s</masterLabel>
    </sections>
</ReportType>''' % (NS, base, escape(desc), escape(label), body, escape(label)))


report_type('DE_Assignment_Logs', 'DE_Assignment_Log__c', 'DE Assignment Logs', 'Distribution Engine assignment, SLA, reassignment and rejection history.')
report_type('DE_Availability_Events', 'DE_Availability_Event__c', 'DE Availability Events', 'Distribution Engine online/offline history per user.')
report_type('DE_Run_Logs', 'DE_Run_Log__c', 'DE Run Logs', 'Distribution Engine scheduler, classifier and maintenance runs.')
report_type('DE_Rejected_Assignments', 'DE_Reject_Request__c', 'DE Rejected Assignments', 'Rejection requests: who rejected which record, when and why.')

write('reports/DE_Reports.reportFolder-meta.xml', '''
<ReportFolder xmlns="%s">
    <accessType>Public</accessType>
    <name>Distribution Engine Reports</name>
    <publicFolderAccess>ReadOnly</publicFolderAccess>
</ReportFolder>''' % NS)


def report(dev, name, rtype, base, desc, columns, groupings, filters=(), interval='INTERVAL_LAST30',
           aggregates=(), date_col='CreatedDate'):
    p = []
    for c in columns:
        avg = '\n        <aggregateTypes>Average</aggregateTypes>' if c in aggregates else ''
        p.append('''    <columns>%s
        <field>%s$%s</field>
    </columns>''' % (avg, base, c))
    p.append('    <description>%s</description>' % escape(desc))
    if filters:
        crit = '\n'.join('''        <criteriaItems>
            <column>%s$%s</column>
            <columnToView>false</columnToView>
            <isUnlocked>true</isUnlocked>
            <operator>%s</operator>
            <value>%s</value>
        </criteriaItems>''' % (base, c, op, escape(v)) for c, op, v in filters)
        p.append('    <filter>\n%s\n    </filter>' % crit)
    p.append('    <format>Summary</format>')
    for g, gran in groupings:
        p.append('''    <groupingsDown>
        <dateGranularity>%s</dateGranularity>
        <field>%s$%s</field>
        <sortOrder>Asc</sortOrder>
    </groupingsDown>''' % (gran, base, g))
    p.append('    <name>%s</name>' % escape(name))
    p.append('''    <params>
        <name>co</name>
        <value>1</value>
    </params>''')
    p.append('    <reportType>%s__c</reportType>' % rtype)
    p.append('    <scope>organization</scope>')
    p.append('    <showDetails>false</showDetails>')
    p.append('    <showGrandTotal>true</showGrandTotal>')
    p.append('    <showSubTotals>true</showSubTotals>')
    p.append('''    <timeFrameFilter>
        <dateColumn>%s$%s</dateColumn>
        <interval>%s</interval>
    </timeFrameFilter>''' % (base, date_col, interval))
    write('reports/DE_Reports/%s.report-meta.xml' % dev, '<Report xmlns="%s">\n%s\n</Report>' % (NS, '\n'.join(p)))


LOG = 'DE_Assignment_Log__c'
LOG_COLS = ['Name', 'Record_Name__c', 'Object_API_Name__c', 'Method__c', 'Status__c', 'Assigned_At__c']
report('DE_Distributions_by_Team', 'Distributions by Team', 'DE_Assignment_Logs', LOG,
       'Records distributed per team in the last 30 days.', LOG_COLS, [('Team__c', 'Day')],
       [('Status__c', 'equals', 'Assigned,Reassigned')])
report('DE_Distributions_by_Assignee', 'Distributions by Assignee', 'DE_Assignment_Logs', LOG,
       'Records distributed per assignee in the last 30 days.', LOG_COLS, [('Assigned_User__c', 'Day')],
       [('Status__c', 'equals', 'Assigned,Reassigned')])
report('DE_Distributions_by_Day', 'Distributions by Day', 'DE_Assignment_Logs', LOG,
       'Daily distribution volume by type.', LOG_COLS, [('Assigned_At__c', 'Day'), ('Type__c', 'Day')],
       [('Status__c', 'equals', 'Assigned,Reassigned')], date_col='Assigned_At__c')
report('DE_SLA_Alerts', 'SLA Alerts', 'DE_Assignment_Logs', LOG,
       'Assignments with an SLA alert or a missed SLA checkpoint.', LOG_COLS + ['SLA_Status__c', 'SLA_Missed__c'],
       [('Team__c', 'Day')], [('SLA_Missed__c', 'greaterThan', '0')])
report('DE_Rejections_by_Day', 'Rejected Records by Day', 'DE_Assignment_Logs', LOG,
       'Rejected assignments per day and reason.', LOG_COLS + ['Reject_Reason__c'],
       [('Rejected_At__c', 'Day'), ('Reject_Reason__c', 'Day')], [('Status__c', 'equals', 'Rejected')],
       date_col='Rejected_At__c')
report('DE_Speed_to_Assign', 'Speed to Assign by Team', 'DE_Assignment_Logs', LOG,
       'Average seconds from record creation to assignment, per team.', LOG_COLS + ['Speed_To_Assign_Seconds__c'],
       [('Team__c', 'Day')], [('Status__c', 'equals', 'Assigned')],
       aggregates=['Speed_To_Assign_Seconds__c'])
report('DE_Time_to_Action', 'Time to Action by Assignee', 'DE_Assignment_Logs', LOG,
       'Average minutes from assignment to first action, per assignee.', LOG_COLS + ['Time_To_Action_Mins__c'],
       [('Assigned_User__c', 'Day')], [('Time_To_Action_Mins__c', 'notEqual', '')],
       aggregates=['Time_To_Action_Mins__c'])
report('DE_User_Availability_History', 'User Availability History', 'DE_Availability_Events', 'DE_Availability_Event__c',
       'Online and offline changes per user over the last 7 days.',
       ['Changed_At__c', 'Online__c', 'Source__c', 'Reason__c'], [('User__c', 'Day')],
       interval='INTERVAL_LAST7', date_col='Changed_At__c')
report('DE_Run_History', 'Scheduler Run History', 'DE_Run_Logs', 'DE_Run_Log__c',
       'Scheduler, classifier and maintenance runs with errors in the last 7 days.',
       ['Started_At__c', 'Status__c', 'Records_Processed__c', 'Assignments__c', 'Errors__c', 'Duration_Ms__c'],
       [('Process__c', 'Day')], interval='INTERVAL_LAST7', date_col='Started_At__c')

# ------------------------------------------------------------------ dashboard
write('dashboards/DE_Dashboards.dashboardFolder-meta.xml', '''
<DashboardFolder xmlns="%s">
    <accessType>Public</accessType>
    <name>Distribution Engine Dashboards</name>
    <publicFolderAccess>ReadOnly</publicFolderAccess>
</DashboardFolder>''' % NS)

TILES = [
    ('DE_Distributions_by_Team', 'Distributions by Team', 'Bar', 0, 0, 6),
    ('DE_Distributions_by_Assignee', 'Distributions by Assignee', 'Bar', 6, 0, 6),
    ('DE_Distributions_by_Day', 'Distributions by Day', 'Line', 0, 8, 12),
    ('DE_SLA_Alerts', 'SLA Alerts by Team', 'Bar', 0, 16, 6),
    ('DE_Rejections_by_Day', 'Rejected Records by Day', 'Column', 6, 16, 6),
    ('DE_Speed_to_Assign', 'Speed to Assign', 'Table', 0, 24, 6),
    ('DE_Run_History', 'Scheduler Runs', 'Table', 6, 24, 6),
]
grid = []
for rpt, header, ctype, col, row, span in TILES:
    extra = ''
    if ctype == 'Table':
        extra = '''                <dashboardTableColumns>
                    <column>RowLabel</column>
                </dashboardTableColumns>
                <dashboardTableColumns>
                    <column>RowCount</column>
                    <showSubTotal>true</showSubTotal>
                </dashboardTableColumns>
'''
    elif ctype == 'Line':
        extra = '''                <groupingColumn>DE_Assignment_Log__c$Assigned_At__c</groupingColumn>
                <groupingColumn>DE_Assignment_Log__c$Type__c</groupingColumn>
'''
    grid.append('''        <dashboardGridComponents>
            <colSpan>%d</colSpan>
            <columnIndex>%d</columnIndex>
            <dashboardComponent>
                <autoselectColumnsFromReport>true</autoselectColumnsFromReport>
                <componentType>%s</componentType>
%s                <displayUnits>Integer</displayUnits>
                <drillEnabled>false</drillEnabled>
                <drillToDetailEnabled>false</drillToDetailEnabled>
                <enableHover>true</enableHover>
                <header>%s</header>
                <legendPosition>Bottom</legendPosition>
                <report>DE_Reports/%s</report>
                <showPercentage>false</showPercentage>
                <showValues>true</showValues>
                <sortBy>RowLabelAscending</sortBy>
                <useReportChart>false</useReportChart>
            </dashboardComponent>
            <rowIndex>%d</rowIndex>
            <rowSpan>8</rowSpan>
        </dashboardGridComponents>''' % (span, col, ctype, extra, escape(header), rpt, row))

write('dashboards/DE_Dashboards/DE_Distribution_Engine_Overview.dashboard-meta.xml', '''
<Dashboard xmlns="%s">
    <backgroundEndColor>#FFFFFF</backgroundEndColor>
    <backgroundFadeDirection>Diagonal</backgroundFadeDirection>
    <backgroundStartColor>#FFFFFF</backgroundStartColor>
    <dashboardGridLayout>
%s
        <numberOfColumns>12</numberOfColumns>
        <rowHeight>36</rowHeight>
    </dashboardGridLayout>
    <dashboardType>LoggedInUser</dashboardType>
    <description>Distribution volume, SLA alerts, rejections, speed to assign and scheduler health.</description>
    <isGridLayout>true</isGridLayout>
    <textColor>#000000</textColor>
    <title>Distribution Engine Overview</title>
    <titleColor>#000000</titleColor>
    <titleSize>12</titleSize>
</Dashboard>''' % (NS, '\n'.join(grid)))
print('generated')
