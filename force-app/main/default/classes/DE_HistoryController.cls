/**
 * Change history viewer: the last 100 configuration changes for a team (or another parent such as a
 * holiday region or user), for one object type, or across the whole configuration.
 */
public with sharing class DE_HistoryController {
    public static final Integer MAX_ROWS = 100;

    @AuraEnabled
    public static List<DE_History__c> getHistory(String parentId, String objectName) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view change history');
        Id parent = String.isBlank(parentId) ? null : DE_Ids.toId(parentId);
        if (String.isNotBlank(parentId) && parent == null) {
            throw DE_Ui.error('Invalid record Id.');
        }
        String obj = String.isBlank(objectName) ? null : objectName.trim();
        if (obj != null && !DE_HistoryService.PARENT_FIELD.containsKey(obj)) {
            throw DE_Ui.error('Change history is not recorded for ' + obj + '.');
        }
        List<String> clauses = new List<String>();
        if (parent != null) {
            clauses.add('(Parent_Record_Id__c = :parentKey OR Record_Id__c = :parentKey)');
        }
        if (obj != null) {
            clauses.add('Object_API_Name__c = :obj');
        }
        String soql =
            'SELECT Id, Name, Object_API_Name__c, Record_Id__c, Record_Name__c, Parent_Record_Id__c, Change_Type__c, Field__c, ' +
            'Old_Value__c, New_Value__c, Changed_By__c, Changed_By__r.Name, Changed_At__c, Background_Change__c FROM DE_History__c' +
            (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ')) +
            ' ORDER BY Changed_At__c DESC, Name DESC LIMIT ' +
            MAX_ROWS;
        return Database.queryWithBinds(
            soql,
            new Map<String, Object>{ 'parentKey' => parent == null ? null : String.valueOf(parent), 'obj' => obj },
            AccessLevel.USER_MODE
        );
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getTrackedObjects() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view change history');
        List<Map<String, String>> out = new List<Map<String, String>>();
        List<String> names = new List<String>(DE_HistoryService.PARENT_FIELD.keySet());
        names.sort();
        for (String o : names) {
            Schema.DescribeSObjectResult d = DE_Schema.describe(o);
            out.add(new Map<String, String>{ 'value' => o, 'label' => d == null ? o : d.getLabel() });
        }
        return out;
    }
}
