/**
 * Custom classification: stamp groups and their ordered stamps. A Single group applies the first
 * matching stamp; a Multiple group applies every matching stamp. Stamps are stored on the details as
 * "Group:Value" and optionally written to a field on the record.
 */
public without sharing class DE_StampClassifier {
    public class GroupConfig {
        public DE_Stamp_Group__c grp;
        public List<DE_Stamp__c> stamps = new List<DE_Stamp__c>();
        public Map<Id, List<DE_Condition__c>> conditions = new Map<Id, List<DE_Condition__c>>();
    }

    public static List<GroupConfig> groups(String objectName) {
        List<GroupConfig> out = new List<GroupConfig>();
        List<DE_Stamp_Group__c> groupRows = [
            SELECT
                Id,
                Name,
                Object_API_Name__c,
                Group_Type__c,
                Stamp_Field__c,
                (SELECT Id, Name, Order__c, Condition_Logic__c FROM Stamps__r ORDER BY Order__c, Name)
            FROM DE_Stamp_Group__c
            WHERE Object_API_Name__c = :objectName AND Active__c = TRUE
            ORDER BY Name
        ];
        Set<Id> stampIds = new Set<Id>();
        for (DE_Stamp_Group__c g : groupRows) {
            for (DE_Stamp__c s : g.Stamps__r) {
                stampIds.add(s.Id);
            }
        }
        Map<Id, List<DE_Condition__c>> byStamp = new Map<Id, List<DE_Condition__c>>();
        for (DE_Condition__c c : [
            SELECT Id, Stamp__c, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c
            FROM DE_Condition__c
            WHERE Stamp__c IN :stampIds
            ORDER BY Sequence__c
        ]) {
            if (!byStamp.containsKey(c.Stamp__c)) {
                byStamp.put(c.Stamp__c, new List<DE_Condition__c>());
            }
            byStamp.get(c.Stamp__c).add(c);
        }
        for (DE_Stamp_Group__c g : groupRows) {
            GroupConfig gc = new GroupConfig();
            gc.grp = g;
            gc.stamps = g.Stamps__r;
            for (DE_Stamp__c s : g.Stamps__r) {
                gc.conditions.put(s.Id, byStamp.containsKey(s.Id) ? byStamp.get(s.Id) : new List<DE_Condition__c>());
            }
            out.add(gc);
        }
        return out;
    }

    public static Set<String> requiredPaths(List<GroupConfig> groups) {
        Set<String> out = new Set<String>();
        for (GroupConfig g : groups) {
            for (List<DE_Condition__c> c : g.conditions.values()) {
                out.addAll(DE_Conditions.recordPaths(c));
            }
        }
        return out;
    }

    public static Map<Id, Map<String, Object>> classify(
        String objectName,
        List<SObject> records,
        Map<Id, DE_Record_Detail__c> details,
        List<GroupConfig> groups
    ) {
        Map<Id, Map<String, Object>> stamps = new Map<Id, Map<String, Object>>();
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.details = details;
        for (SObject rec : records) {
            DE_Record_Detail__c d = DE_RecordDetails.ensure(details, rec.Id, objectName);
            List<String> all = new List<String>();
            for (GroupConfig g : groups) {
                List<String> values = new List<String>();
                for (DE_Stamp__c s : g.stamps) {
                    if (DE_Conditions.matches(rec, g.conditions.get(s.Id), s.Condition_Logic__c, ctx, null)) {
                        values.add(s.Name);
                        if (g.grp.Group_Type__c != 'Multiple') {
                            break;
                        }
                    }
                }
                for (String v : values) {
                    all.add(g.grp.Name + ':' + v);
                }
                if (String.isNotBlank(g.grp.Stamp_Field__c) && DE_Schema.hasField(objectName, g.grp.Stamp_Field__c)) {
                    if (!stamps.containsKey(rec.Id)) {
                        stamps.put(rec.Id, new Map<String, Object>());
                    }
                    stamps.get(rec.Id).put(g.grp.Stamp_Field__c, values.isEmpty() ? null : String.join(values, ';'));
                }
            }
            d.Stamps__c = all.isEmpty() ? null : String.join(all, ';').left(4000);
        }
        return stamps;
    }
}
