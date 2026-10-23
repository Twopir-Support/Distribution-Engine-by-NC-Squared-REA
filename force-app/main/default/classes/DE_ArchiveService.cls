/**
 * Auto archive: never-distributed Leads/Cases waiting in a distributor source queue longer than the
 * archive age are moved to the archive queue. Editing an archived record restores it to its source queue.
 */
public without sharing class DE_ArchiveService {
    public static final List<String> OBJECTS = new List<String>{ 'Lead', 'Case' };

    public static void restoreOnEdit(String objectName, List<SObject> newRecords, Map<Id, SObject> oldMap) {
        if (!DE_Schema.hasField(objectName, 'DE_Is_Archived__c') || !DE_Schema.hasField(objectName, 'DE_Source_Queue__c')) {
            return;
        }
        for (SObject r : newRecords) {
            if (r.get('DE_Is_Archived__c') == true && oldMap.get(r.Id).get('DE_Is_Archived__c') == true) {
                Id source = DE_Ids.toId((String) r.get('DE_Source_Queue__c'));
                if (source != null) {
                    r.put('OwnerId', source);
                }
                r.put('DE_Is_Archived__c', false);
            }
        }
    }

    public static Integer archive(Datetime now) {
        if (!DE_Settings.archiveEnabled()) {
            return 0;
        }
        Id archiveQueue = DE_Ids.toId(DE_Settings.archiveQueueId());
        if (archiveQueue == null) {
            DE_RunLogger.log('Archive', 'Warning', 0, 0, 0, 'Auto archive is enabled but no archive queue is set.');
            return 0;
        }
        Datetime cutoff = now.addDays(-DE_Settings.archiveAfterDays());
        Integer total = 0;
        for (String obj : OBJECTS) {
            Set<Id> sources = new Set<Id>();
            for (DE_Distributor__c d : [
                SELECT Source_Id__c
                FROM DE_Distributor__c
                WHERE Active__c = TRUE AND Type__c IN ('Standard', 'Pull') AND Source_Type__c = 'Queue' AND Team__r.Object_API_Name__c = :obj AND Team__r.Active__c = TRUE
            ]) {
                Id q = DE_Ids.toId(d.Source_Id__c);
                if (q != null && q != archiveQueue) {
                    sources.add(q);
                }
            }
            if (sources.isEmpty()) {
                continue;
            }
            List<SObject> rows = Database.queryWithBinds(
                'SELECT Id, OwnerId FROM ' +
                    obj +
                    ' WHERE OwnerId IN :sources AND DE_Is_Distributed__c = false AND DE_Is_Archived__c = false AND CreatedDate < :cutoff LIMIT 5000',
                new Map<String, Object>{ 'sources' => sources, 'cutoff' => cutoff },
                AccessLevel.SYSTEM_MODE
            );
            for (SObject r : rows) {
                r.put('DE_Source_Queue__c', String.valueOf(r.get('OwnerId')));
                r.put('OwnerId', archiveQueue);
                r.put('DE_Is_Archived__c', true);
                r.put('DE_Last_Archive_Date__c', now);
            }
            Boolean previous = DE_TriggerHandler.bypass;
            DE_TriggerHandler.bypass = true;
            try {
                for (Database.SaveResult s : Database.update(rows, false, AccessLevel.SYSTEM_MODE)) {
                    if (s.isSuccess()) {
                        total++;
                    }
                }
            } finally {
                DE_TriggerHandler.bypass = previous;
            }
        }
        DE_RunLogger.log('Archive', 'Success', total, 0, 0, total + ' records archived.');
        return total;
    }

    /** Restores archived records to their source queue (console Archive action). */
    public static Integer restore(Set<Id> recordIds) {
        Integer ok = 0;
        Map<String, List<SObject>> byObject = new Map<String, List<SObject>>();
        for (Id i : recordIds) {
            String obj = i.getSobjectType().getDescribe().getName();
            if (!OBJECTS.contains(obj)) {
                continue;
            }
            if (!byObject.containsKey(obj)) {
                byObject.put(obj, new List<SObject>());
            }
            byObject.get(obj).add(i.getSobjectType().newSObject(i));
        }
        for (String obj : byObject.keySet()) {
            List<SObject> stubs = byObject.get(obj);
            Set<Id> ids = new Map<Id, SObject>(stubs).keySet();
            List<SObject> rows = Database.queryWithBinds(
                'SELECT Id, DE_Source_Queue__c FROM ' + obj + ' WHERE Id IN :ids AND DE_Is_Archived__c = true',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.SYSTEM_MODE
            );
            for (SObject r : rows) {
                Id source = DE_Ids.toId((String) r.get('DE_Source_Queue__c'));
                if (source != null) {
                    r.put('OwnerId', source);
                }
                r.put('DE_Is_Archived__c', false);
            }
            Boolean previous = DE_TriggerHandler.bypass;
            DE_TriggerHandler.bypass = true;
            try {
                for (Database.SaveResult s : Database.update(rows, false, AccessLevel.SYSTEM_MODE)) {
                    if (s.isSuccess()) {
                        ok++;
                    }
                }
            } finally {
                DE_TriggerHandler.bypass = previous;
            }
        }
        return ok;
    }
}
