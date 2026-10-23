"""Builds the metadata inventory, dependency map, replication matrix and summary from the reference CSV
and the current repository. Run: python3 -I gen_matrix.py <csv> <repo-root>"""
import collections
import csv
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from csvmap_objects import OBJECTS, FIELDS, STANDARD_FIELDS  # noqa: E402
from csvmap_other import (classify_apex, VF_PAGES, VF_COMPONENTS, LWC, AURA, FLOWS, TRIGGERS, TABS, PERMSETS, REPORTS, MISC,  # noqa: E402
                          STATIC_RESOURCES)

CSV_PATH, REPO = sys.argv[1], sys.argv[2]
SRC = os.path.join(REPO, 'force-app', 'main', 'default')
DOCS = os.path.join(REPO, 'docs')
STANDARD_OBJECTS = {'Lead', 'Case', 'Opportunity', 'Contact', 'Account', 'Task', 'Event'}

rows = list(csv.DictReader(open(CSV_PATH, encoding='utf-8-sig')))
for i, r in enumerate(rows, 1):
    r['row'] = i
    r['name'] = r['Component Name'].strip()
    r['parent'] = r['Parent Object'].strip()
    r['type'] = r['Type'].strip()


# ---------------------------------------------------------------- repository checks
def exists(target):
    if target is None:
        return False
    if ':' in target:
        kind, rest = target.split(':', 1)
        paths = {
            'cls': f'classes/{rest}.cls', 'lwc': f'lwc/{rest}', 'flow': f'flows/{rest}.flow-meta.xml', 'trigger': f'triggers/{rest}.trigger',
            'tab': f'tabs/{rest}.tab-meta.xml', 'permset': f'permissionsets/{rest}.permissionset-meta.xml', 'report': f'reports/{rest}.report-meta.xml',
            'dashboard': f'dashboards/{rest}.dashboard-meta.xml', 'reporttype': f'reportTypes/{rest}.reportType-meta.xml',
            'reportfolder': f'reports/{rest}.reportFolder-meta.xml', 'dashboardfolder': f'dashboards/{rest}.dashboardFolder-meta.xml',
            'app': f'applications/{rest}.app-meta.xml', 'cache': f'cachePartitions/{rest}.cachePartition-meta.xml',
            'flexipage': f'flexipages/{rest}.flexipage-meta.xml', 'prompt': f'prompts/{rest}.prompt-meta.xml',
            'emailfolder': f'email/{rest}.emailFolder-meta.xml', 'email': f'email/{rest}.email-meta.xml',
        }
        if kind in paths:
            return os.path.exists(os.path.join(SRC, paths[kind]))
        if kind == 'listview':
            o, n = rest.split('.')
            return os.path.exists(os.path.join(SRC, 'objects', o, 'listViews', n + '.listView-meta.xml'))
        if kind == 'compact':
            o, n = rest.split('.')
            return os.path.exists(os.path.join(SRC, 'objects', o, 'compactLayouts', n + '.compactLayout-meta.xml'))
        if kind == 'alert':
            o, n = rest.split('.')
            p = os.path.join(SRC, 'workflows', o + '.workflow-meta.xml')
            return os.path.exists(p) and f'<fullName>{n}</fullName>' in open(p).read()
        if kind == 'layout':
            return bool(glob.glob(os.path.join(SRC, 'layouts', rest + '-*.layout-meta.xml')))
        raise ValueError(target)
    if '.' in target:
        o, f = target.split('.', 1)
        if f in ('Name', 'Id', 'OwnerId'):
            return o in STANDARD_OBJECTS or os.path.isdir(os.path.join(SRC, 'objects', o))
        return os.path.exists(os.path.join(SRC, 'objects', o, 'fields', f + '.field-meta.xml'))
    return os.path.isdir(os.path.join(SRC, 'objects', target)) or target in STANDARD_OBJECTS


def status_for(targets):
    targets = [t for t in targets if t]
    if not targets:
        return 'Not Started'
    have = [exists(t) for t in targets]
    if all(have):
        return 'Implemented'
    if any(have):
        return 'Implementing'
    return 'Identified'


def obj_target(ref_obj):
    if ref_obj in STANDARD_OBJECTS:
        return ref_obj
    o = OBJECTS.get(ref_obj)
    return o[1] if o else None


def target_object_of(t):
    if not t or ':' in t:
        return None
    return t.split('.')[0]


