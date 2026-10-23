/**
 * Classifier logs: the latest territory, lead matching, auto conversion and custom classification
 * result of each record (one row per record and type, upserted by Record_Id__c), with errors and the
 * number of attempts. Records in error are retried by the scheduler on later runs.
 */
public without sharing class DE_ClassifierLogs {
    public static final String TERRITORY = 'Territory';
    public static final String MATCH = 'Match';
    public static final String CONVERSION = 'Conversion';
    public static final String STAMPS = 'Stamps';

    /** Log object per classification type. */
    public static final Map<String, String> LOG_OBJECT = new Map<String, String>{
        TERRITORY => 'DE_Territory_Log__c',
        MATCH => 'DE_Matching_Log__c',
        CONVERSION => 'DE_Conversion_Log__c',
        STAMPS => 'DE_Classification_Log__c'
    };

    /** Outcome of one classify() call, handed over by DE_ClassifierService. */
    public class Run {
        public String objectName;
        public List<SObject> records = new List<SObject>();
        public Map<Id, DE_Record_Detail__c> details = new Map<Id, DE_Record_Detail__c>();
        /** Classification types that ran in this call. */
        public Set<String> stages = new Set<String>();
        /** Type -> error message when the stage failed for the whole batch. */
        public Map<String, String> errors = new Map<String, String>();
        public Map<Id, DE_TerritoryClassifier.Result> territory = new Map<Id, DE_TerritoryClassifier.Result>();
        public Map<Id, DE_LeadMatcher.MatchInfo> matches = new Map<Id, DE_LeadMatcher.MatchInfo>();
        public Map<Id, DE_Conversion_Log__c> conversions = new Map<Id, DE_Conversion_Log__c>();
    }

    public static void write(Run run) {
        if (run.records.isEmpty() || run.stages.isEmpty()) {
            return;
        }
        String nameField = DE_Schema.nameField(run.objectName);
        Datetime now = System.now();
        for (String stage : run.stages) {
            String logObject = LOG_OBJECT.get(stage);
            Map<String, SObject> previous = previous(logObject, run.records);
            List<SObject> rows = new List<SObject>();
            for (SObject rec : run.records) {
                SObject row = build(stage, rec, run);
                if (row == null) {
                    continue;
                }
                String key = String.valueOf(rec.Id);
                String err = run.errors.get(stage);
                if (err == null && row.get('Error_Message__c') != null) {
                    err = (String) row.get('Error_Message__c'); // per-record failure, e.g. a lead that could not be converted
                }
                SObject prev = previous.get(key);
                Boolean prevError = prev != null && prev.get('In_Error__c') == true;
                Decimal prevAttempts = prev == null || prev.get('Attempts__c') == null ? 0 : (Decimal) prev.get('Attempts__c');
                row.put('Record_Id__c', key);
                row.put('Object_API_Name__c', run.objectName);
                row.put('Record_Name__c', readName(rec, nameField));
                row.put('Processed_At__c', now);
                row.put('In_Error__c', err != null);
                row.put('Error_Message__c', err == null ? null : err.left(255));
                row.put('Attempts__c', err != null && prevError ? prevAttempts + 1 : 1);
                rows.add(row);
            }
            upsertRows(logObject, rows);
        }
    }

    private static SObject build(String stage, SObject rec, Run run) {
        DE_Record_Detail__c d = run.details.get(rec.Id);
        if (stage == TERRITORY) {
            DE_Territory_Log__c t = new DE_Territory_Log__c(Match_Level__c = 'None');
            DE_TerritoryClassifier.Result r = run.territory.get(rec.Id);
            if (r != null) {
                t.Territory__c = r.territory == null ? null : r.territory.Id;
                t.Match_Level__c = r.matchLevel;
                if (r.location != null) {
                    t.Clean_Country__c = r.location.country == null ? null : r.location.country.left(80);
                    t.Clean_State__c = r.location.state == null ? null : r.location.state.left(80);
                    t.Clean_Postal_Code__c = r.location.postal == null ? null : r.location.postal.left(20);
                }
            }
            return t;
        }
        if (stage == MATCH) {
            DE_Matching_Log__c m = new DE_Matching_Log__c();
            if (d != null) {
                m.Matched_Account__c = d.Matched_Account__c;
                m.Matched_Contact__c = d.Matched_Contact__c;
                m.Matched_Lead__c = d.Matched_Lead__c;
            }
            DE_LeadMatcher.MatchInfo info = run.matches.get(rec.Id);
            if (info != null) {
                m.Account_Rule__c = info.accountRuleId;
                m.Account_Confidence__c = info.accountConfidence;
                m.Lead_Rule__c = info.leadRuleId;
                m.Lead_Confidence__c = info.leadConfidence;
            }
            return m;
        }
        if (stage == CONVERSION) {
            DE_Conversion_Log__c c = run.conversions.get(rec.Id);
            return c == null ? new DE_Conversion_Log__c(Result__c = 'Not Converted') : c.clone(false, true);
        }
        DE_Classification_Log__c s = new DE_Classification_Log__c();
        s.Stamps__c = d == null || String.isBlank(d.Stamps__c) ? null : d.Stamps__c.replace(';', '\n').left(4000);
        return s;
    }

    private static String readName(SObject rec, String nameField) {
        try {
            Object v = nameField == null ? null : rec.get(nameField);
            return v == null ? null : String.valueOf(v).left(255);
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, SObject> previous(String logObject, List<SObject> records) {
        List<String> keys = new List<String>();
        for (SObject r : records) {
            keys.add(String.valueOf(r.Id));
        }
        Map<String, SObject> out = new Map<String, SObject>();
        for (
            SObject row : Database.queryWithBinds(
                'SELECT Record_Id__c, In_Error__c, Attempts__c FROM ' + logObject + ' WHERE Record_Id__c IN :keys',
                new Map<String, Object>{ 'keys' => keys },
                AccessLevel.SYSTEM_MODE
            )
        ) {
            out.put((String) row.get('Record_Id__c'), row);
        }
        return out;
    }

    private static void upsertRows(String logObject, List<SObject> rows) {
        if (rows.isEmpty()) {
            return;
        }
        Schema.SObjectField key = DE_Schema.fields(logObject).get('record_id__c');
        List<SObject> typed = (List<SObject>) Type.forName('List<' + logObject + '>').newInstance();
        typed.addAll(rows);
        Database.upsert(typed, key, false, AccessLevel.SYSTEM_MODE);
    }

    // ------------------------------------------------------------------ retry and maintenance

    /** Re-classifies records whose last classification failed, oldest first. Returns records retried. */
    public static Integer retryFailed(Integer maxRecords) {
        Integer retried = 0;
        for (String stage : LOG_OBJECT.keySet()) {
            if (retried >= maxRecords || Limits.getQueries() > Limits.getLimitQueries() * 0.6) {
                break;
            }
            Map<String, Set<Id>> byObject = new Map<String, Set<Id>>();
            for (
                SObject row : Database.query(
                    'SELECT Record_Id__c, Object_API_Name__c FROM ' + LOG_OBJECT.get(stage) + ' WHERE In_Error__c = TRUE ORDER BY Processed_At__c LIMIT ' +
                    (maxRecords - retried)
                )
            ) {
                Id recordId = DE_Ids.toId((String) row.get('Record_Id__c'));
                String obj = (String) row.get('Object_API_Name__c');
                if (recordId == null || String.isBlank(obj)) {
                    continue;
                }
                if (!byObject.containsKey(obj)) {
                    byObject.put(obj, new Set<Id>());
                }
                byObject.get(obj).add(recordId);
            }
            for (String obj : byObject.keySet()) {
                DE_ClassifierService.classify(obj, byObject.get(obj), new Set<String>{ stage });
                retried += byObject.get(obj).size();
            }
        }
        return retried;
    }

    /** Records that failed classification at least `threshold` times in a row, per log type. */
    public static Map<String, Integer> repeatedFailures(Integer threshold) {
        Map<String, Integer> out = new Map<String, Integer>();
        for (String stage : LOG_OBJECT.keySet()) {
            Integer n = Database.countQuery(
                'SELECT COUNT() FROM ' + LOG_OBJECT.get(stage) + ' WHERE In_Error__c = TRUE AND Attempts__c >= ' + Integer.valueOf(threshold)
            );
            if (n > 0) {
                out.put(stage, n);
            }
        }
        return out;
    }

    /** Log objects purged with the classifier/sync log retention period. */
    public static List<String> retentionObjects() {
        List<String> out = LOG_OBJECT.values().clone();
        out.add('DE_Object_Sync_Log__c');
        return out;
    }
}
