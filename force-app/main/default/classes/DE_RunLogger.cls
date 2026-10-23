/**
 * Writes engine run logs (scheduler, classifier, SLA monitor, object sync, archive, health checker),
 * including heap usage at the time of logging and the Apex job Id when known.
 */
public without sharing class DE_RunLogger {
    public static DE_Run_Log__c log(String process, String status, Integer processed, Integer assignments, Integer errors, String message) {
        DE_Run_Log__c r = build(process, status, processed, assignments, errors, message, System.now(), null);
        Database.insert(r, false, AccessLevel.SYSTEM_MODE);
        return r;
    }

    public static DE_Run_Log__c build(
        String process,
        String status,
        Integer processed,
        Integer assignments,
        Integer errors,
        String message,
        Datetime startedAt,
        Long durationMs
    ) {
        return build(process, status, processed, assignments, errors, message, startedAt, durationMs, null);
    }

    public static DE_Run_Log__c build(
        String process,
        String status,
        Integer processed,
        Integer assignments,
        Integer errors,
        String message,
        Datetime startedAt,
        Long durationMs,
        Id jobId
    ) {
        return new DE_Run_Log__c(
            Heap_Used__c = Limits.getHeapSize(),
            Job_Id__c = jobId,
            Process__c = process,
            Status__c = status,
            Started_At__c = startedAt,
            Duration_Ms__c = durationMs,
            Records_Processed__c = processed,
            Assignments__c = assignments,
            Errors__c = errors,
            Message__c = message == null ? null : message.left(32000)
        );
    }
}
