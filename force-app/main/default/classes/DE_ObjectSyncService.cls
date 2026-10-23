/**
 * Object Sync: after a parent record is assigned to a user, related child records (via a lookup)
 * that match the action's filters take the same owner.
 */
public without sharing class DE_ObjectSyncService {
    public static Integer sync(DE_Model.TeamConfig cfg, List<DE_Model.Decision> decisions) {
        Map<Id, Id> ownerByParent = new Map<Id, Id>();
        for (DE_Model.Decision d : decisions) {
            if (d.status == 'Assigned' && d.assigneeId != null && d.assigneeId.getSobjectType() == User.SObjectType) {
                ownerByParent.put(d.recordId, d.assigneeId);
            }
        }
        if (ownerByParent.isEmpty()) {
            return 0;
        }
        String parentObject = cfg.objectName;
        List<DE_Object_Sync__c> actions = [
            SELECT
                Id,
                Name,
                Parent_Object__c,
                Child_Object__c,
                Lookup_Field__c,
                Filter_Logic__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Object_Sync__c
            WHERE Active__c = TRUE AND Parent_Object__c = :parentObject
        ];
        Integer changed = 0;
        for (DE_Object_Sync__c a : actions) {
            changed += runAction(a, ownerByParent);
        }
        return changed;
    }

    private static Integer runAction(DE_Object_Sync__c a, Map<Id, Id> ownerByParent) {
        String child = DE_Schema.objectName(a.Child_Object__c);
        String lookup = DE_Schema.canonicalPath(child, a.Lookup_Field__c);
        if (lookup == null || !DE_Schema.hasField(child, 'OwnerId')) {
            return 0;
        }
        List<DE_Condition__c> conds = a.Conditions__r;
        Set<String> paths = DE_Conditions.recordPaths(conds);
        paths.add('Id');
        paths.add('OwnerId');
        paths.add(lookup);
        Set<Id> parentIds = ownerByParent.keySet();
        String soql = 'SELECT ' + DE_RecordQuery.selectList(child, paths, null) + ' FROM ' + child + ' WHERE ' + lookup + ' IN :parents LIMIT 5000';
        List<SObject> rows = Database.queryWithBinds(soql, new Map<String, Object>{ 'parents' => parentIds }, AccessLevel.SYSTEM_MODE);
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        List<SObject> updates = new List<SObject>();
        Schema.SObjectType t = DE_Schema.sobjectType(child);
        for (SObject r : rows) {
            Id newOwner = ownerByParent.get((Id) r.get(lookup));
            if (newOwner == null || r.get('OwnerId') == newOwner) {
                continue;
            }
            if (!DE_Conditions.matches(r, conds, a.Filter_Logic__c, ctx, null)) {
                continue;
            }
            SObject u = t.newSObject(r.Id);
            u.put('OwnerId', newOwner);
            updates.add(u);
        }
        if (updates.isEmpty()) {
            return 0;
        }
        Boolean previous = DE_TriggerHandler.bypass;
        DE_TriggerHandler.bypass = true;
        Integer ok = 0;
        try {
            for (Database.SaveResult s : Database.update(updates, false, AccessLevel.SYSTEM_MODE)) {
                if (s.isSuccess()) {
                    ok++;
                }
            }
        } finally {
            DE_TriggerHandler.bypass = previous;
        }
        DE_RunLogger.log(
            'Object Sync',
            ok == updates.size() ? 'Success' : 'Warning',
            rows.size(),
            ok,
            updates.size() - ok,
            a.Name + ': ' + ok + ' related ' + child + ' records synced.'
        );
        return ok;
    }
}