# ---------------------------------------------------------------- per-row mapping
def map_row(r):
    n, p, t = r['name'], r['parent'], r['type']
    out = dict(targets=[], status='Not Started', dep='', notes='', area='')
    def special(spec):
        if isinstance(spec, str):
            kind, note = spec.split(':', 1)
            out['status'] = {'na': 'Not Applicable', 'blocked': 'Blocked'}[kind]
            out['notes'] = note
            return True
        out['targets'] = spec
        return False

    if t == 'Custom Object':
        kind, target, note = OBJECTS.get(n, ('investigate', None, 'Not mapped yet.'))
        out['area'] = 'Data model'
        out['notes'] = note
        if kind == 'na':
            out['status'] = 'Not Applicable'
        elif kind == 'blocked':
            out['status'] = 'Blocked'
        elif kind == 'investigate':
            out['status'] = 'Investigating'
        else:
            out['targets'] = [target]
            if kind == 'equiv':
                out['notes'] = ('Equivalent design. ' + note).strip()
    elif t == 'Custom Field':
        out['area'] = 'Data model'
        ptarget = obj_target(p)
        out['dep'] = ptarget or ''
        if p in STANDARD_OBJECTS:
            spec = STANDARD_FIELDS.get(n)
            if isinstance(spec, tuple):
                out['targets'] = [spec[0]]
                out['notes'] = spec[1]
            elif spec:
                out['targets'] = [p + '.' + spec]
            else:
                out['notes'] = 'No equivalent field yet.'
        else:
            kind, target, onote = OBJECTS.get(p, ('investigate', None, ''))
            if kind in ('na', 'blocked'):
                out['status'] = 'Not Applicable' if kind == 'na' else 'Blocked'
                out['notes'] = 'Parent object: ' + (onote or kind)
            else:
                spec = FIELDS.get(p, {}).get(n)
                if spec is None and kind == 'equiv':
                    out['targets'] = [target]
                    out['notes'] = 'Covered by the equivalent target of the parent object. ' + onote
                elif spec is None:
                    out['notes'] = 'No equivalent field mapped yet.'
                elif isinstance(spec, tuple):
                    if spec[0] == 'na':
                        out['status'] = 'Not Applicable'
                        out['notes'] = spec[1]
                    else:
                        out['targets'] = [spec[0]]
                        out['notes'] = spec[1]
                else:
                    out['targets'] = [spec]
    elif t == 'Page Layout':
        out['area'] = 'UI (layouts)'
        ptarget = obj_target(p)
        kind = OBJECTS.get(p, ('',))[0]
        out['dep'] = ptarget or ''
        if kind in ('na', 'blocked'):
            out['status'] = 'Not Applicable' if kind == 'na' else 'Blocked'
            out['notes'] = 'Parent object is not replicated.'
        elif ptarget == 'DE_Settings__c':
            out['status'] = 'Not Applicable'
            out['notes'] = 'Mapped to a hierarchy custom setting, which has no page layout; edited in the Settings tab.'
        elif ptarget and ':' not in ptarget and '.' not in ptarget:
            out['targets'] = ['layout:' + ptarget]
        else:
            out['notes'] = 'Parent object is covered by an equivalent design without its own object.'
            out['status'] = 'Not Applicable'
    elif t == 'Apex Class':
        area, targets, kind, note = classify_apex(n)
        out['area'] = area
        out['notes'] = note
        if kind == 'na':
            out['status'] = 'Not Applicable'
        elif kind == 'blocked':
            out['status'] = 'Blocked'
        elif kind == 'investigate':
            out['status'] = 'Investigating'
        else:
            out['targets'] = targets
            if kind == 'test':
                out['dep'] = ', '.join(x.split(':')[-1] for x in targets)
                out['notes'] = (note + ' ').strip()
    elif t == 'Apex Trigger':
        out['area'] = 'Triggers'
        out['dep'] = obj_target(p) or ''
        special(TRIGGERS.get(n, 'na:Unknown trigger.'))
    elif t == 'Visualforce Page':
        out['area'] = 'UI (Visualforce → LWC)'
        if not special(VF_PAGES.get(n, [])):
            out['notes'] = 'Visualforce page replaced by the Lightning web component.'
    elif t == 'Visualforce Component':
        out['area'] = 'UI (Visualforce → LWC)'
        if not special(VF_COMPONENTS.get(n, [])):
            out['notes'] = 'Visualforce component replaced by the target.'
    elif t == 'Lightning Web Component Bundle':
        out['area'] = 'UI (LWC)'
        special(LWC.get(n, []))
    elif t == 'Aura Component Bundle':
        out['area'] = 'UI (Aura → LWC)'
        if not special(AURA.get(n, [])):
            out['notes'] = 'Aura wrapper (Lightning Out) replaced by the LWC.'
    elif t == 'Flow Definition':
        out['area'] = 'Automation'
        special(FLOWS.get(n, []))
    elif t == 'Tab':
        out['area'] = 'UI (navigation)'
        special(TABS.get(n, []))
    elif t == 'Permission Set':
        out['area'] = 'Security'
        special(PERMSETS.get(n, []))
    elif t == 'Report':
        out['area'] = 'Reporting'
        special(REPORTS.get(n, []))
    elif t == 'Static Resource':
        out['area'] = 'UI (resources)'
        special(STATIC_RESOURCES.get(n, 'na:Unknown resource.'))
    elif t.startswith('Feature Parameter'):
        out['area'] = 'Licensing / ISV telemetry'
        out['status'] = 'Not Applicable'
        out['notes'] = 'LMA feature parameter; only meaningful in a managed package connected to a License Management App.'
    elif t == 'Document':
        out['area'] = 'Branding'
        out['status'] = 'Not Applicable'
        out['notes'] = 'Vendor logo image; not copied. SLDS icons are used.'
    else:
        spec = MISC.get((t, n))
        out['area'] = {'Workflow Email Alert': 'Automation', 'Workflow Rule': 'Automation', 'Classic Email Template': 'Email',
                       'Classic Email Template Folder': 'Email', 'Dashboard': 'Reporting', 'Custom Report Type': 'Reporting',
                       'Report Folder': 'Reporting', 'Dashboard Folder': 'Reporting'}.get(t, 'Platform')
        if spec is None:
            out['status'] = 'Investigating'
            out['notes'] = 'Not mapped yet.'
        else:
            special(spec)
            if t == 'Workflow Rule':
                out['notes'] = 'Workflow rules are retired for new automation; replaced by record-triggered flows.'
            if t == 'Home Page Component' or t == 'Home Page Layout':
                out['notes'] = 'Classic home page; replaced by a Lightning home page with the widget.'
    if out['targets'] and out['status'] == 'Not Started':
        out['status'] = status_for(out['targets'])
    if not out['dep']:
        deps = sorted({target_object_of(x) for x in out['targets'] if target_object_of(x)} - {None})
        if t != 'Custom Object':
            out['dep'] = ', '.join(deps)
    return out


