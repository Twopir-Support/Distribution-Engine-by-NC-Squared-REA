trigger DE_ContactTrigger on Contact(before update, after insert) {
    DE_TriggerHandler.handle('Contact');
}
