/**
 * Record page component: distribution status and history, manual assignment, rejection,
 * distribute now and the assignment simulator for one record.
 */
public with sharing class DE_RecordDetailController {
    public class RecordState {
        @AuraEnabled
        public Boolean distributed = false;
        @AuraEnabled
        public DE_Assignment_Log__c current;
        @AuraEnabled
        public List<DE_Assignment_Log__c> history = new List<DE_Assignment_Log__c>();
        @AuraEnabled
        public DE_Record_Detail__c details;
        @AuraEnabled
        public Boolean canAssign = false;
        @AuraEnabled
        public Boolean canReject = false;
        @AuraEnabled
        public Boolean canDistribute = false;
        @AuraEnabled
        public Boolean canSimulate = false;
        @AuraEnabled
        public List<String> rejectReasons;
        @AuraEnabled
        public Boolean allowOtherReason;
    }

    private static Boolean canEdit(Id recordId) {
        List<UserRecordAccess> a = [SELECT RecordId, HasEditAccess FROM UserRecordAccess WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId];
        return !a.isEmpty() && a[0].HasEditAccess;
    }

    @AuraEnabled
    public static RecordState getRecordState(Id recordId) {
        DE_Permissions.require(DE_Permissions.isUser(), 'view distribution details');
        RecordState s = new RecordState();
        String key = String.valueOf(recordId);
        s.history = [
            SELECT
                Id,
                Name,
                Team__r.Name,
                Distributor__r.Name,
                Distributor__r.Rejection_Enabled__c,
                Assignee_Id__c,
                Assigned_User__r.Name,
                Previous_Owner_Id__c,
                Method__c,
                Type__c,
                Status__c,
                Is_Sticky__c,
                Assigned_At__c,
                Speed_To_Assign_Seconds__c,
                SLA_Status__c,
                SLA_Missed__c,
                Next_SLA_Check__c,
                Time_To_Action_Mins__c,
                Reject_Reason__c,
                Message__c,
                Current__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c = :key
            WITH USER_MODE
            ORDER BY Assigned_At__c DESC
            LIMIT 50
        ];
        for (DE_Assignment_Log__c l : s.history) {
            if (l.Current__c) {
                s.current = l;
                s.distributed = true;
                break;
            }
        }
        s.details = DE_RecordDetails.load(
                new Set<Id>{ recordId },
                new Set<String>{ 'Matched_Account__r.Name', 'Matched_Contact__r.Name', 'Matched_Lead__r.Name' }
            )
            .get(recordId);
        Boolean edit = canEdit(recordId);
        Boolean manager = DE_Permissions.isTeamManager();
        s.canAssign = manager && edit;
        s.canDistribute = edit;
        s.canSimulate = manager;
        s.canReject =
            s.current != null &&
            s.current.Distributor__r != null &&
            s.current.Distributor__r.Rejection_Enabled__c &&
            (s.current.Assignee_Id__c == String.valueOf(UserInfo.getUserId()) || manager);
        s.rejectReasons = DE_Settings.rejectReasons();
        s.allowOtherReason = DE_Settings.allowOtherRejectReason();
        return s;
    }

    @AuraEnabled
    public static List<DE_ManualAssignService.TeamOption> getManualOptions(Id recordId) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'assign records manually');
        try {
            return DE_ManualAssignService.options(recordId);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void assignManually(Id recordId, Id distributorId, Id memberId) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'assign records manually');
        if (!canEdit(recordId)) {
            throw DE_Ui.error('You do not have edit access to this record.');
        }
        try {
            DE_ManualAssignService.assign(recordId, distributorId, memberId);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static DE_RejectionService.RejectResult reject(Id recordId, String reason) {
        return DE_WidgetController.reject(recordId, reason);
    }

    /** Runs Trigger distributors, then Standard distributors, for this record now. */
    @AuraEnabled
    public static String distributeNow(Id recordId) {
        DE_Permissions.require(DE_Permissions.isUser(), 'distribute records');
        if (!canEdit(recordId)) {
            throw DE_Ui.error('You do not have edit access to this record.');
        }
        try {
            DE_TriggerDistribution.Outcome o = DE_TriggerDistribution.distributeIds(new Set<Id>{ recordId }, 'Manual');
            if (o.assigned + o.defaulted > 0) {
                return 'Assigned by a trigger distributor.';
            }
            DE_DistributionRunner.Summary s = DE_DistributionRunner.runStandard(new Set<Id>{ recordId }, null);
            if (s.assigned > 0) {
                return 'Assigned by a standard distributor.';
            }
            return 'Not assigned. Use Simulate to see why.';
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static DE_Simulator.Result simulate(Id recordId, DE_Simulator.Options options) {
        return DE_ConsoleController.simulate(recordId, options);
    }
}