for r in rows:
    r.update(map_row(r))


# ---------------------------------------------------------------- outputs
def fmt_targets(ts):
    out = []
    for x in ts:
        out.append('`' + x + '`' + ('' if exists(x) else ' (planned)'))
    return '<br>'.join(out) if out else '—'


def esc(s):
    return (s or '').replace('|', '\\|').replace('\n', ' ')


type_counts = collections.Counter(r['type'] for r in rows)
status_counts = collections.Counter(r['status'] for r in rows)
by_type_status = collections.defaultdict(collections.Counter)
for r in rows:
    by_type_status[r['type']][r['status']] += 1

STATUSES = ['Implemented', 'Implementing', 'Identified', 'Investigating', 'Not Started', 'Blocked', 'Not Applicable']

# --- replication matrix
lines = ['# Metadata Replication Matrix', '',
         'One row per component in `Metadata Components Included in Package - Sheet1.csv` (the reference package inventory), '
         f'{len(rows)} rows in CSV order within each type section. Generated by `scripts/metadata/gen_matrix.py` from the CSV and the current repository.', '',
         '**How status is decided**',
         '- `Implemented`: every target listed exists in this repository. It does **not** mean tests were executed. No Salesforce org was available, so Apex tests have not run.',
         '- `Implementing`: some, but not all, targets exist.',
         '- `Identified`: the target is designed (marked *planned*), but does not exist yet.',
         '- `Investigating`: the purpose is not yet established from the available evidence.',
         '- `Not Started`: no target designed yet.',
         '- `Blocked`: needs an external system or credentials (the Slack app, OAuth, vendor middleware).',
         '- `Not Applicable`: ISV licensing, vendor telemetry, vendor messaging, branding or package-upgrade plumbing.', '',
         '`Tested` is not used, because no test has been executed. Test coverage that exists is named in the notes and in `docs/parity-matrix.md`.', '',
         '**Target notation**: `DE_X__c` object · `DE_X__c.Field__c` field · `cls:` Apex class · `lwc:` Lightning web component · `flow:` · `trigger:` · `tab:` · `permset:` · `report:` · `layout:` page layout(s) of an object · `email:` classic email template · `alert:` workflow email alert.', '']
for t, _ in type_counts.most_common():
    lines += [f'## {t} ({type_counts[t]})', '', '| # | Reference Component | Parent Object | Metadata Type | Target Component | Status | Dependency | Notes |',
              '|---|---|---|---|---|---|---|---|']
    for r in rows:
        if r['type'] != t:
            continue
        lines.append(f"| {r['row']} | {esc(r['name'])} | {esc(r['parent']) or '—'} | {t} | {fmt_targets(r['targets'])} | {r['status']} | {esc(r['dep']) or '—'} | {esc(r['notes'])} |")
    lines.append('')
open(os.path.join(DOCS, 'metadata-replication-matrix.md'), 'w').write('\n'.join(lines))

