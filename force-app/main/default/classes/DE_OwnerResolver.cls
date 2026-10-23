/**
 * Owner-based methods: Lookup Owner, Related Owner and Dynamic Owner.
 * Each returns the team member a record should go to, or nothing so the record overflows.
 */
public without sharing class DE_OwnerResolver {
    private static final Map<String, String> DE_RELATED = new Map<String, String>{
        'de.matchedaccount' => 'Matched_Account__c',
        'de.matchedcontact' => 'Matched_Contact__c',
        'de.matchedlead' => 'Matched_Lead__c'
    };

    /**
     * Lookup Owner: finds records on another object whose target field equals the record's field
     * (case-insensitive), filtered by the Lookup Where conditions. Prefers matches owned by team members,
     * then the tie-breaker (default newest LastModifiedDate). Only team members can receive the record.
     */
    public static Map<Id, Id> lookupOwners(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, List<SObject> records, Set<Id> memberIds, List<String> warnings) {
        Map<Id, Id> out = new Map<Id, Id>();
        DE_Distributor__c d = dc.dist;
        String target = DE_Schema.objectName(d.Lookup_Object__c);
        if (!DE_Schema.objectExists(target) || String.isBlank(d.Lookup_Record_Field__c) || String.isBlank(d.Lookup_Target_Field__c)) {
            warnings.add('Lookup Owner distributor ' + d.Name + ' is not fully configured.');
            return out;
        }
        String targetField = DE_Schema.canonicalPath(target, d.Lookup_Target_Field__c);
        String assignPath = DE_Schema.canonicalPath(target, String.isBlank(d.Lookup_Assign_Field__c) ? 'OwnerId' : d.Lookup_Assign_Field__c);
        String tieField = DE_Schema.canonicalPath(target, String.isBlank(d.Lookup_Tie_Breaker_Field__c) ? 'LastModifiedDate' : d.Lookup_Tie_Breaker_Field__c);
        if (targetField == null || assignPath == null || tieField == null) {
            warnings.add('Lookup Owner distributor ' + d.Name + ' references a field that does not exist on ' + target + '.');
            return out;
        }
        Map<String, List<Id>> recordsByValue = new Map<String, List<Id>>();
        Set<String> values = new Set<String>();
        for (SObject r : records) {
            Object v = DE_Conditions.readPath(r, d.Lookup_Record_Field__c);
            if (v == null || String.isBlank(String.valueOf(v))) {
                continue;
            }
            String key = String.valueOf(v).trim().toLowerCase();
            values.add(String.valueOf(v).trim());
            if (!recordsByValue.containsKey(key)) {
                recordsByValue.put(key, new List<Id>());
            }
            recordsByValue.get(key).add(r.Id);
        }
        if (values.isEmpty()) {
            return out;
        }
        Set<String> paths = new Set<String>{ 'Id', targetField, assignPath, tieField };
        paths.addAll(DE_Conditions.recordPaths(dc.lookupWhere));
        Set<Id> ownRecordIds = new Map<Id, SObject>(records).keySet();
        String soql =
            'SELECT ' +
            DE_RecordQuery.selectList(target, paths, warnings) +
            ' FROM ' +
            target +
            ' WHERE ' +
            targetField +
            ' IN :vals AND Id NOT IN :own';
        if (target == 'Lead') {
            soql += ' AND IsConverted = false';
        }
        soql += ' LIMIT 2000';
        List<SObject> candidates = Database.queryWithBinds(soql, new Map<String, Object>{ 'vals' => values, 'own' => ownRecordIds }, AccessLevel.SYSTEM_MODE);
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        Boolean newestFirst = d.Lookup_Tie_Breaker_Direction__c != 'Oldest or Lowest';
        Map<String, SObject> best = new Map<String, SObject>();
        for (SObject c : candidates) {
            if (!DE_Conditions.matches(c, dc.lookupWhere, d.Lookup_Where_Logic__c, ctx, null)) {
                continue;
            }
            Object owner = DE_Conditions.readPath(c, assignPath);
            if (!(owner instanceof Id) || !memberIds.contains((Id) owner)) {
                continue;
            }
            String key = String.valueOf(c.get(targetField)).trim().toLowerCase();
            SObject current = best.get(key);
            if (current == null || better(c, current, tieField, newestFirst)) {
                best.put(key, c);
            }
        }
        for (String key : best.keySet()) {
            Id owner = (Id) DE_Conditions.readPath(best.get(key), assignPath);
            for (Id recordId : recordsByValue.get(key)) {
                out.put(recordId, owner);
            }
        }
        return out;
    }

    private static Boolean better(SObject a, SObject b, String tieField, Boolean newestFirst) {
        Integer c = DE_Conditions.compareValues(DE_Conditions.readPath(a, tieField), String.valueOf(DE_Conditions.readPath(b, tieField)), System.now());
        if (DE_Conditions.readPath(a, tieField) instanceof Datetime && DE_Conditions.readPath(b, tieField) instanceof Datetime) {
            Long diff = ((Datetime) DE_Conditions.readPath(a, tieField)).getTime() - ((Datetime) DE_Conditions.readPath(b, tieField)).getTime();
            c = diff > 0 ? 1 : (diff < 0 ? -1 : 0);
        }
        if (c == null) {
            return false;
        }
        return newestFirst ? c > 0 : c < 0;
    }

    /**
     * Related Owner: the owner of a related record (DE.MatchedAccount / DE.MatchedContact / DE.MatchedLead,
     * or a lookup field on the record) if they are a team member; otherwise the secondary related record.
     */
    public static Map<Id, Id> relatedOwners(DE_Model.DistributorConfig dc, List<SObject> records, Map<Id, DE_Record_Detail__c> details, Set<Id> memberIds) {
        Map<Id, Id> primary = relatedIds(dc.dist.Related_Field__c, records, details);
        Map<Id, Id> secondary = relatedIds(dc.dist.Related_Secondary_Field__c, records, details);
        Set<Id> all = new Set<Id>(primary.values());
        all.addAll(secondary.values());
        Map<Id, Id> owners = ownersOf(all);
        Map<Id, Id> out = new Map<Id, Id>();
        for (SObject r : records) {
            Id o1 = owners.get(primary.get(r.Id));
            if (o1 != null && memberIds.contains(o1)) {
                out.put(r.Id, o1);
                continue;
            }
            Id o2 = owners.get(secondary.get(r.Id));
            if (o2 != null && memberIds.contains(o2)) {
                out.put(r.Id, o2);
            }
        }
        return out;
    }

    private static Map<Id, Id> relatedIds(String path, List<SObject> records, Map<Id, DE_Record_Detail__c> details) {
        Map<Id, Id> out = new Map<Id, Id>();
        if (String.isBlank(path)) {
            return out;
        }
        String detailField = DE_RELATED.get(path.trim().toLowerCase());
        for (SObject r : records) {
            Object v;
            if (detailField != null) {
                DE_Record_Detail__c d = details.get(r.Id);
                v = d == null ? null : d.get(detailField);
            } else {
                try {
                    v = DE_Conditions.readPath(r, path);
                } catch (Exception e) {
                    v = null;
                }
            }
            Id i = v == null ? null : DE_Ids.toId(String.valueOf(v));
            if (i != null) {
                out.put(r.Id, i);
            }
        }
        return out;
    }

    /** OwnerId of each record, grouped by object type (one query per type). */
    public static Map<Id, Id> ownersOf(Set<Id> ids) {
        Map<Id, Id> out = new Map<Id, Id>();
        Map<String, Set<Id>> byType = new Map<String, Set<Id>>();
        for (Id i : ids) {
            if (i == null) {
                continue;
            }
            String t = i.getSobjectType().getDescribe().getName();
            if (!byType.containsKey(t)) {
                byType.put(t, new Set<Id>());
            }
            byType.get(t).add(i);
        }
        for (String t : byType.keySet()) {
            if (!DE_Schema.hasField(t, 'OwnerId')) {
                continue;
            }
            Set<Id> typeIds = byType.get(t);
            for (SObject s : Database.queryWithBinds('SELECT Id, OwnerId FROM ' + t + ' WHERE Id IN :ids', new Map<String, Object>{ 'ids' => typeIds }, AccessLevel.SYSTEM_MODE)) {
                out.put(s.Id, (Id) s.get('OwnerId'));
            }
        }
        return out;
    }

    /** Dynamic Owner: the active user whose Id is in the configured field. */
    public static Map<Id, Id> dynamicOwners(DE_Model.DistributorConfig dc, List<SObject> records) {
        Map<Id, Id> candidates = new Map<Id, Id>();
        for (SObject r : records) {
            Object v;
            try {
                v = DE_Conditions.readPath(r, dc.dist.Dynamic_Owner_Field__c);
            } catch (Exception e) {
                v = null;
            }
            Id i = v == null ? null : DE_Ids.toId(String.valueOf(v));
            if (i != null && i.getSobjectType() == User.SObjectType) {
                candidates.put(r.Id, i);
            }
        }
        Set<Id> userIds = new Set<Id>(candidates.values());
        Map<Id, User> active = new Map<Id, User>([SELECT Id FROM User WHERE Id IN :userIds AND IsActive = TRUE]);
        Map<Id, Id> out = new Map<Id, Id>();
        for (Id recordId : candidates.keySet()) {
            if (active.containsKey(candidates.get(recordId))) {
                out.put(recordId, candidates.get(recordId));
            }
        }
        return out;
    }
}
