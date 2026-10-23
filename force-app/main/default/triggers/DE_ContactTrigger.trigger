trigger DE_ContactTrigger on Contact(before insert, before update, after insert, after update, after delete) {
    DE_TriggerHandler.handle('Contact');
}