# --- inventory
inv = ['# Metadata Component Inventory', '',
       'Source: `Metadata Components Included in Package - Sheet1.csv`, the component list of the reference AppExchange package '
       '"Distribution Engine" (listing a0N30000009x4YAEAY). The CSV gives component names (labels for objects and fields), parent objects and metadata types. '
       'It gives no API names, field types or source code. The managed package hides its Apex source, and no org with the package installed was available. '
       'Behaviour is therefore established from the public help centre and listing (see `evidence-and-gaps.md`), not from the package internals.', '',
       f'**Total components: {len(rows)}**', '', '## 1. Components by metadata type', '', '| Type | Count | ' + ' | '.join(STATUSES) + ' |',
       '|---|---|' + '---|' * len(STATUSES)]
for t, c in type_counts.most_common():
    inv.append(f'| {t} | {c} | ' + ' | '.join(str(by_type_status[t][s] or '') for s in STATUSES) + ' |')
inv.append(f'| **Total** | **{len(rows)}** | ' + ' | '.join(f'**{status_counts[s]}**' for s in STATUSES) + ' |')

parent_counts = collections.defaultdict(collections.Counter)
for r in rows:
    if r['parent']:
        parent_counts[r['parent']][r['type']] += 1
inv += ['', '## 2. Components by parent object', '',
        'Custom Fields, Page Layouts, triggers, workflow items, list views and compact layouts are listed under their parent. The target column shows the replicated object.', '',
        '| Parent Object | Target | Kind | Fields | Layouts | Other | Total |', '|---|---|---|---|---|---|---|']
for p in sorted(parent_counts, key=lambda k: -sum(parent_counts[k].values())):
    c = parent_counts[p]
    kind = 'standard' if p in STANDARD_OBJECTS else OBJECTS.get(p, ('?',))[0]
    tgt = obj_target(p) or '—'
    other = sum(v for k, v in c.items() if k not in ('Custom Field', 'Page Layout'))
    inv.append(f"| {p} | `{tgt}` | {kind} | {c['Custom Field']} | {c['Page Layout']} | {other} | {sum(c.values())} |")

area_counts = collections.defaultdict(collections.Counter)
for r in rows:
    area_counts[r['area'] or 'Other'][r['status']] += 1
inv += ['', '## 3. Components by functional area', '',
        'Apex classes were classified by name with ordered rules (see `scripts/metadata/csvmap_other.py`); every other type by its metadata type. A name only suggests the area. The behaviour of each area comes from the help centre.', '',
        '| Functional area | Total | ' + ' | '.join(STATUSES) + ' |', '|---|---|' + '---|' * len(STATUSES)]
for a in sorted(area_counts, key=lambda k: -sum(area_counts[k].values())):
    c = area_counts[a]
    inv.append(f'| {a} | {sum(c.values())} | ' + ' | '.join(str(c[s] or '') for s in STATUSES) + ' |')

apex = [r for r in rows if r['type'] == 'Apex Class']
tests = [r for r in apex if re.search(r'(_Tests?|Tests?)$', r['name'])]
inv += ['', '### Apex class roles (by naming convention)', '',
        '| Role (suffix/prefix) | Count |', '|---|---|']
roles = collections.Counter()
for r in apex:
    n = r['name']
    if re.search(r'(_Tests?|Tests?)$', n):
        roles['Test classes (*_Tests)'] += 1
    elif n.startswith('Mock') or n.startswith('TestUtils'):
        roles['Test mocks and builders (Mock*, TestUtils_*)'] += 1
    elif n.endswith('_Controller') or n.endswith('Controller'):
        roles['Controllers (VF/LWC)'] += 1
    elif n.endswith('UIVO') or n.endswith('VO') or n.endswith('DTO'):
        roles['Value/transfer objects (*VO, *UIVO, *DTO)'] += 1
    elif n.endswith('DAO') or n.endswith('UIDAO'):
        roles['Data access (*DAO)'] += 1
    elif n.endswith('Service'):
        roles['Services (*Service)'] += 1
    elif n.endswith('Utils') or n.endswith('Utility') or n.endswith('UIUtils') or n.endswith('Helper'):
        roles['Utilities and helpers'] += 1
    elif n.startswith('I') and n[1:2].isupper():
        roles['Interfaces (I*)'] += 1
    elif 'EmailBuilder' in n:
        roles['Email builders'] += 1
    elif n.startswith('Trigger'):
        roles['Trigger handlers (Trigger*)'] += 1
    elif n.startswith('Housekeeping'):
        roles['Housekeeping tasks'] += 1
    else:
        roles['Other (executors, jobs, batches, queueables)'] += 1
for k, v in roles.most_common():
    inv.append(f'| {k} | {v} |')
