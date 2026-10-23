trigger DE_OutOfOfficeHistoryTrigger on DE_Out_Of_Office__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Out_Of_Office__c');
}
