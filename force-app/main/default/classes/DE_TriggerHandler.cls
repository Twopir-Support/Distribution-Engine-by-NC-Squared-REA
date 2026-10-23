/**
 * Single entry point for every Distribution Engine trigger. Any object (including custom objects)
 * can be enabled with a one-line trigger:
 *
 *   trigger My_Object_DE on My_Object__c (before update, after insert) {
 *       DE_TriggerHandler.handle('My_Object__c');
 *   }
 *
 * The engine sets bypass = true around its own record updates so they never re-enter routing.
 */
public without sharing class DE_TriggerHandler {
    public static Boolean bypass = false;

    public static void handle(String objectName) {
        if (bypass || !Trigger.isExecuting || !DE_Settings.engineEnabled()) {
            return;
        }
        try {
            switch on Trigger.operationType {
                when BEFORE_UPDATE {
                    DE_ArchiveService.restoreOnEdit(objectName, Trigger.new, Trigger.oldMap);
                    DE_ActionTracking.beforeUpdate(objectName, Trigger.new, Trigger.oldMap);
                    DE_TriggerDistribution.beforeUpdate(objectName, Trigger.new, Trigger.oldMap);
                }
                when AFTER_INSERT {
                    DE_ClassifierService.onInsert(objectName, Trigger.newMap.keySet());
                }
                when else {
                    return;
                }
            }
        } catch (DE_TeamLock.LockException e) {
            // A concurrent assignment holds the team; the scheduler will retry.
            System.debug(LoggingLevel.WARN, e.getMessage());
        }
    }

    /** Task and Event after insert: auto action tracking and calendar out of office. */
    public static void handleActivities(String activityObject) {
        if (bypass || !Trigger.isExecuting || !DE_Settings.engineEnabled() || Trigger.operationType != System.TriggerOperation.AFTER_INSERT) {
            return;
        }
        DE_ActionTracking.autoAction(Trigger.new);
        if (activityObject == 'Event') {
            DE_CalendarSync.createOutOfOffice(Trigger.new);
        }
    }
}
