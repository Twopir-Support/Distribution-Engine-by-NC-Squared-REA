"""Page layouts, compact layout, list view, Lightning home page, Visualforce email components and templates,
workflow email alerts and the email notification flows. Run after genmeta2.py: python3 scripts/metadata/genui.py <repo-root>"""
import os
import re
import sys
from xml.sax.saxutils import escape

SRC = os.path.join(sys.argv[1], 'force-app', 'main', 'default')
OBJ = os.path.join(SRC, 'objects')
NS = 'http://soap.sforce.com/2006/04/metadata'
HDR = '<?xml version="1.0" encoding="UTF-8"?>\n'


def write(rel, body):
    p = os.path.join(SRC, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w') as fh:
        fh.write(body if body.startswith('<?xml') or rel.endswith('.email') or rel.endswith('.component') else HDR + body.strip() + '\n')


def read_object(o):
    x = open(os.path.join(OBJ, o, o + '.object-meta.xml')).read()
    label = re.search(r'<label>([^<]+)</label>', x).group(1)
    auto = '<type>AutoNumber</type>' in x
    detail = 'ControlledByParent' in re.search(r'<sharingModel>([^<]+)</sharingModel>', x).group(1)
    fields = []
    fd = os.path.join(OBJ, o, 'fields')
    for f in sorted(os.listdir(fd)) if os.path.isdir(fd) else []:
        fx = open(os.path.join(fd, f)).read()
        name = f.replace('.field-meta.xml', '')
        ftype = re.search(r'<type>([^<]+)</type>', fx).group(1)
        req = '<required>true</required>' in fx or ftype == 'MasterDetail'
        ro = '<formula>' in fx or ftype in ('Summary', 'AutoNumber')
        ref = re.search(r'<referenceTo>([^<]+)</referenceTo>', fx)
        fields.append(dict(name=name, type=ftype, required=req, readonly=ro, ref=ref.group(1) if ref else None,
                           long=ftype in ('LongTextArea', 'TextArea')))
    return dict(api=o, label=label, auto=auto, detail=detail, fields=fields, xml=x)


OBJECTS = sorted(o for o in os.listdir(OBJ) if o.startswith('DE_') and o.endswith('__c') and o != 'DE_Settings__c')
META = {o: read_object(o) for o in OBJECTS}

# children: (child object, lookup field) per parent
CHILDREN = {}
for o, m in META.items():
    for f in m['fields']:
        if f['ref'] and f['ref'] in META and f['type'] in ('Lookup', 'MasterDetail'):
            CHILDREN.setdefault(f['ref'], []).append((o, f['name']))


def item(field, behavior):
    return f'''            <layoutItems>
                <behavior>{behavior}</behavior>
                <field>{field}</field>
            </layoutItems>'''


def section(label, cols, style='TwoColumnsTopToBottom', detail=True):
    out = ['    <layoutSections>', '        <customLabel>true</customLabel>' if label not in ('Information', 'System Information') else '        <customLabel>false</customLabel>',
           f'        <detailHeading>{"true" if detail else "false"}</detailHeading>', '        <editHeading>true</editHeading>', f'        <label>{escape(label)}</label>']
    for c in cols:
        out.append('        <layoutColumns>')
        out += c
        out.append('        </layoutColumns>')
    out += [f'        <style>{style}</style>', '    </layoutSections>']
    return '\n'.join(out)


def layout(o):
    m = META[o]
    short = [f for f in m['fields'] if not f['long']]
    longs = [f for f in m['fields'] if f['long']]
    name_item = item('Name', 'Readonly' if m['auto'] else 'Required')
    left, right = [name_item], []
    for i, f in enumerate(short):
        beh = 'Readonly' if f['readonly'] else ('Required' if f['required'] else 'Edit')
        (right if i % 2 == 0 else left).append(item(f['name'], beh))
    secs = [section('Information', [left, right or [item('CreatedById', 'Readonly')]])]
    if longs:
        secs.append(section('Details', [[item(f['name'], 'Readonly' if f['readonly'] else ('Required' if f['required'] else 'Edit')) for f in longs]], 'OneColumn'))
    sys_left = [item('CreatedById', 'Readonly')]
    if not m['detail']:
        sys_left.append(item('OwnerId', 'Edit'))
    secs.append(section('System Information', [sys_left, [item('LastModifiedById', 'Readonly')]], detail=False))
    rel = []
    for child, fld in sorted(CHILDREN.get(o, [])):
        rel.append(f'''    <relatedLists>
        <fields>NAME</fields>
        <fields>CREATED_DATE</fields>
        <relatedList>{child}.{fld}</relatedList>
    </relatedLists>''')
    if '<enableHistory>true</enableHistory>' in m['xml']:
        rel.append('''    <relatedLists>
        <relatedList>RelatedEntityHistoryList</relatedList>
    </relatedLists>''')
    body = f'''<Layout xmlns="{NS}">
{chr(10).join(secs)}
    <miniLayout>
        <fields>Name</fields>
    </miniLayout>
{chr(10).join(rel)}
    <showEmailCheckbox>false</showEmailCheckbox>
    <showHighlightsPanel>false</showHighlightsPanel>
    <showInteractionLogPanel>false</showInteractionLogPanel>
    <showRunAssignmentRulesCheckbox>false</showRunAssignmentRulesCheckbox>
    <showSubmitAndAttachButton>false</showSubmitAndAttachButton>
</Layout>'''
    write(f'layouts/{o}-{m["label"]} Layout.layout-meta.xml', body)


for o in OBJECTS:
    layout(o)

# ---------------------------------------------------------------- compact layout + list view
write('objects/DE_Record_Detail__c/compactLayouts/DE_Record_Detail.compactLayout-meta.xml', f'''
<CompactLayout xmlns="{NS}">
    <fields>Name</fields>
    <fields>Object_API_Name__c</fields>
    <fields>Classifier_Status__c</fields>
    <fields>Territory_Name__c</fields>
    <fields>Matched_Account__c</fields>
    <fields>On_Hold_Until__c</fields>
    <label>Distribution Engine Details</label>
</CompactLayout>''')
p = os.path.join(OBJ, 'DE_Record_Detail__c', 'DE_Record_Detail__c.object-meta.xml')
x = open(p).read().replace('<compactLayoutAssignment>SYSTEM</compactLayoutAssignment>', '<compactLayoutAssignment>DE_Record_Detail</compactLayoutAssignment>')
open(p, 'w').write(x)

write('objects/DE_Team__c/listViews/All.listView-meta.xml', f'''
<ListView xmlns="{NS}">
    <fullName>All</fullName>
    <columns>NAME</columns>
    <columns>Object_API_Name__c</columns>
    <columns>Active__c</columns>
    <columns>Execution_Order__c</columns>
    <columns>Holiday_Region__c</columns>
    <columns>LAST_UPDATE</columns>
    <filterScope>Everything</filterScope>
    <label>All</label>
</ListView>''')

# ---------------------------------------------------------------- Lightning home page with the widget
write('flexipages/DE_Home.flexipage-meta.xml', f'''
<FlexiPage xmlns="{NS}">
    <flexiPageRegions>
        <itemInstances>
            <componentInstance>
                <componentName>deAssignedToMe</componentName>
                <identifier>deAssignedToMe</identifier>
            </componentInstance>
        </itemInstances>
        <mode>Replace</mode>
        <name>top</name>
        <type>Region</type>
    </flexiPageRegions>
    <flexiPageRegions>
        <mode>Replace</mode>
        <name>bottomLeft</name>
        <type>Region</type>
    </flexiPageRegions>
    <flexiPageRegions>
        <mode>Replace</mode>
        <name>bottomRight</name>
        <type>Region</type>
    </flexiPageRegions>
    <flexiPageRegions>
        <itemInstances>
            <componentInstance>
                <componentName>deWidget</componentName>
                <identifier>deWidget</identifier>
            </componentInstance>
        </itemInstances>
        <mode>Replace</mode>
        <name>sidebar</name>
        <type>Region</type>
    </flexiPageRegions>
    <masterLabel>DE Default</masterLabel>
    <template>
        <name>home:desktopTemplate</name>
    </template>
    <type>HomePage</type>
</FlexiPage>''')

# ---------------------------------------------------------------- Visualforce email components
VF_META = f'''<?xml version="1.0" encoding="UTF-8"?>
<ApexComponent xmlns="{NS}">
    <apiVersion>66.0</apiVersion>
    <description>{{desc}}</description>
    <label>{{label}}</label>
</ApexComponent>
'''


def component(name, label, desc, markup):
    write(f'components/{name}.component', markup.strip() + '\n')
    write(f'components/{name}.component-meta.xml', VF_META.format(desc=escape(desc), label=escape(label)))


component('DE_EmailNotificationLink', 'DE Email Notification Link', 'Link to the assigned record in Lightning Experience.', '''
<apex:component access="global">
    <apex:attribute name="recordId" type="String" required="true" description="Id of the assigned record" />
    <apex:attribute name="label" type="String" required="true" description="Link text" />
    <a href="{!LEFT($Api.Partner_Server_URL_660, FIND('/services', $Api.Partner_Server_URL_660))}{!recordId}">{!label}</a>
</apex:component>''')

component('DE_EmailNotificationFooter', 'DE Email Notification Footer', 'Footer explaining why the email was sent.', '''
<apex:component access="global">
    <apex:attribute name="teamName" type="String" required="false" description="Team that assigned the record" />
    <p style="color:#706e6b;font-size:12px;margin-top:24px">
        You received this email because Distribution Engine by NC Squared assigned a record to you<apex:outputText value=" through the {!teamName} team" rendered="{!NOT(ISBLANK(teamName))}" />.
        Your administrator can turn these emails off per distributor (Post assignment: Send standard email notifications).
    </p>
</apex:component>''')

component('DE_EmailNotification', 'DE Email Notification', 'Body of the assignment notification: the record summary fields per object.', '''
<apex:component access="global">
    <apex:attribute name="log" type="DE_Assignment_Log__c" required="true" description="Distribution log the email is about" />
    <apex:attribute name="headline" type="String" required="true" description="First line of the email" />
    <div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#181818">
        <p>{!headline}</p>
        <table cellpadding="4" style="border-collapse:collapse">
            <apex:outputPanel layout="none" rendered="{!NOT(ISBLANK(log.Lead__c))}">
                <tr><td><b>Name</b></td><td><c:DE_EmailNotificationLink recordId="{!log.Lead__c}" label="{!log.Lead__r.Name}" /></td></tr>
                <tr><td><b>Lead Source</b></td><td>{!log.Lead__r.LeadSource}</td></tr>
                <tr><td><b>Company</b></td><td>{!log.Lead__r.Company}</td></tr>
                <tr><td><b>Rating</b></td><td>{!log.Lead__r.Rating}</td></tr>
                <tr><td><b>Status</b></td><td>{!log.Lead__r.Status}</td></tr>
            </apex:outputPanel>
            <apex:outputPanel layout="none" rendered="{!NOT(ISBLANK(log.Opportunity__c))}">
                <tr><td><b>Name</b></td><td><c:DE_EmailNotificationLink recordId="{!log.Opportunity__c}" label="{!log.Opportunity__r.Name}" /></td></tr>
                <tr><td><b>Lead Source</b></td><td>{!log.Opportunity__r.LeadSource}</td></tr>
                <tr><td><b>Type</b></td><td>{!log.Opportunity__r.Type}</td></tr>
                <tr><td><b>Stage</b></td><td>{!log.Opportunity__r.StageName}</td></tr>
            </apex:outputPanel>
            <apex:outputPanel layout="none" rendered="{!NOT(ISBLANK(log.Case__c))}">
                <tr><td><b>Case Number</b></td><td><c:DE_EmailNotificationLink recordId="{!log.Case__c}" label="{!log.Case__r.CaseNumber}" /></td></tr>
                <tr><td><b>Subject</b></td><td>{!log.Case__r.Subject}</td></tr>
                <tr><td><b>Priority</b></td><td>{!log.Case__r.Priority}</td></tr>
                <tr><td><b>Type</b></td><td>{!log.Case__r.Type}</td></tr>
                <tr><td><b>Account</b></td><td>{!log.Case__r.Account.Name}</td></tr>
                <tr><td><b>Contact</b></td><td>{!log.Case__r.Contact.Name}</td></tr>
                <tr><td><b>Status</b></td><td>{!log.Case__r.Status}</td></tr>
            </apex:outputPanel>
            <apex:outputPanel layout="none" rendered="{!AND(ISBLANK(log.Lead__c), ISBLANK(log.Opportunity__c), ISBLANK(log.Case__c))}">
                <tr><td><b>Record</b></td><td><c:DE_EmailNotificationLink recordId="{!log.Record_Id__c}" label="{!log.Record_Name__c}" /></td></tr>
                <tr><td><b>Object</b></td><td>{!log.Object_API_Name__c}</td></tr>
            </apex:outputPanel>
        </table>
        <c:DE_EmailNotificationFooter teamName="{!log.Team__r.Name}" />
    </div>
</apex:component>''')

# ---------------------------------------------------------------- email templates (Visualforce)
write('email/DE_Templates.emailFolder-meta.xml', f'''
<EmailFolder xmlns="{NS}">
    <accessType>Public</accessType>
    <name>Distribution Engine Templates</name>
    <publicFolderAccess>ReadOnly</publicFolderAccess>
</EmailFolder>''')

TEMPLATES = [
    ('DE_Notification', 'Distribution Engine Notification', 'Sent to the assignee when a record is assigned to them.',
     '{!relatedTo.Object_API_Name__c} assigned to you: {!relatedTo.Record_Name__c}',
     'A {!relatedTo.Object_API_Name__c} has been assigned to you{!IF(ISBLANK(relatedTo.Team__c), \'\', \' by the \' + relatedTo.Team__r.Name + \' team\')}.'),
    ('DE_Notification_v2', 'Distribution Engine Notification v2', 'Sent to the assignee when an SLA checkpoint on their assignment is missed.',
     'SLA alert: {!relatedTo.Record_Name__c}',
     'An SLA checkpoint was missed on a {!relatedTo.Object_API_Name__c} assigned to you. Please action it as soon as possible.'),
    ('DE_Role_Notification', 'Distribution Engine Role Notification', 'Sent when a user is added to an Account, Opportunity or Case team with a role.',
     'You were added as {!relatedTo.Team_Role__c}: {!relatedTo.Record_Name__c}',
     'You have been added to the {!relatedTo.Object_API_Name__c} team as {!relatedTo.Team_Role__c}.'),
]
for dev, name, desc, subject, headline in TEMPLATES:
    write(f'email/DE_Templates/{dev}.email', f'''<messaging:emailTemplate subject="{subject}" recipientType="User" relatedToType="DE_Assignment_Log__c">
    <messaging:htmlEmailBody>
        <c:DE_EmailNotification log="{{!relatedTo}}" headline="{headline}" />
    </messaging:htmlEmailBody>
    <messaging:plainTextEmailBody>
{headline}
{{!relatedTo.Record_Name__c}}
{{!LEFT($Api.Partner_Server_URL_660, FIND('/services', $Api.Partner_Server_URL_660))}}{{!relatedTo.Record_Id__c}}
    </messaging:plainTextEmailBody>
</messaging:emailTemplate>
''')
    write(f'email/DE_Templates/{dev}.email-meta.xml', f'''
<EmailTemplate xmlns="{NS}">
    <available>true</available>
    <description>{escape(desc)}</description>
    <encodingKey>UTF-8</encodingKey>
    <name>{escape(name)}</name>
    <style>none</style>
    <subject>{escape(subject)}</subject>
    <type>visualforce</type>
    <uiType>Aloha</uiType>
</EmailTemplate>''')

# ---------------------------------------------------------------- workflow email alerts
ALERTS = [('DE_Email_Notification', 'Distribution Engine - Email Notification', 'DE_Notification'),
          ('DE_Email_Notification_v2', 'Distribution Engine - Email Notification v2', 'DE_Notification_v2'),
          ('DE_Email_Notification_Team_Role', 'Distribution Engine - Email Notification Team Role', 'DE_Role_Notification')]
alerts = []
for dev, desc, tpl in ALERTS:
    alerts.append(f'''    <alerts>
        <fullName>{dev}</fullName>
        <description>{escape(desc)}</description>
        <protected>false</protected>
        <recipients>
            <field>Assigned_User__c</field>
            <type>userLookup</type>
        </recipients>
        <senderType>CurrentUser</senderType>
        <template>DE_Templates/{tpl}</template>
    </alerts>''')
write('workflows/DE_Assignment_Log__c.workflow-meta.xml', f'<Workflow xmlns="{NS}">\n' + '\n'.join(alerts) + '\n</Workflow>')


# ---------------------------------------------------------------- record-triggered flows
def flow(name, label, desc, trigger, filters, alert, changed=False):
    fl = []
    for field, op, kind, val in filters:
        fl.append(f'''        <filters>
            <field>{field}</field>
            <operator>{op}</operator>
            <value>
                <{kind}>{val}</{kind}>
            </value>
        </filters>''')
    body = f'''<Flow xmlns="{NS}">
    <actionCalls>
        <name>Send_Email</name>
        <label>Send Email</label>
        <locationX>176</locationX>
        <locationY>335</locationY>
        <actionName>DE_Assignment_Log__c.{alert}</actionName>
        <actionType>emailAlert</actionType>
        <flowTransactionModel>CurrentTransaction</flowTransactionModel>
        <inputParameters>
            <name>SObjectRowId</name>
            <value>
                <elementReference>$Record.Id</elementReference>
            </value>
        </inputParameters>
        <nameSegment>DE_Assignment_Log__c.{alert}</nameSegment>
    </actionCalls>
    <apiVersion>66.0</apiVersion>
    <description>{escape(desc)}</description>
    <environments>Default</environments>
    <interviewLabel>{escape(label)} {{!$Flow.CurrentDateTime}}</interviewLabel>
    <label>{escape(label)}</label>
    <processMetadataValues>
        <name>BuilderType</name>
        <value>
            <stringValue>LightningFlowBuilder</stringValue>
        </value>
    </processMetadataValues>
    <processMetadataValues>
        <name>CanvasMode</name>
        <value>
            <stringValue>AUTO_LAYOUT_CANVAS</stringValue>
        </value>
    </processMetadataValues>
    <processMetadataValues>
        <name>OriginBuilderType</name>
        <value>
            <stringValue>LightningFlowBuilder</stringValue>
        </value>
    </processMetadataValues>
    <processType>AutoLaunchedFlow</processType>
    <start>
        <locationX>50</locationX>
        <locationY>0</locationY>
        <connector>
            <targetReference>Send_Email</targetReference>
        </connector>{chr(10) + '        <doesRequireRecordChangedToMeetCriteria>true</doesRequireRecordChangedToMeetCriteria>' if changed else ''}
        <filterLogic>and</filterLogic>
{chr(10).join(fl)}
        <object>DE_Assignment_Log__c</object>
        <recordTriggerType>{trigger}</recordTriggerType>
        <triggerType>RecordAfterSave</triggerType>
    </start>
    <status>Active</status>
</Flow>'''
    write(f'flows/{name}.flow-meta.xml', body)


BASE = [('Send_Email__c', 'EqualTo', 'booleanValue', 'true'), ('Assigned_User__c', 'IsNull', 'booleanValue', 'false')]
flow('DE_Email_Notification_on_new_log', 'DE Email Notification on new log',
     'Emails the assignee when a distribution log is created for an assignment (Send Standard Email set from the distributor).', 'Create',
     BASE + [('Team_Role__c', 'IsNull', 'booleanValue', 'true'), ('Status__c', 'EqualTo', 'stringValue', 'Assigned')], 'DE_Email_Notification')
flow('DE_Email_Notification_on_log_update', 'DE Email Notification on log update',
     'Emails the assignee when an SLA checkpoint is missed on their current assignment.', 'Update',
     BASE + [('Team_Role__c', 'IsNull', 'booleanValue', 'true'), ('SLA_Missed__c', 'IsChanged', 'booleanValue', 'true'),
             ('Current__c', 'EqualTo', 'booleanValue', 'true')], 'DE_Email_Notification_v2', changed=True)
flow('DE_Email_Team_Role_Notification_on_new_log', 'DE Email Team Role Notification on new log',
     'Emails a user added to an Account, Opportunity or Case team by a role assignment distributor.', 'Create',
     BASE + [('Team_Role__c', 'IsNull', 'booleanValue', 'false')], 'DE_Email_Notification_Team_Role')
flow('DE_Email_Team_Role_Notification_on_log_update', 'DE Email Team Role Notification on log update',
     'Emails the team member again when the role on their distribution log changes.', 'Update',
     BASE + [('Team_Role__c', 'IsNull', 'booleanValue', 'false'), ('Team_Role__c', 'IsChanged', 'booleanValue', 'true')],
     'DE_Email_Notification_Team_Role', changed=True)
print('ui generated:', len(OBJECTS), 'layouts')
