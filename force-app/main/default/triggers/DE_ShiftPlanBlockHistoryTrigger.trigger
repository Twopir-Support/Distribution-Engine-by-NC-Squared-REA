trigger DE_ShiftPlanBlockHistoryTrigger on DE_Shift_Plan_Block__c(after insert, after update, after delete) {
    DE_TriggerHandler.handleHistory('DE_Shift_Plan_Block__c');
}
