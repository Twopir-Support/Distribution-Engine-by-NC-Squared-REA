trigger DE_HolidayHistoryTrigger on DE_Holiday__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Holiday__c');
}
