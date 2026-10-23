trigger DE_DistributorHistoryTrigger on DE_Distributor__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Distributor__c');
}
