/**
 * Repository for DE_Record_Detail__c: classifier output and per-record distribution state
 * (failed attempts, hold, previous assignees), keyed by the routed record's Id.
 */
public without sharing class DE_RecordDetails {
    private static final List<String> BASE_FIELDS = new List<String>{
        'Id',
        'Record_Id__c',
        'Object_API_Name__c',
        'Classifier_Status__c',
        'Territory__c',
        'Territory_Name__c',
        'Matched_Account__c',
        'Matched_Contact__c',
        'Matched_Lead__c',
        'Match_Confidence__c',
        'Domain__c',
        'Personal_Email__c',
        'Stamps__c',
        'Conversion_Result__c',
        'Failed_Attempts__c',
        'On_Hold_Until__c',
        'Last_Error__c',
        'Previous_Assignees__c',
        'Source_Queue_Id__c',
        'Is_Archived__c',
        'Archived_At__c',
        'CreatedDate'
    };
    public static final Integer MAX_TRACKED = 50;

    public static Map<Id, DE_Record_Detail__c> load(Set<Id> recordIds, Set<String> extraFields) {
        Map<Id, DE_Record_Detail__c> out = new Map<Id, DE_Record_Detail__c>();
        if (recordIds == null || recordIds.isEmpty()) {
            return out;
        }
        Set<String> fields = new Set<String>(BASE_FIELDS);
        if (extraFields != null) {
            for (String f : extraFields) {
                String canonical = DE_Schema.canonicalPath('DE_Record_Detail__c', f);
                if (canonical != null) {
                    fields.add(canonical);
                }
            }
        }
        List<String> keys = new List<String>();
        for (Id i : recordIds) {
            keys.add(String.valueOf(i));
        }
        String soql = 'SELECT ' + String.join(new List<String>(fields), ', ') + ' FROM DE_Record_Detail__c WHERE Record_Id__c IN :keys';
        for (
            DE_Record_Detail__c d : (List<DE_Record_Detail__c>) Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'keys' => keys },
                AccessLevel.SYSTEM_MODE
            )
        ) {
            out.put(Id.valueOf(d.Record_Id__c), d);
        }
        return out;
    }

    /** Returns the details for a record, creating an unsaved one when it does not exist yet. */
    public static DE_Record_Detail__c ensure(Map<Id, DE_Record_Detail__c> details, Id recordId, String objectName) {
        DE_Record_Detail__c d = details.get(recordId);
        if (d == null) {
            d = new DE_Record_Detail__c(
                Record_Id__c = String.valueOf(recordId),
                Object_API_Name__c = objectName,
                Classifier_Status__c = 'Done',
                Failed_Attempts__c = 0
            );
            details.put(recordId, d);
        }
        return d;
    }

    public static void save(List<DE_Record_Detail__c> details) {
        if (details == null || details.isEmpty()) {
            return;
        }
        Database.upsert(details, DE_Record_Detail__c.Record_Id__c, false, AccessLevel.SYSTEM_MODE);
    }

    public static List<Id> previousAssignees(DE_Record_Detail__c d) {
        List<Id> out = new List<Id>();
        if (d == null || String.isBlank(d.Previous_Assignees__c)) {
            return out;
        }
        for (String s : d.Previous_Assignees__c.split(',')) {
            Id i = DE_Ids.toId(s);
            if (i != null) {
                out.add(i);
            }
        }
        return out;
    }

    /** The last N tracked assignees, most recent first. */
    public static Set<Id> recentAssignees(DE_Record_Detail__c d, Integer n) {
        Set<Id> out = new Set<Id>();
        if (n <= 0) {
            return out;
        }
        for (Id i : previousAssignees(d)) {
            if (out.size() >= n) {
                break;
            }
            out.add(i);
        }
        return out;
    }

    public static void pushAssignee(DE_Record_Detail__c d, Id assignee) {
        if (d == null || assignee == null) {
            return;
        }
        List<Id> current = previousAssignees(d);
        List<String> next = new List<String>{ String.valueOf(assignee) };
        for (Id i : current) {
            if (i != assignee && next.size() < MAX_TRACKED) {
                next.add(String.valueOf(i));
            }
        }
        d.Previous_Assignees__c = String.join(next, ',');
    }

    /** True while classification has not finished (records older than 10 minutes are never blocked). */
    public static Boolean isWaiting(DE_Record_Detail__c d, Datetime recordCreated, Datetime now) {
        if (d == null || d.Classifier_Status__c == null || d.Classifier_Status__c == 'Done') {
            return false;
        }
        return recordCreated == null || recordCreated > now.addMinutes(-10);
    }

    public static Boolean isOnHold(DE_Record_Detail__c d, Datetime now) {
        return d != null && d.On_Hold_Until__c != null && d.On_Hold_Until__c > now;
    }
}
