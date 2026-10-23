trigger DE_ShiftHistoryTrigger on DE_Shift__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Shift__c');
}
