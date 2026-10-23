/**
 * Sticky assignment: records with the same match value (e.g. Email) go to the same member for a period.
 * Sticky keys are stored on Distribution Logs, scoped to the distributor, team or globally.
 */
public without sharing class DE_StickyService {
    public static String scopePrefix(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc) {
        String level = dc.dist.Sticky_Level__c == null ? 'Distributor' : dc.dist.Sticky_Level__c;
        if (level == 'Global') {
            return 'G';
        }
        if (level == 'Team') {
            return 'T|' + cfg.team.Id;
        }
        return 'D|' + dc.dist.Id;
    }

    /** The sticky key for a record, or null when the match field is blank. */
    public static String key(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, SObject rec) {
        if (dc.dist.Sticky_Enabled__c != true || String.isBlank(dc.dist.Sticky_Field__c)) {
            return null;
        }
        Object v;
        try {
            v = DE_Conditions.readPath(rec, dc.dist.Sticky_Field__c);
        } catch (Exception e) {
            return null;
        }
        if (v == null || String.isBlank(String.valueOf(v))) {
            return null;
        }
        return (scopePrefix(cfg, dc) + '|' + String.valueOf(v).trim().toLowerCase()).left(255);
    }

    /** Most recent assignee per sticky key within the sticky period. */
    public static Map<String, Id> lookup(Set<String> keys, Integer days, Datetime now) {
        Map<String, Id> out = new Map<String, Id>();
        if (keys.isEmpty()) {
            return out;
        }
        Datetime since = now.addDays(-(days == null ? 90 : days));
        for (DE_Assignment_Log__c l : [
            SELECT Sticky_Key__c, Assignee_Id__c
            FROM DE_Assignment_Log__c
            WHERE Sticky_Key__c IN :keys AND Assigned_At__c >= :since AND Status__c IN :DE_CapService.COUNTED_STATUSES
            ORDER BY Assigned_At__c DESC
            LIMIT 2000
        ]) {
            if (!out.containsKey(l.Sticky_Key__c) && l.Assignee_Id__c != null) {
                out.put(l.Sticky_Key__c, Id.valueOf(l.Assignee_Id__c));
            }
        }
        return out;
    }

    /**
     * Removes sticky matches after reassignment or rejection.
     * New Sticky Only clears the key on the log being reassigned; Always clears every log with that key.
     */
    public static void remove(List<DE_Assignment_Log__c> logs, String mode) {
        if (mode == 'Never' || logs.isEmpty()) {
            return;
        }
        Set<String> keys = new Set<String>();
        for (DE_Assignment_Log__c l : logs) {
            if (String.isNotBlank(l.Sticky_Key__c)) {
                keys.add(l.Sticky_Key__c);
                l.Sticky_Key__c = null;
            }
        }
        if (mode == 'Always' && !keys.isEmpty()) {
            Map<Id, DE_Assignment_Log__c> byId = new Map<Id, DE_Assignment_Log__c>(logs);
            List<DE_Assignment_Log__c> others = new List<DE_Assignment_Log__c>();
            for (DE_Assignment_Log__c l : [SELECT Id FROM DE_Assignment_Log__c WHERE Sticky_Key__c IN :keys LIMIT 5000]) {
                if (!byId.containsKey(l.Id)) {
                    others.add(new DE_Assignment_Log__c(Id = l.Id, Sticky_Key__c = null));
                }
            }
            if (!others.isEmpty()) {
                Database.update(others, false, AccessLevel.SYSTEM_MODE);
            }
        }
    }
}
