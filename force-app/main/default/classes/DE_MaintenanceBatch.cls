/**
 * Daily maintenance: purges logs older than the retention period (current assignments are kept),
 * then runs auto archive and dynamic team member sync in finish().
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
        Datetime cutoff = System.now().addDays(-DE_Settings.logRetentionDays());
        List<DE_Run_Log__c> oldRuns = [SELECT Id FROM DE_Run_Log__c WHERE Started_At__c < :cutoff LIMIT 9000];
        Database.delete(oldRuns, false, AccessLevel.SYSTEM_MODE);
        Datetime historyCutoff = System.now().addDays(-92);
        List<DE_Availability_Event__c> oldEvents = [SELECT Id FROM DE_Availability_Event__c WHERE Changed_At__c < :historyCutoff LIMIT 9000];
        Database.delete(oldEvents, false, AccessLevel.SYSTEM_MODE);
        DE_RunLogger.log('Purge', 'Success', purged + oldRuns.size() + oldEvents.size(), 0, 0, purged + ' distribution logs, ' + oldRuns.size() + ' run logs and ' + oldEvents.size() + ' availability events purged.');
        DE_ArchiveService.archive(System.now());
        DE_DynamicMembers.syncAll();
    }
}
