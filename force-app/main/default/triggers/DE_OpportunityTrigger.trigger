trigger DE_OpportunityTrigger on Opportunity(before update, after insert) {
    DE_TriggerHandler.handle('Opportunity');
}
