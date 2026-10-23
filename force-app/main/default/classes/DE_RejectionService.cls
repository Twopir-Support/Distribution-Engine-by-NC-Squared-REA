/**
 * Assignment rejection: the assignee (or a manager) hands a record back. The record goes to the
 * distributor's Reject To queue/user, optional fields are updated, the rejecting user is tracked so
 * they do not receive it again, and they can be given a replacement record.
 */
public without sharing class DE_RejectionService {
    public class RejectResult {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public Boolean success = false;
        @AuraEnabled
        public String message;
        public RejectResult(Id recordId) {
            this.recordId = recordId;
        }
    }

    /** Replacement for a rejected (or manually reassigned) record per the distributor setting. */
    public static void applyReplacement(DE_RotationService rotation, DE_Model.DistributorConfig dc, Id memberId, String scope) {
        String mode = dc.dist.Replace_Rejected__c == null ? 'Replace on Usual Assignment' : dc.dist.Replace_Rejected__c;
        if (mode == 'Replace as Next Assignment') {
            rotation.moveToFront(memberId, scope);
        } else if (mode == 'Replace on Usual Assignment') {
            rotation.addReplacementCredit(memberId, scope);
        }
    }

    public static String validateReason(String reason) {
        if (String.isBlank(reason)) {
            return 'Choose a reason for rejecting.';
        }
        for (String r : DE_Settings.rejectReasons()) {
            if (r.equalsIgnoreCase(reason.trim())) {
                return null;
            }
        }
        return DE_Settings.allowOtherRejectReason() ? null : '"' + reason + '" is not an allowed reject reason.';
    }

    public static List<RejectResult> reject(List<Id> recordIds, String reason, Id actingUserId, Boolean actorIsManager) {
        List<RejectResult> results = new List<RejectResult>();
        Map<Id, RejectResult> byRecord = new Map<Id, RejectResult>();
        List<String> keys = new List<String>();
        for (Id i : recordIds) {
            RejectResult r = new RejectResult(i);
            results.add(r);
            byRecord.put(i, r);
            keys.add(String.valueOf(i));
        }
        String reasonError = validateReason(reason);
        if (reasonError != null) {
            for (RejectResult r : results) {
                r.message = reasonError;
            }
            return results;
        }
        Map<String, DE_Assignment_Log__c> logs = new Map<String, DE_Assignment_Log__c>();
        Set<Id> teamIds = new Set<Id>();
        for (DE_Assignment_Log__c l : [
            SELECT
                Id,
                Record_Id__c,
                Record_Name__c,
                Team__c,
                Distributor__c,
                Assignee_Id__c,
                Assigned_User__c,
                Status__c,
                SLA_Status__c,
                Sticky_Key__c,
                Current__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c IN :keys AND Current__c = TRUE
        ]) {
            logs.put(l.Record_Id__c, l);
            teamIds.add(l.Team__c);
        }
        Map<Id, DE_Model.TeamConfig> teams = new Map<Id, DE_Model.TeamConfig>();
        for (DE_Model.TeamConfig cfg : DE_ConfigRepository.load(teamIds, null, true)) {
            teams.put(cfg.team.Id, cfg);
        }
        Map<Id, Integer> rejectedToday = rejectionsToday(actingUserId);
        Map<Id, List<DE_Assignment_Log__c>> byTeam = new Map<Id, List<DE_Assignment_Log__c>>();
        for (Id recordId : recordIds) {
            RejectResult res = byRecord.get(recordId);
            DE_Assignment_Log__c l = logs.get(String.valueOf(recordId));
            if (l == null) {
                res.message = 'This record was not assigned by Distribution Engine.';
                continue;
            }
            DE_Model.TeamConfig cfg = teams.get(l.Team__c);
            DE_Model.DistributorConfig dc = cfg == null ? null : cfg.distributor(l.Distributor__c);
            if (dc == null || dc.dist.Rejection_Enabled__c != true) {
                res.message = 'Rejection is not enabled for the distributor that assigned this record.';
                continue;
            }
            if (String.valueOf(actingUserId) != l.Assignee_Id__c && !actorIsManager) {
                res.message = 'Only the assignee or a manager can reject this record.';
                continue;
            }
            String limitMode = cfg.team.Rejection_Limit__c == null ? 'Unlimited' : cfg.team.Rejection_Limit__c;
            if (limitMode == 'Manager Only' && !actorIsManager) {
                res.message = 'Only managers can reject assignments for this team.';
                continue;
            }
            if (limitMode == 'Limited' && !actorIsManager) {
                Integer used = rejectedToday.containsKey(cfg.team.Id) ? rejectedToday.get(cfg.team.Id) : 0;
                Integer allowed = cfg.team.Rejections_Per_Day__c == null ? 0 : cfg.team.Rejections_Per_Day__c.intValue();
                if (used >= allowed) {
                    res.message = 'You have reached today\'s rejection limit (' + allowed + ').';
                    continue;
                }
                rejectedToday.put(cfg.team.Id, used + 1);
            }
            if (!byTeam.containsKey(cfg.team.Id)) {
                byTeam.put(cfg.team.Id, new List<DE_Assignment_Log__c>());
            }
            byTeam.get(cfg.team.Id).add(l);
        }
        for (Id teamId : byTeam.keySet()) {
            applyTeam(teams.get(teamId), byTeam.get(teamId), reason, actingUserId, byRecord);
        }
        return results;
    }

    private static Map<Id, Integer> rejectionsToday(Id userId) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        Datetime since = DE_ShiftCalendar.always(UserInfo.getTimeZone().getID()).localMidnight(System.now());
        String key = String.valueOf(userId);
        for (AggregateResult ar : [
            SELECT Team__c t, COUNT(Id) c
            FROM DE_Assignment_Log__c
            WHERE Status__c = 'Rejected' AND Assignee_Id__c = :key AND Rejected_At__c >= :since
            GROUP BY Team__c
        ]) {
            out.put((Id) ar.get('t'), (Integer) ar.get('c'));
        }
        return out;
    }

    private static void applyTeam(DE_Model.TeamConfig cfg, List<DE_Assignment_Log__c> logs, String reason, Id actingUserId, Map<Id, RejectResult> byRecord) {
        Set<Id> recordIds = new Set<Id>();
        for (DE_Assignment_Log__c l : logs) {
            recordIds.add(Id.valueOf(l.Record_Id__c));
        }
        List<String> warnings = new List<String>();
        Map<Id, SObject> records = new Map<Id, SObject>(
            DE_RecordQuery.byIds(cfg.objectName, new Set<String>{ 'Id', cfg.assignmentField }, recordIds, warnings)
        );
        DE_TeamLock.lock(cfg);
        DE_RotationService rotation = new DE_RotationService(cfg);
        Map<Id, DE_Record_Detail__c> details = DE_RecordDetails.load(recordIds, null);
        Schema.SObjectType sType = DE_Schema.sobjectType(cfg.objectName);
        Datetime now = System.now();
        List<SObject> updates = new List<SObject>();
        List<DE_Assignment_Log__c> accepted = new List<DE_Assignment_Log__c>();
        for (DE_Assignment_Log__c l : logs) {
            SObject rec = records.get(Id.valueOf(l.Record_Id__c));
            RejectResult res = byRecord.get(Id.valueOf(l.Record_Id__c));
            if (rec == null || String.valueOf(rec.get(cfg.assignmentField)) != l.Assignee_Id__c) {
                res.message = 'This record has been reassigned since it was distributed and can no longer be rejected.';
                continue;
            }
            DE_Model.DistributorConfig dc = cfg.distributor(l.Distributor__c);
            SObject t = sType.newSObject(rec.Id);
            t.put(cfg.assignmentField, DE_Ids.toId(dc.dist.Reject_To_Id__c));
            if (DE_Schema.hasField(cfg.objectName, 'DE_Is_Rejected__c')) {
                t.put('DE_Is_Rejected__c', true);
            }
            if (DE_Schema.hasField(cfg.objectName, 'DE_Last_Rejected__c')) {
                t.put('DE_Last_Rejected__c', now);
            }
            DE_FieldUpdates.apply(t, cfg.objectName, dc.dist.Reject_Field_Updates__c, warnings);
            updates.add(t);
            accepted.add(l);
        }
        Boolean previous = DE_TriggerHandler.bypass;
        DE_TriggerHandler.bypass = true;
        List<Database.SaveResult> saves;
        try {
            saves = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        } finally {
            DE_TriggerHandler.bypass = previous;
        }
        List<DE_Assignment_Log__c> logUpdates = new List<DE_Assignment_Log__c>();
        List<DE_Record_Detail__c> detailUpdates = new List<DE_Record_Detail__c>();
        Map<String, List<DE_Assignment_Log__c>> stickyByMode = new Map<String, List<DE_Assignment_Log__c>>();
        List<DE_Assignment_Event__e> events = new List<DE_Assignment_Event__e>();
        for (Integer i = 0; i < saves.size(); i++) {
            DE_Assignment_Log__c l = accepted[i];
            RejectResult res = byRecord.get(Id.valueOf(l.Record_Id__c));
            if (!saves[i].isSuccess()) {
                res.message = saves[i].getErrors()[0].getMessage();
                continue;
            }
            res.success = true;
            res.message = 'Rejected.';
            DE_Model.DistributorConfig dc = cfg.distributor(l.Distributor__c);
            l.Status__c = 'Rejected';
            l.Current__c = false;
            l.Reject_Reason__c = reason.left(255);
            l.Rejected_At__c = now;
            l.Rejected_By__c = actingUserId;
            l.Next_SLA_Check__c = null;
            if (l.SLA_Status__c == 'Pending') {
                l.SLA_Status__c = 'Cancelled';
            }
            logUpdates.add(l);
            String mode = dc.dist.Remove_Sticky_On_Reassign__c == null ? 'New Sticky Only' : dc.dist.Remove_Sticky_On_Reassign__c;
            if (!stickyByMode.containsKey(mode)) {
                stickyByMode.put(mode, new List<DE_Assignment_Log__c>());
            }
            stickyByMode.get(mode).add(l);
            DE_Record_Detail__c d = DE_RecordDetails.ensure(details, Id.valueOf(l.Record_Id__c), cfg.objectName);
            DE_RecordDetails.pushAssignee(d, DE_Ids.toId(l.Assignee_Id__c));
            detailUpdates.add(d);
            DE_Model.Member m = cfg.member(DE_Ids.toId(l.Assignee_Id__c));
            if (m != null) {
                applyReplacement(rotation, dc, m.memberId, rotation.roundRobinScope(dc));
            }
            events.add(
                new DE_Assignment_Event__e(
                    Record_Id__c = l.Record_Id__c,
                    Object_API_Name__c = cfg.objectName,
                    Record_Name__c = l.Record_Name__c,
                    Assignee_Id__c = l.Assignee_Id__c,
                    Team_Name__c = cfg.team.Name.left(80),
                    Event_Type__c = 'Rejected'
                )
            );
        }
        for (String mode : stickyByMode.keySet()) {
            DE_StickyService.remove(stickyByMode.get(mode), mode);
        }
        Database.update(logUpdates, false, AccessLevel.SYSTEM_MODE);
        DE_RecordDetails.save(detailUpdates);
        rotation.save();
        DE_Notifier.publish(events);
    }
}