inv += ['', f'Apex: {len(apex)} classes, of which {len(tests)} are test classes. The reference uses a layered design: VF/LWC controller → UIVO/DTO → service → DAO. '
        'The target keeps the layering lighter: LWC → `*Controller` → services (`DE_*Service`, `DE_Distribution*`) → `DE_ConfigRepository`/`DE_RecordQuery`. '
        'Replicating 1,341 class names one to one would mean writing classes whose internals are unknown, so each reference class is mapped to the target class that carries the same responsibility.']

# duplicates / similar names
inv += ['', '## 4. Duplicate and similar component names', '']
dupe = collections.Counter((r['type'], r['parent'], r['name'].lower()) for r in rows)
dups = [(k, v) for k, v in dupe.items() if v > 1]
inv += ['**Exact duplicates (same type, parent and case-insensitive name).** These are separate fields that share a label (different API names):', '']
for (t, p, n), v in sorted(dups):
    inv.append(f'- {t} `{n}` on *{p or "—"}* × {v}')
sim = collections.defaultdict(list)
for r in rows:
    key = (r['type'], r['parent'], re.sub(r'[^a-z0-9]', '', r['name'].lower()))
    sim[key].append(r['name'])
inv += ['', '**Near duplicates (same letters, different case or punctuation):**', '']
for (t, p, k), names in sorted(sim.items()):
    if len(set(names)) > 1:
        inv.append(f'- {t} on *{p or "—"}*: ' + ', '.join(f'`{x}`' for x in sorted(set(names))))
inv += ['', '**Families of numbered components:** `Stamp group 0–9` (and their `name`/`stamps` variants) on *Classifier custom classification log* and *Distribution Engine details*; '
        '`Order field/Order by 1–3 (deprecated)` and `Lookup match/unique field 2–3` on *Distributor*; `Log type` ×3 on *Distributor schedule log*.']

# needs further reverse engineering
inv += ['', '## 5. Components that need further investigation', '']
inv_rows = [r for r in rows if r['status'] in ('Investigating', 'Not Started')]
if inv_rows:
    inv += ['| # | Component | Parent | Type | Why |', '|---|---|---|---|---|']
    for r in inv_rows:
        inv.append(f"| {r['row']} | {esc(r['name'])} | {esc(r['parent']) or '—'} | {r['type']} | {esc(r['notes']) or 'No target designed yet.'} |")
else:
    inv.append('None. Every row is mapped.')

# equivalents
inv += ['', '## 6. Components that cannot be recreated one to one, and their equivalents', '',
        '| Reference component(s) | Type | Equivalent in the target | Why |', '|---|---|---|---|']
for o, (kind, tgt, note) in sorted(OBJECTS.items()):
    if kind == 'equiv':
        inv.append(f'| {o} | Custom Object | `{tgt}` | {esc(note)} |')
inv += ['| 66 Visualforce pages, 21 Visualforce components | Visualforce | Lightning web components (tabs, widget, record component) | Lightning Experience UI; see the matrix for the page-by-page mapping. |',
        '| 3 Aura bundles (Lightning Out wrappers) | Aura | The LWCs they wrapped | Not needed once the UI is LWC. |',
        '| 2 Workflow Rules | Workflow | Record-triggered flows that call the same email alerts | Salesforce has retired workflow rules for new automation. |',
        '| 2 Home Page Components, 1 Home Page Layout | Classic home | Lightning home page `DE_Home` with the widget | Classic-only metadata. |',
        '| 1,341 Apex classes | Apex | 70+ target classes by responsibility | Reference internals are not visible; behaviour is rebuilt from documentation. |']
inv += ['', '## 7. Not applicable and blocked', '',
        '| Group | Count | Reason |', '|---|---|---|']
na_groups = collections.Counter()
for r in rows:
    if r['status'] in ('Not Applicable', 'Blocked'):
        na_groups[(r['status'], r['area'])] += 1
for (s, a), c in sorted(na_groups.items(), key=lambda x: -x[1]):
    inv.append(f'| {s}: {a} | {c} | ' + esc(next((r['notes'] for r in rows if r['status'] == s and r['area'] == a and r['notes']), '')) + ' |')

# naming strategy
inv += ['', '## 8. Naming strategy and object name map', '',
        '- **Prefix.** Every target component uses the `DE_` prefix and no namespace (unmanaged). A namespace can be added when the project is packaged (2GP), and the `DE_` names still avoid clashes with standard metadata.',
        '- **Functional names.** Target API names say what a component does, for example `DE_Assignment_Log__c` for the reference "Distribution log". Labels follow the reference labels where the meaning is the same.',
        '- **No copied identifiers.** No reference IDs, namespaces or package-specific identifiers are copied.', '',
        '| Reference object (label) | Target | Kind | Reason |', '|---|---|---|---|']
for o, (kind, tgt, note) in sorted(OBJECTS.items()):
    inv.append(f'| {o} | {("`" + tgt + "`") if tgt else "—"} | {kind} | {esc(note)} |')
