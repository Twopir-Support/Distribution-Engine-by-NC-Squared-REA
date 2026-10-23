/**
 * Persists assignment decisions: updates the records (or the Trigger.new rows in place),
 * writes Distribution Logs, updates per-record details, sends notifications and platform events,
 * and runs Object Sync. Record DML is partial-success: one failing record never blocks the others.
 */
public without sharing class DE_AssignmentWriter {
    public class Result {
        public Integer assigned = 0;
        public Integer errors = 0;
        public List<DE_Assignment_Log__c> logs = new List<DE_Assignment_Log__c>();
        public Map<Id, String> errorByRecord = new Map<Id, String>();
    }

    public static Result persist(DE_Model.TeamConfig cfg, List<DE_Model.Decision> decisions, DE_DistributionCore.RunContext ctx, Boolean inPlace) {
        Result result = new Result();
        List<DE_Model.Decision> toWrite = new List<DE_Model.Decision>();
        for (DE_Model.Decision d : decisions) {
            if (d.status == 'Assigned' && d.assigneeId != null) {
                toWrite.add(d);
            }
        }
        if (toWrite.isEmpty() || ctx.dryRun) {
            result.assigned = ctx.dryRun ? toWrite.size() : 0;
            return result;
        }
        String obj = cfg.objectName;
        Datetime now = ctx.now;
        Boolean hasDistributed = DE_Schema.hasField(obj, 'DE_Is_Distributed__c');
        Boolean hasLast = DE_Schema.hasField(obj, 'DE_Last_Distributed__c');
        Boolean hasCount = DE_Schema.hasField(obj, 'DE_Distribution_Count__c');
        Schema.SObjectType sType = DE_Schema.sobjectType(obj);

        // 1. Record updates.
        List<SObject> targets = new List<SObject>();
        for (DE_Model.Decision d : toWrite) {
            SObject target = inPlace ? d.record : sType.newSObject(d.recordId);
            if (d.method != 'Current Owner') {
                target.put(cfg.assignmentField, d.assigneeId);
            }
            if (hasDistributed) {
                target.put('DE_Is_Distributed__c', true);
            }
            if (hasLast) {
                target.put('DE_Last_Distributed__c', now);
            }
            if (hasCount) {
                Object c = d.record.get('DE_Distribution_Count__c');
                target.put('DE_Distribution_Count__c', (c == null ? 0 : (Decimal) c) + 1);
            }
            DE_Distributor__c dist = d.distributor == null ? null : d.distributor.dist;
            if (dist != null && dist.Source_Type__c == 'Field Value' && String.isNotBlank(dist.Source_After_Value__c)) {
                DE_FieldUpdates.apply(target, obj, dist.Source_Field__c + '=' + dist.Source_After_Value__c, d.trace);
            }
            if (dist != null) {
                DE_FieldUpdates.apply(target, obj, dist.Field_Updates__c, d.trace);
            }
            targets.add(target);
        }
        if (!inPlace) {
            Boolean previous = DE_TriggerHandler.bypass;
            DE_TriggerHandler.bypass = true;
            List<Database.SaveResult> saves;
            try {
                saves = Database.update(targets, false, AccessLevel.SYSTEM_MODE);
            } finally {
                DE_TriggerHandler.bypass = previous;
            }
            for (Integer i = 0; i < saves.size(); i++) {
                if (!saves[i].isSuccess()) {
                    List<String> msgs = new List<String>();
                    for (Database.Error e : saves[i].getErrors()) {
                        msgs.add(e.getMessage());
                    }
                    toWrite[i].status = 'Error';
                    toWrite[i].message = String.join(msgs, '; ');
                    toWrite[i].trace.add('Update failed: ' + toWrite[i].message);
                }
            }
        }

        // 2. Logs.
        Set<String> successIds = new Set<String>();
        for (DE_Model.Decision d : toWrite) {
            if (d.status == 'Assigned') {
                successIds.add(String.valueOf(d.recordId));
            }
        }
        retireCurrentLogs(successIds);
        String nameField = DE_Schema.nameField(obj);
        Boolean traceOn = DE_Settings.decisionTraceEnabled();
        List<DE_Record_Detail__c> detailUpdates = new List<DE_Record_Detail__c>();
        List<DE_Notifier.Item> notes = new List<DE_Notifier.Item>();
        List<DE_Assignment_Event__e> events = new List<DE_Assignment_Event__e>();
        for (DE_Model.Decision d : toWrite) {
            DE_Assignment_Log__c log = baseLog(cfg, d, ctx.logType, now, nameField);
            DE_Record_Detail__c detail = DE_RecordDetails.ensure(ctx.cond.details, d.recordId, obj);
            if (d.status == 'Assigned') {
                result.assigned++;
                log.Status__c = 'Assigned';
                log.Current__c = true;
                DE_Distributor__c dist = d.distributor == null ? null : d.distributor.dist;
                if (dist != null && dist.SLA_Enabled__c == true && !cfg.slas.isEmpty() && d.method != 'Current Owner') {
                    DE_SlaService.Checkpoint next = DE_SlaService.nextCheckpoint(cfg, d.member, now, d.record, 0, detail);
                    if (next != null) {
                        log.SLA_Status__c = 'Pending';
                        log.Next_SLA_Check__c = next.due;
                    }
                }
                DE_RecordDetails.pushAssignee(detail, d.assigneeId);
                detail.Failed_Attempts__c = 0;
                detail.On_Hold_Until__c = null;
                detail.Last_Error__c = null;
                if (dist != null && d.assigneeId.getSobjectType() == User.SObjectType && dist.Send_Notification__c != false) {
                    DE_Notifier.Item n = new DE_Notifier.Item(
                        d.assigneeId,
                        d.recordId,
                        'New ' + obj + ' assigned: ' + log.Record_Name__c,
                        'Assigned to you by ' + cfg.team.Name + ' (' + dist.Name + ').'
                    );
                    n.email = dist.Send_Email__c == true;
                    notes.add(n);
                }
                events.add(
                    new DE_Assignment_Event__e(
                        Record_Id__c = d.recordId,
                        Object_API_Name__c = obj,
                        Record_Name__c = log.Record_Name__c,
                        Assignee_Id__c = d.assigneeId,
                        Team_Name__c = cfg.team.Name.left(80),
                        Event_Type__c = 'Assigned'
                    )
                );
            } else {
                result.errors++;
                result.errorByRecord.put(d.recordId, d.message);
                log.Status__c = 'Error';
                log.Current__c = false;
                log.Message__c = d.message == null ? null : d.message.left(255);
                detail.Failed_Attempts__c = (detail.Failed_Attempts__c == null ? 0 : detail.Failed_Attempts__c) + 1;
                detail.Last_Error__c = d.message == null ? null : d.message.left(255);
            }
            if (traceOn) {
                log.Decision_Trace__c = String.join(d.trace, '\n').left(32000);
            }
            result.logs.add(log);
            detailUpdates.add(detail);
        }
        Database.insert(result.logs, false, AccessLevel.SYSTEM_MODE);
        DE_RecordDetails.save(detailUpdates);
        DE_Notifier.send(notes);
        DE_Notifier.publish(events);
        if (cfg.team.Object_Sync_Enabled__c == true) {
            DE_ObjectSyncService.sync(cfg, toWrite);
        }
        return result;
    }

    public static DE_Assignment_Log__c baseLog(DE_Model.TeamConfig cfg, DE_Model.Decision d, String logType, Datetime now, String nameField) {
        Object name = null;
        try {
            name = d.record.get(nameField);
        } catch (Exception e) {
            name = null;
        }
        Datetime created = null;
        try {
            created = (Datetime) d.record.get('CreatedDate');
        } catch (Exception e) {
            created = null;
        }
        DE_Distributor__c dist = d.distributor == null ? null : d.distributor.dist;
        DE_Assignment_Log__c log = new DE_Assignment_Log__c(
            Record_Id__c = d.recordId,
            Object_API_Name__c = cfg.objectName,
            Record_Name__c = name == null ? String.valueOf(d.recordId) : String.valueOf(name).left(255),
            Team__c = cfg.team.Id,
            Distributor__c = dist == null ? null : dist.Id,
            Assignee_Id__c = d.assigneeId,
            Assigned_User__c = d.assigneeId != null && d.assigneeId.getSobjectType() == User.SObjectType ? d.assigneeId : null,
            Previous_Owner_Id__c = d.previousOwnerId,
            Method__c = d.method,
            Type__c = logType,
            Is_Sticky__c = d.sticky,
            Sticky_Key__c = d.stickyKey,
            Counts_As_Hit__c = d.countsAsHit,
            Assigned_At__c = now,
            Record_Created_At__c = created,
            Speed_To_Assign_Seconds__c = created == null ? null : (now.getTime() - created.getTime()) / 1000,
            Balance_Value__c = d.balanceValue,
            SLA_Status__c = 'Not Applicable',
            Message__c = d.message == null ? null : d.message.left(255)
        );
        return log;
    }

    /** Marks earlier current logs for these records as superseded and cancels their pending SLAs. */
    public static void retireCurrentLogs(Set<String> recordIds) {
        if (recordIds.isEmpty()) {
            return;
        }
        List<DE_Assignment_Log__c> current = [
            SELECT Id, SLA_Status__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c IN :recordIds AND Current__c = TRUE
        ];
        for (DE_Assignment_Log__c l : current) {
            l.Current__c = false;
            l.Next_SLA_Check__c = null;
            if (l.SLA_Status__c == 'Pending') {
                l.SLA_Status__c = 'Cancelled';
            }
        }
        if (!current.isEmpty()) {
            Database.update(current, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
