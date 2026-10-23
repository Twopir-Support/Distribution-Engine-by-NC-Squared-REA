/**
 * Persists assignment decisions: updates the records (or the Trigger.new rows in place),
 * writes Distribution Logs, updates per-record details, sends notifications and platform events,
 * and runs Object Sync. Record DML is partial-success: one failing record never blocks the others.
 *
 * Role assignment distributors add the assignee to the record's Account/Opportunity/Case team
 * (DE_SalesforceTeamService) instead of changing the owner. Standard emails are sent by the
 * "DE Email Notification" flows from the log's Send_Email__c flag.
 *
 * When the team has Distribution Logging Disabled, no logs are written. Rotation state is kept,
 * but caps, load balancing and sticky assignment count logs, so they see no assignments from
 * that team (a validation rule stops logging being disabled together with action tracking or object sync).
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
            if (d.method != 'Current Owner' && !isRoleAssignment(d)) {
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

        // 2. Role assignment: add the assignee to the record's team instead of changing the owner.
        Map<Id, DE_SalesforceTeamService.Result> roles = addTeamMembers(obj, toWrite);

        // 3. Logs.
        Set<String> successIds = new Set<String>();
        for (DE_Model.Decision d : toWrite) {
            if (d.status == 'Assigned' && !isRoleAssignment(d)) {
                successIds.add(String.valueOf(d.recordId));
            }
        }
        retireCurrentLogs(successIds);
        String nameField = DE_Schema.nameField(obj);
        Boolean traceOn = DE_Settings.decisionTraceEnabled();
        Map<Id, String> names = assigneeNames(toWrite);
        List<DE_Record_Detail__c> detailUpdates = new List<DE_Record_Detail__c>();
        List<DE_Notifier.Item> notes = new List<DE_Notifier.Item>();
        List<DE_Assignment_Event__e> events = new List<DE_Assignment_Event__e>();
        for (DE_Model.Decision d : toWrite) {
            DE_Assignment_Log__c log = baseLog(cfg, d, ctx.logType, now, nameField);
            log.Assignee_Name__c = names.get(d.assigneeId);
            DE_Record_Detail__c detail = DE_RecordDetails.ensure(ctx.cond.details, d.recordId, obj);
            DE_SalesforceTeamService.Result role = roles.get(d.recordId);
            if (role != null) {
                log.Team_Role__c = role.role == null ? null : role.role.left(80);
                log.Team_Member_Record_Id__c = role.teamMemberId;
            }
            if (d.status == 'Assigned') {
                result.assigned++;
                log.Status__c = 'Assigned';
                // Role assignments do not change the owner, so they never become the record's current assignment.
                log.Current__c = role == null;
                DE_Distributor__c dist = d.distributor == null ? null : d.distributor.dist;
                if (dist != null && role == null && dist.SLA_Enabled__c == true && !cfg.slas.isEmpty() && d.method != 'Current Owner') {
                    DE_SlaService.Checkpoint next = DE_SlaService.nextCheckpoint(cfg, d.member, now, d.record, 0, detail);
                    if (next != null) {
                        log.SLA_Status__c = 'Pending';
                        log.Next_SLA_Check__c = next.due;
                    }
                }
                if (role == null) {
                    DE_RecordDetails.pushAssignee(detail, d.assigneeId);
                }
                detail.Failed_Attempts__c = 0;
                detail.On_Hold_Until__c = null;
                detail.Last_Error__c = null;
                if (dist != null && d.assigneeId.getSobjectType() == User.SObjectType && dist.Send_Notification__c != false) {
                    notes.add(
                        new DE_Notifier.Item(
                            d.assigneeId,
                            d.recordId,
                            (role == null ? 'New ' + obj + ' assigned: ' : 'Added to the ' + obj + ' team: ') + log.Record_Name__c,
                            'Assigned to you by ' + cfg.team.Name + ' (' + dist.Name + ').'
                        )
                    );
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
        if (cfg.team.Logging_Disabled__c != true) {
            Database.insert(result.logs, false, AccessLevel.SYSTEM_MODE);
        }
        DE_RecordDetails.save(detailUpdates);
        DE_Notifier.send(notes);
        DE_Notifier.publish(events);
        if (cfg.team.Object_Sync_Enabled__c == true) {
            List<DE_Model.Decision> owned = new List<DE_Model.Decision>();
            for (DE_Model.Decision d : toWrite) {
                if (!isRoleAssignment(d)) {
                    owned.add(d);
                }
            }
            DE_ObjectSyncService.sync(cfg, owned);
        }
        return result;
    }

    public static Boolean isRoleAssignment(DE_Model.Decision d) {
        return d.distributor != null && d.distributor.dist.Salesforce_Team_Enabled__c == true;
    }

    /** Runs role assignment for the successful role-assignment decisions; failures turn the decision into an error. */
    private static Map<Id, DE_SalesforceTeamService.Result> addTeamMembers(String obj, List<DE_Model.Decision> decisions) {
        Map<Id, DE_SalesforceTeamService.Result> out = new Map<Id, DE_SalesforceTeamService.Result>();
        Map<Id, List<DE_Model.Decision>> byDistributor = new Map<Id, List<DE_Model.Decision>>();
        Map<Id, DE_Model.DistributorConfig> configs = new Map<Id, DE_Model.DistributorConfig>();
        for (DE_Model.Decision d : decisions) {
            if (d.status != 'Assigned' || !isRoleAssignment(d)) {
                continue;
            }
            Id key = d.distributor.dist.Id;
            if (!byDistributor.containsKey(key)) {
                byDistributor.put(key, new List<DE_Model.Decision>());
                configs.put(key, d.distributor);
            }
            byDistributor.get(key).add(d);
        }
        for (Id key : byDistributor.keySet()) {
            out.putAll(DE_SalesforceTeamService.addMembers(obj, configs.get(key), byDistributor.get(key)));
        }
        for (DE_Model.Decision d : decisions) {
            DE_SalesforceTeamService.Result r = out.get(d.recordId);
            if (r != null && r.error != null) {
                d.status = 'Error';
                d.message = r.error;
                d.trace.add('Role assignment failed: ' + r.error);
            }
        }
        return out;
    }

    /** Display names of user and queue assignees. */
    public static Map<Id, String> assigneeNames(List<DE_Model.Decision> decisions) {
        Map<Id, String> out = new Map<Id, String>();
        Set<Id> users = new Set<Id>();
        Set<Id> queues = new Set<Id>();
        for (DE_Model.Decision d : decisions) {
            if (d.assigneeId == null) {
                continue;
            }
            if (d.member != null && d.member.user != null) {
                out.put(d.assigneeId, d.member.user.Name);
            } else if (d.assigneeId.getSobjectType() == User.SObjectType) {
                users.add(d.assigneeId);
            } else {
                queues.add(d.assigneeId);
            }
        }
        out.putAll(namesOf(users, queues));
        return out;
    }

    public static Map<Id, String> namesOf(Set<Id> users, Set<Id> queues) {
        Map<Id, String> out = new Map<Id, String>();
        if (!users.isEmpty()) {
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :users]) {
                out.put(u.Id, u.Name);
            }
        }
        if (!queues.isEmpty()) {
            for (Group g : [SELECT Id, Name FROM Group WHERE Id IN :queues]) {
                out.put(g.Id, g.Name);
            }
        }
        return out;
    }

    /** Sets the log's lookup to the routed record (Lead__c, Case__c, Contact__c, Account__c or Opportunity__c). */
    public static void linkRecord(DE_Assignment_Log__c log, String objectName, Id recordId) {
        String field = RECORD_LOOKUPS.get(objectName == null ? '' : objectName.toLowerCase());
        if (field != null && recordId != null) {
            log.put(field, recordId);
        }
    }

    private static final Map<String, String> RECORD_LOOKUPS = new Map<String, String>{
        'lead' => 'Lead__c',
        'case' => 'Case__c',
        'contact' => 'Contact__c',
        'account' => 'Account__c',
        'opportunity' => 'Opportunity__c'
    };

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
            Send_Email__c = dist != null && dist.Send_Email__c == true && cfg.team.Logging_Disabled__c != true,
            Message__c = d.message == null ? null : d.message.left(255)
        );
        linkRecord(log, cfg.objectName, d.recordId);
        if (String.isNotBlank(cfg.team.Active_Status_Field__c)) {
            try {
                Object status = DE_Conditions.readPath(d.record, cfg.team.Active_Status_Field__c);
                log.Status_On_Assignment__c = status == null ? null : String.valueOf(status).left(255);
            } catch (Exception e) {
                log.Status_On_Assignment__c = null;
            }
        }
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
