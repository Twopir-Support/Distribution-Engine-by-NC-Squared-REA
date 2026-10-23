trigger DE_CaseTrigger on Case(before update, after insert) {
    DE_TriggerHandler.handle('Case');
}
