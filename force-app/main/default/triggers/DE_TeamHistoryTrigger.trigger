trigger DE_TeamHistoryTrigger on DE_Team__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Team__c');
}