open(os.path.join(DOCS, 'metadata-component-inventory.md'), 'w').write('\n'.join(inv) + '\n')

# --- dependency map
dep = ['# Metadata Dependency Map', '',
       'The dependencies between target components that implement the reference inventory, in the order they are built. '
       'Generated from the repository (object relationships, Apex references, LWC imports, report and dashboard references).', '']
objdir = os.path.join(SRC, 'objects')
rels = []
for o in sorted(os.listdir(objdir)):
    fd = os.path.join(objdir, o, 'fields')
    if not os.path.isdir(fd):
        continue
    for f in sorted(os.listdir(fd)):
        x = open(os.path.join(fd, f)).read()
        m = re.search(r'<referenceTo>([^<]+)</referenceTo>', x)
        if m:
            kind = 'master-detail' if '<type>MasterDetail</type>' in x else 'lookup'
            rels.append((o, f.replace('.field-meta.xml', ''), m.group(1), kind))
dep += ['## 1. Objects → objects (relationship fields)', '', '```mermaid', 'graph LR']
for o, f, tgt, kind in rels:
    if tgt.startswith('DE_'):
        dep.append(f'  {o.replace("__c", "")} -->|{f.replace("__c", "")}{" MD" if kind == "master-detail" else ""}| {tgt.replace("__c", "")}')
dep += ['```', '', '| Child object | Field | Parent | Kind |', '|---|---|---|---|']
for o, f, tgt, kind in rels:
    dep.append(f'| `{o}` | `{f}` | `{tgt}` | {kind} |')

dep += ['', '## 2. Objects → fields, layouts, list views, compact layouts, validation rules', '', '| Object | Fields | Layouts | List views | Compact layouts | Validation rules |', '|---|---|---|---|---|---|']
for o in sorted(os.listdir(objdir)):
    def cnt(sub):
        d = os.path.join(objdir, o, sub)
        return len(os.listdir(d)) if os.path.isdir(d) else 0
    lay = len(glob.glob(os.path.join(SRC, 'layouts', o + '-*.layout-meta.xml')))
    dep.append(f'| `{o}` | {cnt("fields")} | {lay} | {cnt("listViews")} | {cnt("compactLayouts")} | {cnt("validationRules")} |')

classes = {os.path.basename(p)[:-4]: open(p).read() for p in glob.glob(os.path.join(SRC, 'classes', '*.cls'))}
objs = sorted(os.listdir(objdir))
dep += ['', '## 3. Apex → objects', '', '| Class | Objects referenced |', '|---|---|']
for c in sorted(classes):
    if c.endswith('Test'):
        continue
    refs = [o for o in objs if o.startswith('DE_') and o in classes[c]]
    if refs:
        dep.append(f'| `{c}` | ' + ', '.join(f'`{o}`' for o in refs) + ' |')
dep += ['', '## 4. Triggers → handlers', '', '| Trigger | Object | Handler |', '|---|---|---|']
for p in sorted(glob.glob(os.path.join(SRC, 'triggers', '*.trigger'))):
    x = open(p).read()
    m = re.search(r'trigger\s+(\w+)\s+on\s+(\w+)', x)
    h = re.findall(r'(DE_\w+)\.(\w+)\(', x)
    dep.append(f'| `{m.group(1)}` | `{m.group(2)}` | ' + ', '.join(f'`{a}.{b}`' for a, b in h) + ' |')
dep += ['', '## 5. LWC → Apex and child components', '', '| Component | Apex methods | Child components |', '|---|---|---|']
for d in sorted(glob.glob(os.path.join(SRC, 'lwc', '*'))):
    name = os.path.basename(d)
    js = ''.join(open(f).read() for f in glob.glob(os.path.join(d, '*.js')))
    html = ''.join(open(f).read() for f in glob.glob(os.path.join(d, '*.html')))
    ap = sorted(set(re.findall(r'@salesforce/apex/([\w.]+)', js)))
    ch = sorted(set(re.findall(r'<c-([a-z0-9-]+)', html)))
    dep.append(f'| `{name}` | ' + (', '.join(f'`{a}`' for a in ap) or '—') + ' | ' + (', '.join(f'`c-{x}`' for x in ch) or '—') + ' |')
dep += ['', '## 6. Flows → objects and actions', '', '| Flow | Object / trigger | Actions |', '|---|---|---|']
for p in sorted(glob.glob(os.path.join(SRC, 'flows', '*.flow-meta.xml'))):
    x = open(p).read()
    o = re.search(r'<object>([^<]+)</object>', x)
    acts = sorted(set(re.findall(r'<actionName>([^<]+)</actionName>', x)))
    dep.append(f'| `{os.path.basename(p)[:-14]}` | {o.group(1) if o else "—"} | ' + (', '.join(f'`{a}`' for a in acts) or '—') + ' |')
