/**
 * Daily maintenance: purges distribution logs older than the retention period (current assignments are
 * kept), then in finish() purges run logs, availability history, change history, classifier and object
 * sync logs and orphaned domain index rows within the transaction's DML row budget, and runs auto
 * archive and dynamic team member sync. Rows left over by the budget are purged on the next day's run.
 */
public without sharing class DE_MaintenanceBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Integer purged = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime cutoff = System.now().addDays(-DE_Settings.logRetentionDays());
        return Database.getQueryLocator([SELECT Id FROM DE_Assignment_Log__c WHERE Assigned_At__c < :cutoff AND Current__c = FALSE]);
    }

    public void execute(Database.BatchableContext bc, List<DE_Assignment_Log__c> scope) {
        Database.delete(scope, false, AccessLevel.SYSTEM_MODE);
        purged += scope.size();
    }

    public void finish(Database.BatchableContext bc) {
        Datetime now = System.now();
        Map<String, Integer> counts = purgeAll(now);
        List<String> parts = new List<String>{ purged + ' distribution logs' };
        Integer total = purged;
        for (String k : counts.keySet()) {
            parts.add(counts.get(k) + ' ' + k);
            total += counts.get(k);
        }
        DE_RunLogger.log('Purge', 'Success', total, 0, 0, String.join(parts, ', ') + ' purged.');
        DE_ArchiveService.archive(now);
        DE_DynamicMembers.syncAll();
    }

    /** Purges everything with a retention period, in order, until the DML row budget is used. Label -> rows deleted. */
    public static Map<String, Integer> purgeAll(Datetime now) {
        Map<String, Integer> out = new Map<String, Integer>();
        Datetime logCutoff = now.addDays(-DE_Settings.logRetentionDays());
        Datetime availabilityCutoff = now.addDays(-92);
        Datetime historyCutoff = now.addDays(-DE_Settings.historyRetentionDays());
        Datetime classifierCutoff = now.addDays(-DE_Settings.classifierLogRetentionDays());
        out.put('run logs', purge('SELECT Id FROM DE_Run_Log__c WHERE Started_At__c < :cutoff', logCutoff));
        out.put('availability events', purge('SELECT Id FROM DE_Availability_Event__c WHERE Changed_At__c < :cutoff', availabilityCutoff));
        out.put('change history rows', purge('SELECT Id FROM DE_History__c WHERE Changed_At__c < :cutoff', historyCutoff));
        Integer classifier = 0;
        for (String logObject : DE_ClassifierLogs.retentionObjects()) {
            classifier += purge('SELECT Id FROM ' + logObject + ' WHERE Processed_At__c < :cutoff', classifierCutoff);
        }
        out.put('classifier and object sync logs', classifier);
        out.put('orphaned domain index rows', budget() > 0 ? DE_AccountDomainService.purgeOrphans() : 0);
        return out;
    }

    private static Integer budget() {
        // Keep headroom for the run log, archive and dynamic member updates that follow.
        return Math.max(0, Limits.getLimitDmlRows() - Limits.getDmlRows() - 1000);
    }

    private static Integer purge(String soql, Datetime cutoff) {
        Integer room = Math.min(budget(), 9000);
        if (room <= 0 || Limits.getQueries() >= Limits.getLimitQueries() - 10) {
            return 0;
        }
        List<SObject> rows = Database.queryWithBinds(soql + ' LIMIT ' + room, new Map<String, Object>{ 'cutoff' => cutoff }, AccessLevel.SYSTEM_MODE);
        if (!rows.isEmpty()) {
            Database.delete(rows, false, AccessLevel.SYSTEM_MODE);
        }
        return rows.size();
    }
}
