"""Generates custom object / field metadata for Distribution Engine by NC Squared.
Run: python3 genmeta.py <repo-root>"""
import os, sys
from xml.sax.saxutils import escape

ROOT = os.path.join(sys.argv[1], 'force-app', 'main', 'default', 'objects')
HDR = '<?xml version="1.0" encoding="UTF-8"?>'
NS = 'http://soap.sforce.com/2006/04/metadata'


def pick(values, default=None, restricted=True, sorted_=False):
    return {'values': values, 'default': default, 'restricted': restricted}


def F(name, label, type_, **kw):
    d = dict(name=name, label=label, type=type_)
    d.update(kw)
    return d


def field_xml(f):
    t = f['type']
    out = [HDR, f'<CustomField xmlns="{NS}">', f'    <fullName>{f["name"]}</fullName>']
    if f.get('external'):
        out.append('    <externalId>true</externalId>')
    if t == 'Checkbox':
        out.append(f'    <defaultValue>{"true" if f.get("default") else "false"}</defaultValue>')
    if f.get('desc'):
        out.append(f'    <description>{escape(f["desc"])}</description>')
    if f.get('help'):
        out.append(f'    <inlineHelpText>{escape(f["help"])}</inlineHelpText>')
    out.append(f'    <label>{escape(f["label"])}</label>')
    if t in ('Text',):
        out.append(f'    <length>{f.get("length", 255)}</length>')
    if t in ('LongTextArea',):
        out.append(f'    <length>{f.get("length", 32768)}</length>')
        out.append(f'    <visibleLines>{f.get("lines", 5)}</visibleLines>')
    if t == 'TextArea':
        pass
    if t in ('Number', 'Percent'):
        out.append(f'    <precision>{f.get("precision", 18)}</precision>')
        out.append(f'    <scale>{f.get("scale", 0)}</scale>')
        if 'default' in f and f['default'] is not None:
            out.append(f'    <defaultValue>{f["default"]}</defaultValue>')
    if t == 'Lookup':
        out.append(f'    <deleteConstraint>{f.get("delete", "SetNull")}</deleteConstraint>')
        out.append(f'    <referenceTo>{f["ref"]}</referenceTo>')
        out.append(f'    <relationshipLabel>{escape(f.get("rlabel", f["label"]))}</relationshipLabel>')
        out.append(f'    <relationshipName>{f["rname"]}</relationshipName>')
    if t == 'MasterDetail':
        out.append(f'    <referenceTo>{f["ref"]}</referenceTo>')
        out.append(f'    <relationshipLabel>{escape(f.get("rlabel", f["label"]))}</relationshipLabel>')
        out.append(f'    <relationshipName>{f["rname"]}</relationshipName>')
        out.append('    <relationshipOrder>0</relationshipOrder>')
        out.append('    <reparentableMasterDetail>false</reparentableMasterDetail>')
        out.append('    <writeRequiresMasterRead>false</writeRequiresMasterRead>')
    if t not in ('Checkbox', 'MasterDetail') and not f.get('setting'):
        out.append(f'    <required>{"true" if f.get("required") else "false"}</required>')
    if f.get('track'):
        out.append('    <trackHistory>true</trackHistory>')
    if t != 'MasterDetail' and not f.get('setting'):
        out.append('    <trackTrending>false</trackTrending>')
    out.append(f'    <type>{t}</type>')
    if f.get('unique'):
        out.append('    <unique>true</unique>')
        out.append('    <caseSensitive>false</caseSensitive>')
    if t in ('Picklist', 'MultiselectPicklist'):
        p = f['picklist']
        out.append('    <valueSet>')
        out.append(f'        <restricted>{"true" if p.get("restricted", True) else "false"}</restricted>')
        out.append('        <valueSetDefinition>')
        out.append('            <sorted>false</sorted>')
        for v in p['values']:
            out.append('            <value>')
            out.append(f'                <fullName>{escape(v)}</fullName>')
            out.append(f'                <default>{"true" if v == p.get("default") else "false"}</default>')
            out.append(f'                <label>{escape(v)}</label>')
            out.append('            </value>')
        out.append('        </valueSetDefinition>')
        out.append('    </valueSet>')
        if t == 'MultiselectPicklist':
            out.append(f'    <visibleLines>{f.get("lines", 4)}</visibleLines>')
    out.append('</CustomField>\n')
    return '\n'.join(out)


def write_field(obj, f):
    d = os.path.join(ROOT, obj, 'fields')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f['name'] + '.field-meta.xml'), 'w') as fh:
        fh.write(field_xml(f))


def object_xml(o):
    out = [HDR, f'<CustomObject xmlns="{NS}">']
    if o.get('setting'):
        out += [f'    <customSettingsType>Hierarchy</customSettingsType>',
                f'    <description>{escape(o["desc"])}</description>',
                '    <enableFeeds>false</enableFeeds>',
                f'    <label>{escape(o["label"])}</label>',
                '    <visibility>Public</visibility>', '</CustomObject>\n']
        return '\n'.join(out)
    for a in ['Accept', 'CancelEdit', 'Clone', 'Delete', 'Edit', 'List', 'New', 'SaveEdit', 'Tab', 'View']:
        out += ['    <actionOverrides>', f'        <actionName>{a}</actionName>', '        <type>Default</type>', '    </actionOverrides>']
    out += ['    <allowInChatterGroups>false</allowInChatterGroups>',
            '    <compactLayoutAssignment>SYSTEM</compactLayoutAssignment>',
            '    <deploymentStatus>Deployed</deploymentStatus>',
            f'    <description>{escape(o["desc"])}</description>',
            '    <enableActivities>false</enableActivities>',
            '    <enableBulkApi>true</enableBulkApi>',
            '    <enableFeeds>false</enableFeeds>',
            f'    <enableHistory>{"true" if o.get("history") else "false"}</enableHistory>',
            '    <enableLicensing>false</enableLicensing>',
            f'    <enableReports>true</enableReports>',
            '    <enableSearch>true</enableSearch>',
            '    <enableSharing>true</enableSharing>',
            '    <enableStreamingApi>true</enableStreamingApi>',
            f'    <externalSharingModel>{"ControlledByParent" if o.get("sharing") == "ControlledByParent" else "Private"}</externalSharingModel>',
            f'    <label>{escape(o["label"])}</label>',
            '    <nameField>']
    if o.get('autonumber'):
        out += [f'        <displayFormat>{o["autonumber"]}</displayFormat>', f'        <label>{escape(o["name_label"])}</label>',
                '        <type>AutoNumber</type>']
    else:
        out += [f'        <label>{escape(o["name_label"])}</label>', '        <type>Text</type>']
    if o.get('history'):
        out.append('        <trackHistory>true</trackHistory>')
    out += ['    </nameField>', f'    <pluralLabel>{escape(o["plural"])}</pluralLabel>',
            '    <searchLayouts></searchLayouts>',
            f'    <sharingModel>{o.get("sharing", "ReadWrite")}</sharingModel>',
            '    <visibility>Public</visibility>', '</CustomObject>\n']
    return '\n'.join(out)


def write_object(o):
    d = os.path.join(ROOT, o['api'])
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, o['api'] + '.object-meta.xml'), 'w') as fh:
        fh.write(object_xml(o))
    for f in o['fields']:
        if o.get('setting'):
            f['setting'] = True
        write_field(o['api'], f)


