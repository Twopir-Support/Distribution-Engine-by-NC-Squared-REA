trigger DE_AccountTrigger on Account(before update, after insert, after update, after delete) {
    DE_TriggerHandler.handle('Account');
}
