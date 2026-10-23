/**
 * Rebuilds the lead-matching domain index (DE_Account_Domain__c) for every account.
 * Started from the Record Classification tab after installation or after bulk data loads with triggers off.
 */
public without sharing class DE_AccountDomainBatch implements Database.Batchable<SObject>, Database.Stateful {
    private Integer accounts = 0;
    private Integer rows = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id FROM Account ORDER BY Id]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        accounts += scope.size();
        rows += DE_AccountDomainService.rebuild(new Map<Id, Account>(scope).keySet());
    }

    public void finish(Database.BatchableContext bc) {
        Integer purged = DE_AccountDomainService.purgeOrphans();
        DE_RunLogger.log(
            'Classifier',
            'Success',
            accounts,
            0,
            0,
            'Domain index rebuilt: ' + rows + ' domains for ' + accounts + ' accounts; ' + purged + ' orphaned rows removed.'
        );
    }
}
