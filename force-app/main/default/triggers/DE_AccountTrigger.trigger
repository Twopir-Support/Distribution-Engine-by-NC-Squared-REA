trigger DE_AccountTrigger on Account(before update, after insert) {
    DE_TriggerHandler.handle('Account');
}
