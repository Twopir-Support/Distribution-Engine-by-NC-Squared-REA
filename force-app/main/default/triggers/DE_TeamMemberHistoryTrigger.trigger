trigger DE_TeamMemberHistoryTrigger on DE_Team_Member__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Team_Member__c');
}
