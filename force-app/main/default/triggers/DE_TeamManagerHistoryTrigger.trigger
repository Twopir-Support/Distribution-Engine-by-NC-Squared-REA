trigger DE_TeamManagerHistoryTrigger on DE_Team_Manager__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Team_Manager__c');
}