dep += ['', '## 7. Reports → report types → objects; dashboards → reports', '', '| Report | Report type |', '|---|---|']
for p in sorted(glob.glob(os.path.join(SRC, 'reports', '*', '*.report-meta.xml'))):
    x = open(p).read()
    rt = re.search(r'<reportType>([^<]+)</reportType>', x)
    dep.append(f'| `{os.path.basename(p)[:-16]}` | `{rt.group(1) if rt else "?"}` |')
dep += ['', '| Report type | Base object |', '|---|---|']
for p in sorted(glob.glob(os.path.join(SRC, 'reportTypes', '*.reportType-meta.xml'))):
    x = open(p).read()
    b = re.search(r'<baseObject>([^<]+)</baseObject>', x)
    dep.append(f'| `{os.path.basename(p)[:-20]}` | `{b.group(1)}` |')
dep += ['', '| Dashboard | Reports |', '|---|---|']
for p in sorted(glob.glob(os.path.join(SRC, 'dashboards', '*', '*.dashboard-meta.xml'))):
    x = open(p).read()
    dep.append(f'| `{os.path.basename(p)[:-19]}` | ' + ', '.join(f'`{a}`' for a in sorted(set(re.findall(r'<report>([^<]+)</report>', x)))) + ' |')
dep += ['', '## 8. Permission sets → objects, classes, tabs, custom permissions', '', '| Permission set | Objects | Fields | Apex classes | Tabs | Custom permissions |', '|---|---|---|---|---|---|']
for p in sorted(glob.glob(os.path.join(SRC, 'permissionsets', '*.permissionset-meta.xml'))):
    x = open(p).read()
    dep.append(f'| `{os.path.basename(p)[:-25]}` | {x.count("<objectPermissions>")} | {x.count("<fieldPermissions>")} | {x.count("<classAccesses>")} | {x.count("<tabSettings>")} | '
               + ', '.join(re.findall(r'<customPermissions>\s*<enabled>true</enabled>\s*<name>(\w+)</name>', x)) + ' |')
dep += ['', '## 9. Build order', '',
        '1. Custom settings (`DE_Settings__c`), custom permissions, platform event, platform cache partition.',
        '2. Parent objects: `DE_Holiday_Region__c`, `DE_Shift__c`, `DE_Team__c`, `DE_Persona__c`, `DE_Stamp_Group__c`, `DE_Territory__c`, `DE_Matching_Rule__c`, `DE_Conversion_Rule__c`.',
        '3. Child objects: members, managers, distributors, SLAs, caps, conditions, shift plans and blocks, stamps, holidays.',
        '4. Runtime and log objects: rotation state, record details, assignment logs and log actions, reject requests, history, classifier and sync logs, run logs.',
        '5. Fields on standard objects (Lead, Case, Opportunity, Contact, Account).',
        '6. Apex: utilities → repository/model → services → engine → controllers → API/flow actions → jobs; then triggers.',
        '7. LWC: utilities → building blocks → tabs and global components.',
        '8. Email templates → workflow email alerts → flows.',
        '9. Layouts, compact layouts, list views, tabs, flexipages, app.',
        '10. Report types → reports → dashboards; permission sets last.']
open(os.path.join(DOCS, 'metadata-dependency-map.md'), 'w').write('\n'.join(dep) + '\n')

# --- summary
def count_target_components():
    n = collections.Counter()
    n['Custom objects'] = len([o for o in os.listdir(objdir) if o.endswith('__c') or o.endswith('__e')])
    n['Custom fields'] = sum(len(os.listdir(os.path.join(objdir, o, 'fields'))) for o in os.listdir(objdir) if os.path.isdir(os.path.join(objdir, o, 'fields')))
    n['Apex classes'] = len(classes)
    n['Apex test classes'] = len([c for c in classes if c.endswith('Test') or c == 'DE_TestFactory'])
    n['Apex triggers'] = len(glob.glob(os.path.join(SRC, 'triggers', '*.trigger')))
    n['LWC bundles'] = len(glob.glob(os.path.join(SRC, 'lwc', '*')))
    n['Flows'] = len(glob.glob(os.path.join(SRC, 'flows', '*.flow-meta.xml')))
    n['Page layouts'] = len(glob.glob(os.path.join(SRC, 'layouts', '*.layout-meta.xml')))
    n['Tabs'] = len(glob.glob(os.path.join(SRC, 'tabs', '*.tab-meta.xml')))
    n['Permission sets'] = len(glob.glob(os.path.join(SRC, 'permissionsets', '*.permissionset-meta.xml')))
    n['Custom permissions'] = len(glob.glob(os.path.join(SRC, 'customPermissions', '*')))
    n['Reports'] = len(glob.glob(os.path.join(SRC, 'reports', '*', '*.report-meta.xml')))
    n['Report types'] = len(glob.glob(os.path.join(SRC, 'reportTypes', '*')))
    n['Dashboards'] = len(glob.glob(os.path.join(SRC, 'dashboards', '*', '*.dashboard-meta.xml')))
    n['Email templates'] = len(glob.glob(os.path.join(SRC, 'email', '*', '*.email-meta.xml')))
    n['Validation rules'] = len(glob.glob(os.path.join(objdir, '*', 'validationRules', '*')))
    n['FlexiPages'] = len(glob.glob(os.path.join(SRC, 'flexipages', '*')))
    n['Other (app, notification type, cache, list views, compact layouts, workflow)'] = (
        len(glob.glob(os.path.join(SRC, 'applications', '*'))) + len(glob.glob(os.path.join(SRC, 'notificationtypes', '*')))
        + len(glob.glob(os.path.join(SRC, 'cachePartitions', '*'))) + len(glob.glob(os.path.join(objdir, '*', 'listViews', '*')))
        + len(glob.glob(os.path.join(objdir, '*', 'compactLayouts', '*'))) + len(glob.glob(os.path.join(SRC, 'workflows', '*'))))
    return n


