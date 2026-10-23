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
                when BEFORE_INSERT {
                    stampDomains(objectName, Trigger.new);
                }
                when BEFORE_UPDATE {
                    stampDomains(objectName, Trigger.new);
                    DE_ArchiveService.restoreOnEdit(objectName, Trigger.new, Trigger.oldMap);
                    DE_ActionTracking.beforeUpdate(objectName, Trigger.new, Trigger.oldMap);
                    DE_TriggerDistribution.beforeUpdate(objectName, Trigger.new, Trigger.oldMap);
                }
                when AFTER_INSERT {
                    indexDomains(objectName, Trigger.new, null);
                    DE_ClassifierService.onInsert(objectName, Trigger.newMap.keySet());
                }
                when AFTER_UPDATE {
                    indexDomains(objectName, Trigger.new, Trigger.oldMap);
                }
                when AFTER_DELETE {
                    indexDomains(objectName, null, Trigger.oldMap);
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

    /** Contact email domains used by lead matching. */
    private static void stampDomains(String objectName, List<SObject> rows) {
        if (objectName == 'Contact') {
            DE_AccountDomainService.stampContactDomains(rows);
        }
    }

    /** Keeps the lead-matching domain index current for accounts and contacts. */
    private static void indexDomains(String objectName, List<SObject> newRows, Map<Id, SObject> oldMap) {
        if (objectName == 'Account') {
            DE_AccountDomainService.onAccountsChanged(newRows, oldMap);
        } else if (objectName == 'Contact') {
            DE_AccountDomainService.onContactsChanged(newRows, oldMap);
        }
    }

    /** Config object triggers (teams, members, distributors, availability): change history. */
    public static void handleHistory(String objectName) {
        if (!Trigger.isExecuting || DE_HistoryService.disabled) {
            return;
        }
        DE_HistoryService.record(objectName, Trigger.operationType, Trigger.new, Trigger.oldMap);
    }
}
