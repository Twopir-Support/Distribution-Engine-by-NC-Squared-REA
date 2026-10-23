trigger DE_EventTrigger on Event(after insert, after update, after delete) {
    if (Trigger.isInsert) {
        DE_TriggerHandler.handleActivities('Event');
    } else {
        DE_CalendarSync.onEventChange(Trigger.new, Trigger.oldMap, Trigger.isDelete);
    }
}
