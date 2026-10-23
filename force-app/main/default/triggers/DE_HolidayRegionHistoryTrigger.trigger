trigger DE_HolidayRegionHistoryTrigger on DE_Holiday_Region__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Holiday_Region__c');
}
