trigger DE_AgentHistoryTrigger on DE_Agent__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Agent__c');
}
