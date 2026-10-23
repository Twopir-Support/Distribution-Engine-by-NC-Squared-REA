trigger DE_LeadTrigger on Lead(before update, after insert) {
    DE_TriggerHandler.handle('Lead');
}
