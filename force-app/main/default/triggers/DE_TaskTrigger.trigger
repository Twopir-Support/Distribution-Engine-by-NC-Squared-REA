trigger DE_TaskTrigger on Task(after insert) {
    DE_TriggerHandler.handleActivities('Task');
}
