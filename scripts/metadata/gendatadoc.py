import os, sys, xml.etree.ElementTree as ET
R=sys.argv[1]; O=os.path.join(R,'force-app/main/default/objects'); NS='{http://soap.sforce.com/2006/04/metadata}'
def t(e,k): x=e.find(NS+k); return x.text if x is not None else ''
out=[open(sys.argv[2]).read()]
order=['DE_Team__c','DE_Team_Member__c','DE_Distributor__c','DE_Condition__c','DE_Cap__c','DE_SLA__c','DE_Rotation_State__c','DE_Shift__c','DE_Holiday__c','DE_Out_Of_Office__c','DE_Agent__c','DE_Availability_Event__c','DE_Territory__c','DE_Stamp_Group__c','DE_Stamp__c','DE_Matching_Rule__c','DE_Conversion_Rule__c','DE_Object_Sync__c','DE_Record_Detail__c','DE_Assignment_Log__c','DE_Run_Log__c','DE_Settings__c','DE_Assignment_Event__e','Lead','Case','Opportunity','Account','Contact']
for o in order:
    d=os.path.join(O,o)
    if not os.path.isdir(d): continue
    of=os.path.join(d,o+'.object-meta.xml')
    if os.path.exists(of):
        r=ET.parse(of).getroot()
        out.append(f"\n### {t(r,'label') or o} (`{o}`)\n\n{t(r,'description')}\n")
        sm=t(r,'sharingModel')
        if sm: out.append(f"Sharing: `{sm}`.\n")
    else:
        out.append(f"\n### {o} (standard object, fields added)\n")
    out.append('| Field | Label | Type | Notes |\n|---|---|---|---|')
    fd=os.path.join(d,'fields')
    for f in sorted(os.listdir(fd)):
        r=ET.parse(os.path.join(fd,f)).getroot()
        ty=t(r,'type'); notes=[]
        if ty in('Lookup','MasterDetail'): ty+=f" → {t(r,'referenceTo')}"
        if ty=='Text': ty+=f"({t(r,'length')})"
        if t(r,'unique')=='true': notes.append('unique')
        if t(r,'externalId')=='true': notes.append('external id / indexed')
        if t(r,'required')=='true': notes.append('required')
        vs=r.find(NS+'valueSet')
        if vs is not None: notes.append('values: '+', '.join(v.find(NS+'fullName').text for v in vs.iter(NS+'value')))
        dv=t(r,'defaultValue')
        if dv: notes.append('default '+dv)
        h=t(r,'inlineHelpText')
        if h: notes.append(h)
        out.append(f"| `{t(r,'fullName')}` | {t(r,'label')} | {ty} | {'; '.join(notes).replace('|','/')} |")
    vd=os.path.join(d,'validationRules')
    if os.path.isdir(vd):
        out.append('\nValidation rules:\n')
        for f in sorted(os.listdir(vd)):
            r=ET.parse(os.path.join(vd,f)).getroot()
            out.append(f"- `{t(r,'fullName')}`: {t(r,'errorMessage')}")
open(os.path.join(R,'docs/data-model.md'),'w').write('\n'.join(out)+'\n')
