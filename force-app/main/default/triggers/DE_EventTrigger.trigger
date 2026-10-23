trigger DE_EventTrigger on Event(after insert) {
    DE_TriggerHandler.handleActivities('Event');
}
