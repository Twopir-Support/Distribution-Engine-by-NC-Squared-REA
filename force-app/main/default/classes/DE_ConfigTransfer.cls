/**
 * Exports and imports Distribution Engine configuration as JSON so it can move between orgs.
 * Ids are made portable: users by Username ("user:..."), queues by DeveloperName ("queue:...") and
 * shifts by Name ("shift:..."). Imported teams are inactive and imported territories are Draft.
 */
public without sharing class DE_ConfigTransfer {
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'id',
        'ownerid',
        'createddate',
        'createdbyid',
        'lastmodifieddate',
        'lastmodifiedbyid',
        'systemmodstamp',
        'isdeleted',
        'lastvieweddate',
        'lastreferenceddate',
        'lastactivitydate',
        'rotation_sequence__c',
        'total_assignments__c',
        'last_assigned_at__c',
        'unique_key__c'
    };
    private static final Set<String> PARENT_FIELDS = new Set<String>{
        'team__c',
        'distributor__c',
        'sla__c',
        'territory__c',
        'stamp__c',
        'stamp_group__c',
        'conversion_rule__c',
        'matching_rule__c',
        'cap__c',
        'object_sync__c'
    };

    // ------------------------------------------------------------------ export

    private static Map<Id, String> refs = new Map<Id, String>();

    public static String exportJson() {
        List<DE_Team__c> teams = Database.query(selectAll('DE_Team__c') + ' ORDER BY Execution_Order__c, Name');
        List<DE_Team_Member__c> members = Database.query(selectAll('DE_Team_Member__c'));
        List<DE_Distributor__c> dists = Database.query(selectAll('DE_Distributor__c') + ' ORDER BY Order__c');
        List<DE_Condition__c> conds = Database.query(selectAll('DE_Condition__c') + ' ORDER BY Sequence__c');
        List<DE_Cap__c> caps = Database.query(selectAll('DE_Cap__c'));
        List<DE_SLA__c> slas = Database.query(selectAll('DE_SLA__c') + ' ORDER BY Checkpoint__c');
        List<DE_Shift__c> shifts = Database.query(selectAll('DE_Shift__c'));
        List<DE_Holiday__c> holidays = Database.query(selectAll('DE_Holiday__c'));
        List<DE_Territory__c> territories = Database.query(selectAll('DE_Territory__c') + ' ORDER BY Priority__c');
        List<DE_Stamp_Group__c> groups = Database.query(selectAll('DE_Stamp_Group__c'));
        List<DE_Stamp__c> stamps = Database.query(selectAll('DE_Stamp__c') + ' ORDER BY Order__c');
        List<DE_Matching_Rule__c> matching = Database.query(selectAll('DE_Matching_Rule__c'));
        List<DE_Conversion_Rule__c> conversion = Database.query(selectAll('DE_Conversion_Rule__c'));
        List<DE_Object_Sync__c> syncs = Database.query(selectAll('DE_Object_Sync__c'));

        Set<Id> ids = new Set<Id>();
        List<List<SObject>> all = new List<List<SObject>>{ teams, members, dists, conversion };
        for (List<SObject> rows : all) {
            for (SObject r : rows) {
                for (Object v : r.getPopulatedFieldsAsMap().values()) {
                    if (v instanceof String || v instanceof Id) {
                        ids.addAll(DE_Ids.parseList(String.valueOf(v)));
                    }
                }
            }
        }
        for (User u : [SELECT Id, Username FROM User WHERE Id IN :ids]) {
            refs.put(u.Id, 'user:' + u.Username);
        }
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Id IN :ids AND Type = 'Queue']) {
            refs.put(g.Id, 'queue:' + g.DeveloperName);
        }
        for (DE_Shift__c s : shifts) {
            refs.put(s.Id, 'shift:' + s.Name);
        }

        Map<Id, List<Map<String, Object>>> condsByParent = new Map<Id, List<Map<String, Object>>>();
        for (DE_Condition__c c : conds) {
            Id parent = c.Cap__c != null
                ? c.Cap__c
                : c.SLA__c != null
                      ? c.SLA__c
                      : c.Distributor__c != null
                            ? c.Distributor__c
                            : c.Territory__c != null
                                  ? c.Territory__c
                                  : c.Stamp__c != null
                                        ? c.Stamp__c
                                        : c.Conversion_Rule__c != null
                                              ? c.Conversion_Rule__c
                                              : c.Matching_Rule__c != null ? c.Matching_Rule__c : c.Object_Sync__c != null ? c.Object_Sync__c : c.Team__c;
            add(condsByParent, parent, portable(c));
        }
        Map<Id, List<Map<String, Object>>> capsByParent = new Map<Id, List<Map<String, Object>>>();
        for (DE_Cap__c c : caps) {
            Map<String, Object> m = portable(c);
            m.put('conditions', nvl(condsByParent.get(c.Id)));
            add(capsByParent, c.Team__c != null ? c.Team__c : c.Distributor__c, m);
        }
        Map<Id, List<Map<String, Object>>> membersByTeam = new Map<Id, List<Map<String, Object>>>();
        for (DE_Team_Member__c m : members) {
            add(membersByTeam, m.Team__c, portable(m));
        }
        Map<Id, List<Map<String, Object>>> distsByTeam = new Map<Id, List<Map<String, Object>>>();
        for (DE_Distributor__c d : dists) {
            Map<String, Object> m = portable(d);
            m.put('conditions', nvl(condsByParent.get(d.Id)));
            m.put('caps', nvl(capsByParent.get(d.Id)));
            add(distsByTeam, d.Team__c, m);
        }
        Map<Id, List<Map<String, Object>>> slasByTeam = new Map<Id, List<Map<String, Object>>>();
        for (DE_SLA__c s : slas) {
            Map<String, Object> m = portable(s);
            m.put('conditions', nvl(condsByParent.get(s.Id)));
            add(slasByTeam, s.Team__c, m);
        }
        List<Map<String, Object>> teamOut = new List<Map<String, Object>>();
        for (DE_Team__c t : teams) {
            Map<String, Object> m = portable(t);
            m.put('conditions', nvl(condsByParent.get(t.Id)));
            m.put('members', nvl(membersByTeam.get(t.Id)));
            m.put('distributors', nvl(distsByTeam.get(t.Id)));
            m.put('caps', nvl(capsByParent.get(t.Id)));
            m.put('slas', nvl(slasByTeam.get(t.Id)));
            teamOut.add(m);
        }
        Map<Id, List<Map<String, Object>>> stampsByGroup = new Map<Id, List<Map<String, Object>>>();
        for (DE_Stamp__c s : stamps) {
            Map<String, Object> m = portable(s);
            m.put('conditions', nvl(condsByParent.get(s.Id)));
            add(stampsByGroup, s.Stamp_Group__c, m);
        }
        List<Map<String, Object>> groupOut = new List<Map<String, Object>>();
        for (DE_Stamp_Group__c g : groups) {
            Map<String, Object> m = portable(g);
            m.put('stamps', nvl(stampsByGroup.get(g.Id)));
            groupOut.add(m);
        }
        Map<String, Object> root = new Map<String, Object>{
            'format' => 'distribution-engine-by-nc-squared',
            'version' => 1,
            'exportedAt' => System.now(),
            'shifts' => portableList(shifts, null),
            'holidays' => portableList(holidays, null),
            'territories' => portableList(territories, condsByParent),
            'stampGroups' => groupOut,
            'matchingRules' => portableList(matching, condsByParent),
            'conversionRules' => portableList(conversion, condsByParent),
            'objectSyncs' => portableList(syncs, condsByParent),
            'teams' => teamOut
        };
        return JSON.serializePretty(root, true);
    }

    private static String selectAll(String objectName) {
        List<String> fields = new List<String>();
        for (Schema.SObjectField f : DE_Schema.fields(objectName).values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.getName() == 'Id' || !SYSTEM_FIELDS.contains(d.getName().toLowerCase())) {
                fields.add(d.getName());
            }
        }
        return 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectName;
    }

    private static void add(Map<Id, List<Map<String, Object>>> m, Id key, Map<String, Object> value) {
        if (!m.containsKey(key)) {
            m.put(key, new List<Map<String, Object>>());
        }
        m.get(key).add(value);
    }

    private static List<Map<String, Object>> nvl(List<Map<String, Object>> v) {
        return v == null ? new List<Map<String, Object>>() : v;
    }

    private static List<Map<String, Object>> portableList(List<SObject> rows, Map<Id, List<Map<String, Object>>> condsByParent) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (SObject r : rows) {
            Map<String, Object> m = portable(r);
            if (condsByParent != null) {
                m.put('conditions', nvl(condsByParent.get(r.Id)));
            }
            out.add(m);
        }
        return out;
    }

    private static Map<String, Object> portable(SObject r) {
        Map<String, Object> out = new Map<String, Object>();
        Map<String, Object> fields = r.getPopulatedFieldsAsMap();
        for (String f : fields.keySet()) {
            String lower = f.toLowerCase();
            Object v = fields.get(f);
            if (SYSTEM_FIELDS.contains(lower) || PARENT_FIELDS.contains(lower) || v instanceof SObject || v instanceof List<SObject>) {
                continue;
            }
            if (v instanceof Id || v instanceof String) {
                String s = String.valueOf(v);
                List<String> parts = new List<String>();
                Boolean allIds = true;
                for (String p : s.split('[,;]')) {
                    Id i = DE_Ids.toId(p.trim());
                    if (i == null || !refs.containsKey(i)) {
                        allIds = false;
                        break;
                    }
                    parts.add(refs.get(i));
                }
                v = allIds && !parts.isEmpty() ? (Object) String.join(parts, ',') : v;
            }
            out.put(f, v);
        }
        return out;
    }

    // ------------------------------------------------------------------ import

    private static Map<String, Id> resolve = new Map<String, Id>();
    private static Integer unresolved = 0;

    public static Map<String, Integer> importJson(String json) {
        Map<String, Object> root;
        try {
            root = (Map<String, Object>) System.JSON.deserializeUntyped(json);
        } catch (Exception e) {
            throw new DE_Permissions.AccessException('The file is not valid Distribution Engine JSON.');
        }
        if (root.get('format') != 'distribution-engine-by-nc-squared') {
            throw new DE_Permissions.AccessException('The file was not exported from Distribution Engine by NC Squared.');
        }
        Map<String, Integer> counts = new Map<String, Integer>();
        for (User u : [SELECT Id, Username FROM User WHERE IsActive = TRUE LIMIT 20000]) {
            resolve.put('user:' + u.Username.toLowerCase(), u.Id);
        }
        for (Group g : [SELECT Id, DeveloperName FROM Group WHERE Type = 'Queue' LIMIT 20000]) {
            resolve.put('queue:' + g.DeveloperName.toLowerCase(), g.Id);
        }
        for (DE_Shift__c s : [SELECT Id, Name FROM DE_Shift__c]) {
            resolve.put('shift:' + s.Name.toLowerCase(), s.Id);
        }
        Integer n = 0;
        for (Object o : items(root, 'shifts')) {
            Map<String, Object> m = (Map<String, Object>) o;
            String key = 'shift:' + String.valueOf(m.get('Name')).toLowerCase();
            if (!resolve.containsKey(key)) {
                SObject s = build('DE_Shift__c', m, null);
                insert s;
                resolve.put(key, s.Id);
                n++;
            }
        }
        counts.put('shifts', n);
        counts.put('holidays', insertAll('DE_Holiday__c', items(root, 'holidays'), null, null));
        counts.put(
            'territories',
            insertWithConditions('DE_Territory__c', items(root, 'territories'), 'Territory__c', new Map<String, Object>{ 'Status__c' => 'Draft' })
        );
        counts.put('matchingRules', insertWithConditions('DE_Matching_Rule__c', items(root, 'matchingRules'), 'Matching_Rule__c', null));
        counts.put('conversionRules', insertWithConditions('DE_Conversion_Rule__c', items(root, 'conversionRules'), 'Conversion_Rule__c', null));
        counts.put(
            'objectSyncs',
            insertWithConditions('DE_Object_Sync__c', items(root, 'objectSyncs'), 'Object_Sync__c', new Map<String, Object>{ 'Active__c' => false })
        );
        n = 0;
        for (Object o : items(root, 'stampGroups')) {
            Map<String, Object> m = (Map<String, Object>) o;
            SObject g = build('DE_Stamp_Group__c', m, null);
            insert g;
            for (Object so : items(m, 'stamps')) {
                Map<String, Object> sm = (Map<String, Object>) so;
                SObject s = build('DE_Stamp__c', sm, new Map<String, Object>{ 'Stamp_Group__c' => g.Id });
                insert s;
                insertConditions(items(sm, 'conditions'), 'Stamp__c', s.Id);
            }
            n++;
        }
        counts.put('stampGroups', n);
        Set<String> existingNames = new Set<String>();
        for (DE_Team__c t : [SELECT Name FROM DE_Team__c]) {
            existingNames.add(t.Name.toLowerCase());
        }
        n = 0;
        for (Object o : items(root, 'teams')) {
            Map<String, Object> m = (Map<String, Object>) o;
            String name = String.valueOf(m.get('Name'));
            if (existingNames.contains(name.toLowerCase())) {
                name = (name + ' (imported)').left(80);
            }
            SObject t = build('DE_Team__c', m, new Map<String, Object>{ 'Name' => name, 'Active__c' => false });
            insert t;
            insertConditions(items(m, 'conditions'), 'Team__c', t.Id);
            List<SObject> mems = new List<SObject>();
            for (Object mo : items(m, 'members')) {
                SObject mem = build('DE_Team_Member__c', (Map<String, Object>) mo, new Map<String, Object>{ 'Team__c' => t.Id });
                Id who = mem.get('User__c') != null ? (Id) mem.get('User__c') : DE_Ids.toId((String) mem.get('Queue_Id__c'));
                if (who == null) {
                    unresolved++;
                    continue;
                }
                mem.put('Unique_Key__c', t.Id + '|' + who);
                mems.add(mem);
            }
            insert mems;
            insertCaps(items(m, 'caps'), 'Team__c', t.Id);
            for (Object so : items(m, 'slas')) {
                Map<String, Object> sm = (Map<String, Object>) so;
                SObject s = build('DE_SLA__c', sm, new Map<String, Object>{ 'Team__c' => t.Id });
                insert s;
                insertConditions(items(sm, 'conditions'), 'SLA__c', s.Id);
            }
            for (Object dobj : items(m, 'distributors')) {
                Map<String, Object> dm = (Map<String, Object>) dobj;
                SObject d = build('DE_Distributor__c', dm, new Map<String, Object>{ 'Team__c' => t.Id });
                insert d;
                insertConditions(items(dm, 'conditions'), 'Distributor__c', d.Id);
                insertCaps(items(dm, 'caps'), 'Distributor__c', d.Id);
            }
            n++;
        }
        counts.put('teams', n);
        counts.put('unresolvedReferences', unresolved);
        return counts;
    }

    private static List<Object> items(Map<String, Object> m, String key) {
        Object v = m.get(key);
        return v instanceof List<Object> ? (List<Object>) v : new List<Object>();
    }

    private static Integer insertAll(String objectName, List<Object> rows, String unused, Map<String, Object> overrides) {
        List<SObject> out = new List<SObject>();
        for (Object o : rows) {
            out.add(build(objectName, (Map<String, Object>) o, overrides));
        }
        insert out;
        return out.size();
    }

    private static Integer insertWithConditions(String objectName, List<Object> rows, String conditionParentField, Map<String, Object> overrides) {
        Integer n = 0;
        for (Object o : rows) {
            Map<String, Object> m = (Map<String, Object>) o;
            SObject r = build(objectName, m, overrides);
            insert r;
            insertConditions(items(m, 'conditions'), conditionParentField, r.Id);
            n++;
        }
        return n;
    }

    private static void insertConditions(List<Object> rows, String parentField, Id parentId) {
        List<SObject> out = new List<SObject>();
        for (Object o : rows) {
            out.add(build('DE_Condition__c', (Map<String, Object>) o, new Map<String, Object>{ parentField => parentId }));
        }
        insert out;
    }

    private static void insertCaps(List<Object> rows, String parentField, Id parentId) {
        for (Object o : rows) {
            Map<String, Object> m = (Map<String, Object>) o;
            SObject c = build('DE_Cap__c', m, new Map<String, Object>{ parentField => parentId });
            insert c;
            insertConditions(items(m, 'conditions'), 'Cap__c', c.Id);
        }
    }

    private static SObject build(String objectName, Map<String, Object> values, Map<String, Object> overrides) {
        SObject s = DE_Schema.sobjectType(objectName).newSObject();
        for (String f : values.keySet()) {
            Object v = values.get(f);
            if (v instanceof List<Object> || v instanceof Map<String, Object> || f == 'attributes') {
                continue;
            }
            Schema.DescribeFieldResult fd = DE_Schema.field(objectName, f);
            if (fd == null || !fd.isCreateable() || SYSTEM_FIELDS.contains(f.toLowerCase()) || PARENT_FIELDS.contains(f.toLowerCase())) {
                continue;
            }
            s.put(fd.getName(), convert(fd, v));
        }
        if (overrides != null) {
            for (String f : overrides.keySet()) {
                s.put(f, overrides.get(f));
            }
        }
        return s;
    }

    private static Object convert(Schema.DescribeFieldResult fd, Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof String) {
            String s = (String) v;
            if (s.startsWith('user:') || s.startsWith('queue:') || s.startsWith('shift:')) {
                List<String> ids = new List<String>();
                for (String part : s.split(',')) {
                    Id i = resolve.get(part.trim().toLowerCase());
                    if (i == null) {
                        unresolved++;
                    } else {
                        ids.add(String.valueOf(i));
                    }
                }
                if (ids.isEmpty()) {
                    return null;
                }
                return fd.getType() == Schema.DisplayType.REFERENCE ? (Object) Id.valueOf(ids[0]) : (Object) String.join(ids, ',');
            }
            return DE_Schema.coerce(fd, s);
        }
        if (v instanceof Boolean) {
            return v;
        }
        if (v instanceof Decimal || v instanceof Double || v instanceof Integer || v instanceof Long) {
            return Decimal.valueOf(String.valueOf(v));
        }
        return DE_Schema.coerce(fd, String.valueOf(v));
    }
}
