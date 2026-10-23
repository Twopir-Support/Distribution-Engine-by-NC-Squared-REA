/**
 * Classifier orchestration: on insert (and through backfill) records are classified with territories,
 * custom stamps, lead matching and lead auto-conversion. Distributors wait for classification to finish.
 */
public without sharing class DE_ClassifierService {
    public static final Set<String> ALL_TYPES = new Set<String>{ 'Territory', 'Stamps', 'Match', 'Conversion' };
    private static Map<String, Boolean> configured = new Map<String, Boolean>();

    /** True when any classifier configuration exists for the object. */
    public static Boolean hasConfiguration(String objectName) {
        String key = objectName.toLowerCase();
        if (!configured.containsKey(key)) {
            Boolean found =
                [SELECT COUNT() FROM DE_Territory__c WHERE Object_API_Name__c = :objectName AND Status__c = 'Active'] > 0 ||
                [SELECT COUNT() FROM DE_Stamp_Group__c WHERE Object_API_Name__c = :objectName AND Active__c = TRUE] > 0;
            if (!found && key == 'lead') {
                found =
                    [SELECT COUNT() FROM DE_Matching_Rule__c WHERE Active__c = TRUE] > 0 ||
                    [SELECT COUNT() FROM DE_Conversion_Rule__c WHERE Active__c = TRUE] > 0;
            }
            configured.put(key, found);
        }
        return configured.get(key);
    }

    /** After insert: mark records as waiting and classify asynchronously (or inline when already async). */
    public static void onInsert(String objectName, Set<Id> recordIds) {
        Boolean classify =
            DE_Settings.classifierEnabled() &&
            DE_Settings.classifierObjects().contains(objectName.toLowerCase()) &&
            hasConfiguration(objectName);
        Boolean distribute = DE_Settings.distributeAfterClassify();
        if (!classify && !distribute) {
            return;
        }
        if (classify) {
            List<DE_Record_Detail__c> waiting = new List<DE_Record_Detail__c>();
            for (Id i : recordIds) {
                waiting.add(
                    new DE_Record_Detail__c(Record_Id__c = i, Object_API_Name__c = objectName, Classifier_Status__c = 'Waiting', Failed_Attempts__c = 0)
                );
            }
            DE_RecordDetails.save(waiting);
            markWaiting(objectName, recordIds);
        }
        Boolean alreadyAsync = System.isBatch() || System.isFuture() || System.isQueueable() || System.isScheduled();
        if (alreadyAsync || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            if (classify) {
                classify(objectName, recordIds, null);
            }
            return;
        }
        System.enqueueJob(new DE_ClassifierJob(objectName, recordIds, classify, distribute));
    }

    /** Classifies records. types = null means all classification types. */
    public static Integer classify(String objectName, Set<Id> recordIds, Set<String> types) {
        Set<String> t = types == null ? ALL_TYPES : types;
        Boolean isLead = objectName.equalsIgnoreCase('Lead');
        List<DE_Territory__c> territories = t.contains('Territory') ? DE_TerritoryClassifier.territories(objectName) : new List<DE_Territory__c>();
        List<DE_StampClassifier.GroupConfig> groups = t.contains('Stamps') ? DE_StampClassifier.groups(objectName) : new List<DE_StampClassifier.GroupConfig>();
        List<DE_Matching_Rule__c> matchRules = isLead && t.contains('Match') ? DE_LeadMatcher.rules() : new List<DE_Matching_Rule__c>();
        List<DE_Conversion_Rule__c> convRules = isLead && t.contains('Conversion') ? DE_LeadConversion.rules() : new List<DE_Conversion_Rule__c>();

        Set<String> paths = new Set<String>{ 'Id', 'CreatedDate' };
        String nameField = DE_Schema.nameField(objectName);
        if (nameField != null) {
            paths.add(nameField);
        }
        paths.addAll(DE_TerritoryClassifier.requiredPaths(objectName, territories));
        paths.addAll(DE_StampClassifier.requiredPaths(groups));
        if (isLead) {
            paths.addAll(DE_LeadMatcher.requiredPaths(matchRules));
            paths.addAll(DE_LeadConversion.requiredPaths(convRules));
        }
        List<String> warnings = new List<String>();
        List<SObject> records = DE_RecordQuery.byIds(objectName, paths, recordIds, warnings);
        // Territory and stamp conditions may read DE.Matched*.<Field>: load those relationship fields too.
        Set<String> detailPaths = new Set<String>();
        for (DE_Territory__c tr : territories) {
            detailPaths.addAll(DE_Conditions.detailFields(tr.Conditions__r));
        }
        for (DE_StampClassifier.GroupConfig g : groups) {
            for (List<DE_Condition__c> c : g.conditions.values()) {
                detailPaths.addAll(DE_Conditions.detailFields(c));
            }
        }
        Set<Id> loadedIds = new Map<Id, SObject>(records).keySet();
        Map<Id, DE_Record_Detail__c> details = DE_RecordDetails.load(loadedIds, detailPaths);
        Map<Id, Map<String, Object>> fieldStamps = new Map<Id, Map<String, Object>>();
        DE_ClassifierLogs.Run run = new DE_ClassifierLogs.Run();
        run.objectName = objectName;
        run.records = records;

        // Each stage runs on its own so one failing stage does not stop the others; failures are logged per stage.
        if (isLead && !matchRules.isEmpty()) {
            run.stages.add(DE_ClassifierLogs.MATCH);
            try {
                DE_LeadMatcher.match(records, details, matchRules);
                run.matches = DE_LeadMatcher.lastMatches;
                if (hasRelationshipPath(detailPaths)) {
                    // Persist the new matches and reload so the matched records' fields can be evaluated.
                    DE_RecordDetails.save(details.values());
                    details = DE_RecordDetails.load(loadedIds, detailPaths);
                }
            } catch (Exception e) {
                stageFailed(run, DE_ClassifierLogs.MATCH, e, warnings);
            }
        }
        if (!territories.isEmpty()) {
            run.stages.add(DE_ClassifierLogs.TERRITORY);
            try {
                mergeStamps(fieldStamps, DE_TerritoryClassifier.classify(objectName, records, details, territories));
                run.territory = DE_TerritoryClassifier.lastResults;
            } catch (Exception e) {
                stageFailed(run, DE_ClassifierLogs.TERRITORY, e, warnings);
            }
        }
        if (!groups.isEmpty()) {
            run.stages.add(DE_ClassifierLogs.STAMPS);
            try {
                mergeStamps(fieldStamps, DE_StampClassifier.classify(objectName, records, details, groups));
            } catch (Exception e) {
                stageFailed(run, DE_ClassifierLogs.STAMPS, e, warnings);
            }
        }
        for (SObject r : records) {
            // Details are always released ("Done") so distribution never waits on a failing classifier.
            DE_RecordDetails.ensure(details, r.Id, objectName).Classifier_Status__c = 'Done';
        }
        DE_RecordDetails.save(details.values());
        // Field stamps and the status mirror are written before conversion: converted leads cannot be updated.
        mirrorStatus(objectName, records, run, fieldStamps);
        writeStamps(objectName, fieldStamps, warnings);
        if (isLead && !convRules.isEmpty()) {
            run.stages.add(DE_ClassifierLogs.CONVERSION);
            try {
                DE_LeadConversion.run(records, details, convRules);
                run.conversions = DE_LeadConversion.lastResults;
                DE_RecordDetails.save(details.values());
            } catch (Exception e) {
                stageFailed(run, DE_ClassifierLogs.CONVERSION, e, warnings);
            }
        }
        run.details = details;
        DE_ClassifierLogs.write(run);
        if (!warnings.isEmpty()) {
            DE_RunLogger.log('Classifier', run.errors.isEmpty() ? 'Warning' : 'Error', records.size(), 0, run.errors.size(), String.join(warnings, '\n'));
        }
        return records.size();
    }

    private static void stageFailed(DE_ClassifierLogs.Run run, String stage, Exception e, List<String> warnings) {
        run.errors.put(stage, e.getMessage());
        warnings.add(stage + ': ' + e.getMessage());
    }

    /** Adds Done or Error (match, territory and stamp stages) for the record's DE_Classifier_Status__c field, when the object has it. */
    private static void mirrorStatus(String objectName, List<SObject> records, DE_ClassifierLogs.Run run, Map<Id, Map<String, Object>> fieldStamps) {
        if (!DE_Schema.hasField(objectName, 'DE_Classifier_Status__c')) {
            return;
        }
        for (SObject r : records) {
            if (!fieldStamps.containsKey(r.Id)) {
                fieldStamps.put(r.Id, new Map<String, Object>());
            }
            fieldStamps.get(r.Id).put('DE_Classifier_Status__c', run.errors.isEmpty() ? 'Done' : 'Error');
        }
    }

    /** Shows "Waiting" on the record while the classifier job runs. */
    private static void markWaiting(String objectName, Set<Id> recordIds) {
        if (!DE_Schema.hasField(objectName, 'DE_Classifier_Status__c')) {
            return;
        }
        Map<Id, Map<String, Object>> status = new Map<Id, Map<String, Object>>();
        for (Id i : recordIds) {
            status.put(i, new Map<String, Object>{ 'DE_Classifier_Status__c' => 'Waiting' });
        }
        writeStamps(objectName, status, new List<String>());
    }

    private static Boolean hasRelationshipPath(Set<String> detailPaths) {
        for (String p : detailPaths) {
            if (p.contains('__r.')) {
                return true;
            }
        }
        return false;
    }

    private static void mergeStamps(Map<Id, Map<String, Object>> target, Map<Id, Map<String, Object>> source) {
        for (Id i : source.keySet()) {
            if (!target.containsKey(i)) {
                target.put(i, new Map<String, Object>());
            }
            target.get(i).putAll(source.get(i));
        }
    }

    private static void writeStamps(String objectName, Map<Id, Map<String, Object>> fieldStamps, List<String> warnings) {
        if (fieldStamps.isEmpty()) {
            return;
        }
        Schema.SObjectType sType = DE_Schema.sobjectType(objectName);
        List<SObject> updates = new List<SObject>();
        for (Id i : fieldStamps.keySet()) {
            SObject s = sType.newSObject(i);
            for (String f : fieldStamps.get(i).keySet()) {
                Schema.DescribeFieldResult fd = DE_Schema.field(objectName, f);
                if (fd != null && fd.isUpdateable()) {
                    Object v = fieldStamps.get(i).get(f);
                    s.put(fd.getName(), v instanceof String && fd.getLength() > 0 ? ((String) v).left(fd.getLength()) : v);
                }
            }
            updates.add(s);
        }
        Boolean previous = DE_TriggerHandler.bypass;
        DE_TriggerHandler.bypass = true;
        try {
            for (Database.SaveResult r : Database.update(updates, false, AccessLevel.SYSTEM_MODE)) {
                if (!r.isSuccess()) {
                    warnings.add('Stamp update failed: ' + r.getErrors()[0].getMessage());
                }
            }
        } finally {
            DE_TriggerHandler.bypass = previous;
        }
    }
}