tc = count_target_components()
summ = ['# Metadata Replication Summary', '',
        'A comparison of every row of the reference inventory CSV against the metadata in this repository. Generated by `scripts/metadata/gen_matrix.py`. '
        'Row-level detail is in `metadata-replication-matrix.md`.', '',
        '> **Validation limits.** No Salesforce org was available. Nothing has been deployed and no Apex test has run. "Implemented" means the target metadata or code exists and passes the offline checks listed in `progress-log.md`.', '',
        '## Totals', '', '| Measure | Count |', '|---|---|',
        f'| Reference components (CSV rows) | {len(rows)} |',
        f'| Target components in this repository | {sum(tc.values())} |',
        f'| Implemented: target exists (fully or by equivalent design) | {status_counts["Implemented"]} |',
        f'| Partially implemented: some targets exist | {status_counts["Implementing"]} |',
        f'| Identified: target designed, not built yet | {status_counts["Identified"]} |',
        f'| Investigating | {status_counts["Investigating"]} |',
        f'| Not started (no equivalent yet) | {status_counts["Not Started"]} |',
        f'| Blocked | {status_counts["Blocked"]} |',
        f'| Not applicable | {status_counts["Not Applicable"]} |', '',
        '## Target components', '', '| Type | Count |', '|---|---|']
for k, v in tc.items():
    summ.append(f'| {k} | {v} |')
summ += ['', '## Status by reference type', '', '| Type | Total | ' + ' | '.join(STATUSES) + ' |', '|---|---|' + '---|' * len(STATUSES)]
for t, c in type_counts.most_common():
    summ.append(f'| {t} | {c} | ' + ' | '.join(str(by_type_status[t][s] or '') for s in STATUSES) + ' |')
summ += ['', '## Per-row verification questions', '',
         'For each CSV row, the matrix answers these questions:',
         '- **Does an equivalent component exist?** See the Target and Status columns.',
         '- **Does it have the correct parent object?** Fields and layouts are mapped to the target of their parent object (Dependency column).',
         '- **Does it have the correct metadata type?** Same type where the platform still supports it. Visualforce, Aura and Workflow Rules become LWC and Flow, as noted.',
         '- **Are its dependencies implemented?** A row is `Implemented` only when all its targets exist; targets that do not exist yet are marked *(planned)*.',
         '- **Is its functionality implemented?** Feature behaviour is tracked in `parity-matrix.md` (F01–F64).',
         '- **Is it tested?** Tests are written but have not been executed. See `parity-matrix.md`.', '',
         '## Remaining work', '']
rem = collections.Counter()
for r in rows:
    if r['status'] in ('Identified', 'Implementing', 'Investigating', 'Not Started'):
        rem[(r['status'], r['area'])] += 1
if rem:
    summ += ['| Status | Area | Rows |', '|---|---|---|']
    for (s, a), c in sorted(rem.items(), key=lambda x: (x[0][0], -x[1])):
        summ.append(f'| {s} | {a} | {c} |')
else:
    summ.append('No rows are left in Identified, Implementing, Investigating or Not Started.')
summ += ['', 'Beyond the inventory: run the Apex tests in a scratch org, verify reports and dashboards render, and review every `Blocked` item if a Slack app becomes available.']
open(os.path.join(DOCS, 'metadata-replication-summary.md'), 'w').write('\n'.join(summ) + '\n')

print('rows', len(rows), dict(status_counts))
unmapped = [r for r in rows if r['status'] in ('Not Started', 'Investigating')]
print('unmapped', len(unmapped))
for r in unmapped[:80]:
    print('  ', r['type'], '|', r['parent'], '|', r['name'], '|', r['notes'])
