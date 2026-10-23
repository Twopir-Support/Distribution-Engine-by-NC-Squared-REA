/**
 * Distribution Engine widget (utility bar): availability toggle, out of office, Get Next (pull),
 * the user's current assignments and missed SLAs, and rejection.
 */
public with sharing class DE_WidgetController {
    public class AssignedItem {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public Datetime assignedAt;
        @AuraEnabled
        public Datetime nextSlaCheck;
        @AuraEnabled
        public Integer slaMissed;
        @AuraEnabled
        public String teamName;
        @AuraEnabled
        public Boolean canReject;
    }

    public class State {
        @AuraEnabled
        public Boolean online;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Datetime offlineUntil;
        @AuraEnabled
        public Boolean isMember;
        @AuraEnabled
        public List<String> toggleReasons;
        @AuraEnabled
        public Boolean requireReason;
        @AuraEnabled
        public List<Integer> timerDurations;
        @AuraEnabled
        public Boolean timerOnly;
        @AuraEnabled
        public List<String> rejectReasons;
        @AuraEnabled
        public Boolean allowOtherReason;
        @AuraEnabled
        public List<DE_PullService.PullOption> pullOptions = new List<DE_PullService.PullOption>();
        @AuraEnabled
        public List<AssignedItem> assigned = new List<AssignedItem>();
        @AuraEnabled
        public List<AssignedItem> missedSlas = new List<AssignedItem>();
        @AuraEnabled
        public Boolean isManager;
    }

    @AuraEnabled
    public static State getState() {
        DE_Permissions.require(DE_Permissions.isUser(), 'use the Distribution Engine widget');
        Id me = UserInfo.getUserId();
        State s = new State();
        DE_Agent__c agent = DE_ConfigRepository.agentsByUser(new Set<Id>{ me }).get(me);
        s.online = agent == null || agent.Online__c;
        s.reason = agent == null ? null : agent.Toggle_Reason__c;
        s.offlineUntil = agent == null ? null : agent.Toggle_Until__c;
        s.isMember = [SELECT COUNT() FROM DE_Team_Member__c WHERE User__c = :me AND Active__c = TRUE] > 0;
        s.toggleReasons = DE_Settings.toggleReasons();
        s.requireReason = DE_Settings.requireToggleReason();
        s.timerDurations = DE_Settings.timerDurations();
        s.isManager = DE_Permissions.isTeamManager();
        s.timerOnly = DE_Settings.timerTogglesOnly() && !s.isManager;
        s.rejectReasons = DE_Settings.rejectReasons();
        s.allowOtherReason = DE_Settings.allowOtherRejectReason();
        s.pullOptions = DE_PullService.options(me);
        String key = String.valueOf(me);
        List<DE_Assignment_Log__c> current = [
            SELECT
                Record_Id__c,
                Record_Name__c,
                Object_API_Name__c,
                Assigned_At__c,
                Next_SLA_Check__c,
                SLA_Missed__c,
                Team__r.Name,
                Team__r.Widget_Active_Only__c,
                Team__r.Active_Status_Field__c,
                Team__r.Active_Status_Values__c,
                Distributor__r.Rejection_Enabled__c,
                Distributor__r.Salesforce_Team_Enabled__c
            FROM DE_Assignment_Log__c
            WHERE Assignee_Id__c = :key AND Current__c = TRUE
            ORDER BY Next_SLA_Check__c ASC NULLS LAST, Assigned_At__c DESC
            LIMIT 50
        ];
        Set<Id> inactive = inactiveRecords(current);
        for (DE_Assignment_Log__c l : current) {
            if (inactive.contains(Id.valueOf(l.Record_Id__c))) {
                continue;
            }
            AssignedItem a = new AssignedItem();
            a.recordId = Id.valueOf(l.Record_Id__c);
            a.name = l.Record_Name__c;
            a.objectName = l.Object_API_Name__c;
            a.assignedAt = l.Assigned_At__c;
            a.nextSlaCheck = l.Next_SLA_Check__c;
            a.slaMissed = l.SLA_Missed__c == null ? 0 : l.SLA_Missed__c.intValue();
            a.teamName = l.Team__r == null ? null : l.Team__r.Name;
            a.canReject = l.Distributor__r != null && l.Distributor__r.Rejection_Enabled__c && l.Distributor__r.Salesforce_Team_Enabled__c != true;
            if (s.assigned.size() < 5) {
                s.assigned.add(a);
            }
            if (a.slaMissed > 0) {
                s.missedSlas.add(a);
            }
        }
        return s;
    }

    /**
     * Records that must be hidden from "Assigned to me" because their team shows only active records
     * (Show Only Active Records in Widget) and the record's active status field is not an active value.
     * One query per object and status field.
     */
    @TestVisible
    private static Set<Id> inactiveRecords(List<DE_Assignment_Log__c> logs) {
        Set<Id> out = new Set<Id>();
        Map<String, Set<Id>> idsByQuery = new Map<String, Set<Id>>();
        Map<String, Set<String>> valuesByRecord = new Map<String, Set<String>>();
        for (DE_Assignment_Log__c l : logs) {
            if (l.Team__r == null || l.Team__r.Widget_Active_Only__c != true || String.isBlank(l.Team__r.Active_Status_Field__c)) {
                continue;
            }
            Set<String> active = new Set<String>();
            for (String v : DE_Conditions.splitValues(l.Team__r.Active_Status_Values__c)) {
                active.add(v.toLowerCase());
            }
            if (active.isEmpty() || !DE_Schema.hasField(l.Object_API_Name__c, l.Team__r.Active_Status_Field__c)) {
                continue;
            }
            String queryKey = l.Object_API_Name__c + '|' + l.Team__r.Active_Status_Field__c;
            if (!idsByQuery.containsKey(queryKey)) {
                idsByQuery.put(queryKey, new Set<Id>());
            }
            idsByQuery.get(queryKey).add(Id.valueOf(l.Record_Id__c));
            valuesByRecord.put(l.Record_Id__c, active);
        }
        for (String queryKey : idsByQuery.keySet()) {
            String obj = queryKey.substringBefore('|');
            String field = queryKey.substringAfter('|');
            Set<Id> ids = idsByQuery.get(queryKey);
            for (
                SObject r : Database.queryWithBinds(
                    'SELECT Id, ' + String.escapeSingleQuotes(field) + ' FROM ' + String.escapeSingleQuotes(obj) + ' WHERE Id IN :ids',
                    new Map<String, Object>{ 'ids' => ids },
                    AccessLevel.SYSTEM_MODE
                )
            ) {
                Object v = r.get(field);
                if (v == null || !valuesByRecord.get(String.valueOf(r.Id)).contains(String.valueOf(v).toLowerCase())) {
                    out.add(r.Id);
                }
            }
        }
        return out;
    }

    @AuraEnabled
    public static void toggle(Boolean online, String reason, Integer timerMinutes) {
        DE_Permissions.require(DE_Permissions.isUser(), 'change your availability');
        try {
            DE_AgentService.setOnline(new Set<Id>{ UserInfo.getUserId() }, online, reason, timerMinutes, DE_Permissions.isTeamManager() ? 'Manager' : 'User');
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static DE_PullService.PullResult pull(Id distributorId) {
        DE_Permissions.require(DE_Permissions.isUser(), 'pull records');
        try {
            return DE_PullService.pull(UserInfo.getUserId(), distributorId);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static DE_RejectionService.RejectResult reject(Id recordId, String reason) {
        DE_Permissions.require(DE_Permissions.isUser(), 'reject assignments');
        try {
            DE_RejectionService.RejectResult r = DE_RejectionService.reject(
                new List<Id>{ recordId },
                reason,
                UserInfo.getUserId(),
                DE_Permissions.isTeamManager()
            )[0];
            if (!r.success) {
                throw DE_Ui.error(r.message);
            }
            return r;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static Id createOutOfOffice(Datetime startAt, Datetime endAt, String reason, Boolean allDay) {
        return DE_AvailabilityController.saveOutOfOffice(
            new DE_Out_Of_Office__c(
                User__c = UserInfo.getUserId(),
                Start__c = startAt,
                End__c = endAt,
                Reason__c = reason,
                All_Day__c = allDay == true,
                Source__c = 'Manual'
            )
        );
    }
}
