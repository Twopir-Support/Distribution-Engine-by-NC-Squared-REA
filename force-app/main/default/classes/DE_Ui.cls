/**
 * Shared helpers for the Lightning controllers: error wrapping, option lists and saving
 * the condition rows that belong to a configuration record.
 */
public with sharing class DE_Ui {
    public class Option {
        @AuraEnabled
        public String label { get; set; }
        @AuraEnabled
        public String value { get; set; }
        @AuraEnabled
        public String kind { get; set; }
        @AuraEnabled
        public String type { get; set; }
        @AuraEnabled
        public List<String> picklistValues { get; set; }
        public Option() {
        }
        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    public static AuraHandledException error(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        String message = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
        return error(message);
    }

    public static void throwIfErrors(List<String> errors) {
        if (errors != null && !errors.isEmpty()) {
            throw error(String.join(errors, '\n'));
        }
    }

    /**
     * Replaces the conditions of one purpose under a parent. Rows are renumbered 1..n when they have
     * no sequence. Runs in user mode so object permissions from the permission sets apply.
     */
    public static void replaceConditions(String parentField, Id parentId, Set<String> purposes, String purpose, List<DE_Condition__c> rows) {
        String soql = 'SELECT Id FROM DE_Condition__c WHERE ' + parentField + ' = :parentId AND Purpose__c IN :purposes';
        List<DE_Condition__c> existing = Database.queryWithBinds(soql, new Map<String, Object>{ 'parentId' => parentId, 'purposes' => purposes }, AccessLevel.USER_MODE);
        if (!existing.isEmpty()) {
            Database.delete(existing, true, AccessLevel.USER_MODE);
        }
        if (rows == null || rows.isEmpty()) {
            return;
        }
        List<DE_Condition__c> inserts = new List<DE_Condition__c>();
        Integer n = 0;
        for (DE_Condition__c r : rows) {
            n++;
            DE_Condition__c c = new DE_Condition__c(
                Sequence__c = r.Sequence__c == null ? n : r.Sequence__c,
                Field_API_Name__c = r.Field_API_Name__c == null ? null : r.Field_API_Name__c.trim(),
                Operator__c = r.Operator__c,
                Value__c = r.Value__c,
                Purpose__c = purpose
            );
            c.put(parentField, parentId);
            inserts.add(c);
        }
        Database.insert(inserts, true, AccessLevel.USER_MODE);
    }

    /** Assigns purpose and sequence to incoming rows so they can be validated before saving. */
    public static List<DE_Condition__c> prepare(List<DE_Condition__c> rows, String purpose) {
        List<DE_Condition__c> out = new List<DE_Condition__c>();
        if (rows == null) {
            return out;
        }
        Integer n = 0;
        for (DE_Condition__c r : rows) {
            n++;
            out.add(
                new DE_Condition__c(
                    Sequence__c = r.Sequence__c == null ? n : r.Sequence__c,
                    Field_API_Name__c = r.Field_API_Name__c,
                    Operator__c = r.Operator__c,
                    Value__c = r.Value__c,
                    Purpose__c = purpose
                )
            );
        }
        return out;
    }

    /** Deletes the rows (no-op when empty). */
    public static void deleteAll(List<SObject> rows, Boolean allOrNone, System.AccessLevel level) {
        if (rows != null && !rows.isEmpty()) {
            Database.delete(rows, allOrNone, level);
        }
    }

    public static Map<Id, String> ownerNames(Set<Id> ids) {
        Map<Id, String> out = new Map<Id, String>();
        Set<Id> users = new Set<Id>();
        Set<Id> groups = new Set<Id>();
        for (Id i : ids) {
            if (i == null) {
                continue;
            }
            if (i.getSobjectType() == User.SObjectType) {
                users.add(i);
            } else if (i.getSobjectType() == Group.SObjectType) {
                groups.add(i);
            }
        }
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :users]) {
            out.put(u.Id, u.Name);
        }
        for (Group g : [SELECT Id, Name FROM Group WHERE Id IN :groups]) {
            out.put(g.Id, g.Name + ' (queue)');
        }
        return out;
    }
}
