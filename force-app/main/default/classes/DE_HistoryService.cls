/**
 * Change history of Distribution Engine configuration: teams, team members, team managers, distributors,
 * holiday regions and holidays, out of office, shifts, shift planner blocks and tag assignments.
 * One DE_History__c row per created or deleted record and per changed field. Changes made by the engine
 * itself (scheduler, timers, calendar sync, batches) are flagged as background changes.
 */
public without sharing class DE_HistoryService {
    /** Set to true to suppress history (e.g. bulk configuration import that logs its own summary). */
    public static Boolean disabled = false;

    /** Object -> field holding the parent (team, region, user...) used to show history in context. Null = the record itself. */
    public static final Map<String, String> PARENT_FIELD = new Map<String, String>{
        'DE_Team__c' => null,
        'DE_Team_Member__c' => 'Team__c',
        'DE_Distributor__c' => 'Team__c',
        'DE_Team_Manager__c' => 'Team__c',
        'DE_Holiday_Region__c' => null,
        'DE_Holiday__c' => 'Holiday_Region__c',
        'DE_Out_Of_Office__c' => 'User__c',
        'DE_Shift__c' => null,
        'DE_Shift_Plan_Block__c' => 'Shift_Plan__c',
        'DE_Agent__c' => 'User__c'
    };

    /** Objects where only some fields are tracked (tag assignments live on the availability record). */
    private static final Map<String, Set<String>> ONLY_FIELDS = new Map<String, Set<String>>{ 'de_agent__c' => new Set<String>{ 'tags__c' } };

    /** Engine-maintained or system fields that would only add noise. */
    private static final Set<String> SKIP = new Set<String>{
        'id',
        'isdeleted',
        'createddate',
        'createdbyid',
        'lastmodifieddate',
        'lastmodifiedbyid',
        'systemmodstamp',
        'lastvieweddate',
        'lastreferenceddate',
        'lastactivitydate',
        'rotation_sequence__c',
        'total_assignments__c',
        'last_assigned_at__c',
        'unique_key__c',
        'unique_user__c'
    };

    public static void record(String objectName, System.TriggerOperation op, List<SObject> newRows, Map<Id, SObject> oldMap) {
        if (disabled || !PARENT_FIELD.containsKey(objectName)) {
            return;
        }
        try {
            List<DE_History__c> rows = build(objectName, op, newRows, oldMap);
            if (!rows.isEmpty()) {
                Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
            }
        } catch (Exception e) {
            // History must never block a configuration change.
            System.debug(LoggingLevel.WARN, 'Change history not recorded: ' + e.getMessage());
        }
    }

    public static Boolean isBackground() {
        return System.isBatch() || System.isFuture() || System.isQueueable() || System.isScheduled() || DE_TriggerHandler.bypass;
    }

    @TestVisible
    private static List<DE_History__c> build(String objectName, System.TriggerOperation op, List<SObject> newRows, Map<Id, SObject> oldMap) {
        List<DE_History__c> out = new List<DE_History__c>();
        Set<String> only = ONLY_FIELDS.get(objectName.toLowerCase());
        List<String> tracked = trackedFields(objectName, only);
        Boolean background = isBackground();
        Datetime now = System.now();
        List<SObject> rows = op == System.TriggerOperation.AFTER_DELETE ? oldMap.values() : newRows;
        Map<Id, Id> parents = parentIds(objectName, rows);
        for (SObject r : rows) {
            DE_History__c base = new DE_History__c(
                Object_API_Name__c = objectName,
                Record_Id__c = r.Id,
                Record_Name__c = name(r),
                Parent_Record_Id__c = parents.get(r.Id),
                Parent_Object__c = parents.get(r.Id) == null ? null : parents.get(r.Id).getSobjectType().getDescribe().getName(),
                Changed_By__c = UserInfo.getUserId(),
                Changed_At__c = now,
                Background_Change__c = background
            );
            if (op == System.TriggerOperation.AFTER_INSERT || op == System.TriggerOperation.AFTER_DELETE) {
                Boolean created = op == System.TriggerOperation.AFTER_INSERT;
                if (only != null) {
                    // Partially tracked objects: record the tracked values instead of a create/delete row.
                    for (String f : tracked) {
                        if (r.get(f) != null) {
                            DE_History__c h = base.clone(false, true);
                            h.Change_Type__c = 'Updated';
                            h.Field__c = f;
                            h.Old_Value__c = created ? null : format(r.get(f));
                            h.New_Value__c = created ? format(r.get(f)) : null;
                            out.add(h);
                        }
                    }
                    continue;
                }
                DE_History__c h = base.clone(false, true);
                h.Change_Type__c = created ? 'Created' : 'Deleted';
                h.Old_Value__c = created ? null : base.Record_Name__c;
                h.New_Value__c = created ? base.Record_Name__c : null;
                out.add(h);
            } else if (op == System.TriggerOperation.AFTER_UPDATE) {
                SObject old = oldMap.get(r.Id);
                for (String f : tracked) {
                    Object before = old.get(f);
                    Object after = r.get(f);
                    if (same(before, after)) {
                        continue;
                    }
                    DE_History__c h = base.clone(false, true);
                    h.Change_Type__c = 'Updated';
                    h.Field__c = f;
                    h.Old_Value__c = format(before);
                    h.New_Value__c = format(after);
                    out.add(h);
                }
            }
        }
        return out;
    }

    private static List<String> trackedFields(String objectName, Set<String> only) {
        List<String> out = new List<String>();
        for (Schema.SObjectField f : DE_Schema.fields(objectName).values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            String n = fd.getName();
            String lower = n.toLowerCase();
            if (only != null ? !only.contains(lower) : (SKIP.contains(lower) || fd.isCalculated() || fd.isAutoNumber())) {
                continue;
            }
            out.add(n);
        }
        out.sort();
        return out;
    }

    private static Map<Id, Id> parentIds(String objectName, List<SObject> rows) {
        Map<Id, Id> out = new Map<Id, Id>();
        String field = PARENT_FIELD.get(objectName);
        if (field == null) {
            for (SObject r : rows) {
                out.put(r.Id, r.Id);
            }
            return out;
        }
        for (SObject r : rows) {
            out.put(r.Id, (Id) r.get(field));
        }
        if (objectName == 'DE_Shift_Plan_Block__c') {
            // Show planner changes with their team.
            Set<Id> planIds = new Set<Id>(out.values());
            planIds.remove(null);
            Map<Id, DE_Shift_Plan__c> plans = new Map<Id, DE_Shift_Plan__c>([SELECT Id, Team__c FROM DE_Shift_Plan__c WHERE Id IN :planIds]);
            for (Id i : out.keySet()) {
                DE_Shift_Plan__c p = plans.get(out.get(i));
                out.put(i, p == null ? out.get(i) : p.Team__c);
            }
        }
        return out;
    }

    /** Exact comparison (String == is case-insensitive in Apex, so compare the text forms). */
    @TestVisible
    private static Boolean same(Object a, Object b) {
        if (a == null || b == null) {
            return a == null && b == null;
        }
        return String.valueOf(a).equals(String.valueOf(b));
    }

    private static String name(SObject r) {
        try {
            Object n = r.get('Name');
            return n == null ? null : String.valueOf(n).left(255);
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String format(Object v) {
        if (v == null) {
            return null;
        }
        if (v instanceof Datetime) {
            return ((Datetime) v).formatGmt('yyyy-MM-dd HH:mm:ss') + ' GMT';
        }
        return String.valueOf(v).left(4000);
    }

    /** Deletes history older than the retention period. Returns rows removed. */
    public static Integer purge(Datetime now) {
        Datetime cutoff = now.addDays(-DE_Settings.historyRetentionDays());
        List<DE_History__c> old = [SELECT Id FROM DE_History__c WHERE Changed_At__c < :cutoff LIMIT 9000];
        if (!old.isEmpty()) {
            Database.delete(old, false, AccessLevel.SYSTEM_MODE);
        }
        return old.size();
    }
}
