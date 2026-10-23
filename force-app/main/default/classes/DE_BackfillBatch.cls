/**
 * Backfill: classifies existing records of an object (optionally only those created since a date),
 * then emails the requester when finished.
 */
public without sharing class DE_BackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    private String objectName;
    private Set<String> types;
    private Datetime createdSince;
    private Id requestedBy;
    private Integer processed = 0;

    public DE_BackfillBatch(String objectName, Set<String> types, Datetime createdSince, Boolean emailWhenDone) {
        this.objectName = DE_Schema.objectName(objectName);
        this.types = types == null || types.isEmpty() ? DE_ClassifierService.ALL_TYPES : types;
        this.createdSince = createdSince;
        this.requestedBy = emailWhenDone == true ? UserInfo.getUserId() : null;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String soql = 'SELECT Id FROM ' + objectName + (createdSince == null ? '' : ' WHERE CreatedDate >= :createdSince') + ' ORDER BY CreatedDate';
        return Database.getQueryLocatorWithBinds(soql, new Map<String, Object>{ 'createdSince' => createdSince }, AccessLevel.SYSTEM_MODE);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        processed += DE_ClassifierService.classify(objectName, new Map<Id, SObject>(scope).keySet(), types);
    }

    public void finish(Database.BatchableContext bc) {
        String message = 'Backfill of ' + objectName + ' (' + String.join(new List<String>(types), ', ') + ') classified ' + processed + ' records.';
        DE_RunLogger.log('Classifier', 'Success', processed, 0, 0, message);
        if (requestedBy != null) {
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTargetObjectId(requestedBy);
            m.setSaveAsActivity(false);
            m.setSubject('Distribution Engine backfill complete');
            m.setPlainTextBody(message);
            try {
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ m }, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, e.getMessage());
            }
        }
    }
}
