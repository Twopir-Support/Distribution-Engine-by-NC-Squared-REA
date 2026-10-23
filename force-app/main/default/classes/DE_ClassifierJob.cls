/**
 * Classifies newly inserted records, then (optionally) distributes them immediately instead of
 * waiting for the next scheduler run.
 */
public without sharing class DE_ClassifierJob implements Queueable {
    private String objectName;
    private Set<Id> recordIds;
    private Boolean classify;
    private Boolean distribute;

    public DE_ClassifierJob(String objectName, Set<Id> recordIds, Boolean classify, Boolean distribute) {
        this.objectName = objectName;
        this.recordIds = recordIds;
        this.classify = classify;
        this.distribute = distribute;
    }

    public void execute(QueueableContext context) {
        if (classify) {
            DE_ClassifierService.classify(objectName, recordIds, null);
        }
        if (distribute && DE_Settings.engineEnabled()) {
            DE_DistributionRunner.Summary s = DE_DistributionRunner.runStandard(recordIds, null);
            if (s.errors > 0) {
                DE_RunLogger.log('Scheduler', 'Warning', s.processed, s.assigned, s.errors, String.join(s.messages, '\n'));
            }
        }
    }
}
