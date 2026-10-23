/**
 * Object Sync: after a parent record is assigned to a user, related child records (via a lookup)
 * that match the action's filters take the same owner. Actions run in execution order. Every synced
 * parent record gets an Object Sync Log with the actions performed (Success, Error, or Skipped when
 * no related records needed a change).
 */
public without sharing class DE_ObjectSyncService {
    public static final String CHANGE_OWNER = 'Change Owner';

    /** Per parent record: synced counts by related object, errors and the first error message. */
    private class ParentResult {
        Map<String, Integer> synced = new Map<String, Integer>();
        Integer errors = 0;
        String message;
    }

    public static Integer sync(DE_Model.TeamConfig cfg, List<DE_Model.Decision> decisions) {
        Map<Id, Id> ownerByParent = new Map<Id, Id>();
        Map<Id, String> nameByParent = new Map<Id, String>();
        String nameField = DE_Schema.nameField(cfg.objectName);
        for (DE_Model.Decision d : decisions) {
            if (d.status == 'Assigned' && d.assigneeId != null && d.assigneeId.getSobjectType() == User.SObjectType) {
                ownerByParent.put(d.recordId, d.assigneeId);
                nameByParent.put(d.recordId, recordName(d.record, nameField));
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
                Order__c,
                Action_Type__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Object_Sync__c
            WHERE Active__c = TRUE AND Parent_Object__c = :parentObject AND (Action_Type__c = :CHANGE_OWNER OR Action_Type__c = NULL)
            ORDER BY Order__c NULLS LAST, Name
        ];
        if (actions.isEmpty()) {
            return 0;
        }
        Map<Id, ParentResult> results = new Map<Id, ParentResult>();
        for (Id p : ownerByParent.keySet()) {
            results.put(p, new ParentResult());
        }
        Integer changed = 0;
        for (DE_Object_Sync__c a : actions) {
            changed += runAction(a, ownerByParent, results);
        }
        writeLogs(cfg, ownerByParent, nameByParent, results);
        return changed;
    }

    private static String recordName(SObject rec, String nameField) {
        try {
            Object v = rec == null || nameField == null ? null : rec.get(nameField);
            return v == null ? null : String.valueOf(v).left(255);
        } catch (Exception e) {
            return null; // name field not queried for this record
        }
    }

    private static Integer runAction(DE_Object_Sync__c a, Map<Id, Id> ownerByParent, Map<Id, ParentResult> results) {
        String child = DE_Schema.objectName(a.Child_Object__c);
        String lookup = DE_Schema.canonicalPath(child, a.Lookup_Field__c);
        if (lookup == null || !DE_Schema.hasField(child, 'OwnerId')) {
            for (ParentResult r : results.values()) {
                r.errors++;
                r.message = r.message == null ? (a.Name + ': ' + child + '.' + a.Lookup_Field__c + ' is not a lookup with an owner.') : r.message;
            }
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
        List<Id> updateParents = new List<Id>();
        Schema.SObjectType t = DE_Schema.sobjectType(child);
        for (SObject r : rows) {
            Id parent = (Id) r.get(lookup);
            Id newOwner = ownerByParent.get(parent);
            if (newOwner == null || r.get('OwnerId') == newOwner) {
                continue;
            }
            if (!DE_Conditions.matches(r, conds, a.Filter_Logic__c, ctx, null)) {
                continue;
            }
            SObject u = t.newSObject(r.Id);
            u.put('OwnerId', newOwner);
            updates.add(u);
            updateParents.add(parent);
        }
        if (updates.isEmpty()) {
            return 0;
        }
        Boolean previous = DE_TriggerHandler.bypass;
        DE_TriggerHandler.bypass = true;
        Integer ok = 0;
        try {
            List<Database.SaveResult> saved = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saved.size(); i++) {
                ParentResult pr = results.get(updateParents[i]);
                if (saved[i].isSuccess()) {
                    ok++;
                    pr.synced.put(child, (pr.synced.containsKey(child) ? pr.synced.get(child) : 0) + 1);
                } else {
                    pr.errors++;
                    if (pr.message == null) {
                        pr.message = child + ' ' + updates[i].Id + ': ' + saved[i].getErrors()[0].getMessage();
                    }
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

    private static void writeLogs(DE_Model.TeamConfig cfg, Map<Id, Id> ownerByParent, Map<Id, String> nameByParent, Map<Id, ParentResult> results) {
        List<DE_Object_Sync_Log__c> logs = new List<DE_Object_Sync_Log__c>();
        Datetime now = System.now();
        for (Id parent : results.keySet()) {
            ParentResult r = results.get(parent);
            Integer synced = 0;
            List<String> lines = new List<String>();
            List<String> objects = new List<String>(r.synced.keySet());
            objects.sort();
            for (String o : objects) {
                synced += r.synced.get(o);
                lines.add(o + '=' + r.synced.get(o));
            }
            logs.add(
                new DE_Object_Sync_Log__c(
                    Record_Id__c = parent,
                    Record_Name__c = nameByParent.get(parent),
                    Object_API_Name__c = cfg.objectName,
                    Team__c = cfg.team.Id,
                    Assignee_Id__c = ownerByParent.get(parent),
                    Status__c = r.errors > 0 ? 'Error' : (synced > 0 ? 'Success' : 'Skipped'),
                    Actions_Performed__c = lines.isEmpty() ? null : String.join(lines, '\n'),
                    Synced_Records__c = synced,
                    Errors__c = r.errors,
                    Error_Message__c = r.message == null ? null : r.message.left(255),
                    Processed_At__c = now
                )
            );
        }
        Database.insert(logs, false, AccessLevel.SYSTEM_MODE);
    }
}
