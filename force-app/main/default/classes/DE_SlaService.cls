/**
 * Distribution SLAs and auto reassign.
 *
 * A team has up to three checkpoints. Each checkpoint fires at a time after assignment
 * (Time Checkpoint, in working minutes per the team's SLA hours setting), at a record date/time
 * (Custom Date/Time), or continuously for a window (Continuous Field Monitoring). When a checkpoint
 * is due and its "SLA missed if" conditions are true, the SLA is missed: the log is marked
 * SLA Alert, the assignee (and optionally manager) is notified, and when the distributor has auto
 * reassign from that checkpoint, the record is taken away and reassigned.
 *
 * SLAs only apply while the record is still owned by the assignee and (optionally) in Active Status.
 */
public without sharing class DE_SlaService {
    public class Checkpoint {
        public DE_SLA__c sla;
        public Datetime due;
        public Checkpoint(DE_SLA__c sla, Datetime due) {
            this.sla = sla;
            this.due = due;
        }
    }

    public class MonitorSummary {
        public Integer checked = 0;
        public Integer missed = 0;
        public Integer reassigned = 0;
        public Integer cancelled = 0;
        public List<String> messages = new List<String>();
    }

    private static Boolean stampApplies(DE_SLA__c s, DE_Record_Detail__c detail) {
        if (String.isBlank(s.Stamp_Value__c)) {
            return true;
        }
        if (detail == null || String.isBlank(detail.Stamps__c)) {
            return false;
        }
        for (String st : detail.Stamps__c.split(';')) {
            if (st.trim().equalsIgnoreCase(s.Stamp_Value__c.trim())) {
                return true;
            }
        }
        return false;
    }

    /** Due time of one checkpoint for an assignment, or null when it cannot be computed. */
    public static Datetime dueTime(DE_Model.TeamConfig cfg, DE_Model.Member member, DE_SLA__c s, Datetime assignedAt, SObject rec) {
        String type = s.Alert_Type__c == null ? 'Time Checkpoint' : s.Alert_Type__c;
        if (type == 'Custom Date/Time') {
            if (rec == null || String.isBlank(s.Check_After_Field__c)) {
                return null;
            }
            try {
                Object v = DE_Conditions.readPath(rec, s.Check_After_Field__c);
                return v instanceof Datetime ? (Datetime) v : (v instanceof Date ? Datetime.newInstance((Date) v, Time.newInstance(0, 0, 0, 0)) : null);
            } catch (Exception e) {
                return null;
            }
        }
        if (type == 'Continuous Field Monitoring') {
            return assignedAt;
        }
        Decimal minutes = s.Minutes_After_Assignment__c == null ? 0 : s.Minutes_After_Assignment__c;
        DE_ShiftCalendar cal = DE_AvailabilityService.timingCalendar(cfg, member, cfg.team.SLA_Respect_Hours__c, assignedAt);
        return cal == null ? assignedAt.addMinutes(minutes.intValue()) : cal.addWorkingMinutes(assignedAt, minutes);
    }

    /** The next applicable checkpoint after the given checkpoint number. */
    public static Checkpoint nextCheckpoint(
        DE_Model.TeamConfig cfg,
        DE_Model.Member member,
        Datetime assignedAt,
        SObject rec,
        Integer after,
        DE_Record_Detail__c detail
    ) {
        for (DE_SLA__c s : cfg.slas) {
            if (s.Checkpoint__c == null || s.Checkpoint__c.intValue() <= after || !stampApplies(s, detail)) {
                continue;
            }
            Datetime due = dueTime(cfg, member, s, assignedAt, rec);
            if (due != null) {
                return new Checkpoint(s, due);
            }
        }
        return null;
    }

    // ------------------------------------------------------------------ monitor

    public static MonitorSummary monitor(Integer maxLogs, Datetime now) {
        MonitorSummary summary = new MonitorSummary();
        List<DE_Assignment_Log__c> due = [
            SELECT
                Id,
                Record_Id__c,
                Object_API_Name__c,
                Record_Name__c,
                Team__c,
                Distributor__c,
                Assignee_Id__c,
                Assigned_User__c,
                Assigned_At__c,
                Last_SLA_Checkpoint__c,
                SLA_Missed__c,
                SLA_Status__c,
                Status__c,
                Sticky_Key__c,
                Current__c,
                Message__c
            FROM DE_Assignment_Log__c
            WHERE Current__c = TRUE AND SLA_Status__c = 'Pending' AND Next_SLA_Check__c <= :now
            ORDER BY Next_SLA_Check__c
            LIMIT :maxLogs
        ];
        if (due.isEmpty()) {
            return summary;
        }
        Set<Id> teamIds = new Set<Id>();
        for (DE_Assignment_Log__c l : due) {
            teamIds.add(l.Team__c);
        }
        Map<Id, DE_Model.TeamConfig> teams = new Map<Id, DE_Model.TeamConfig>();
        for (DE_Model.TeamConfig cfg : DE_ConfigRepository.load(teamIds, null, true)) {
            teams.put(cfg.team.Id, cfg);
        }
        Map<Id, List<DE_Assignment_Log__c>> byTeam = new Map<Id, List<DE_Assignment_Log__c>>();
        for (DE_Assignment_Log__c l : due) {
            if (!byTeam.containsKey(l.Team__c)) {
                byTeam.put(l.Team__c, new List<DE_Assignment_Log__c>());
            }
            byTeam.get(l.Team__c).add(l);
        }
        List<DE_Assignment_Log__c> logUpdates = new List<DE_Assignment_Log__c>();
        List<DE_Notifier.Item> notes = new List<DE_Notifier.Item>();
        for (Id teamId : byTeam.keySet()) {
            DE_Model.TeamConfig cfg = teams.get(teamId);
            List<DE_Assignment_Log__c> logs = byTeam.get(teamId);
            if (cfg == null) {
                for (DE_Assignment_Log__c l : logs) {
                    cancel(l, 'Team no longer exists', logUpdates, summary);
                }
                continue;
            }
            processTeam(cfg, logs, now, logUpdates, notes, summary);
        }
        Database.update(logUpdates, false, AccessLevel.SYSTEM_MODE);
        DE_Notifier.send(notes);
        return summary;
    }

    private static void cancel(DE_Assignment_Log__c l, String why, List<DE_Assignment_Log__c> updates, MonitorSummary summary) {
        l.SLA_Status__c = 'Cancelled';
        l.Next_SLA_Check__c = null;
        l.Message__c = why;
        updates.add(l);
        summary.cancelled++;
    }

    private static void processTeam(
        DE_Model.TeamConfig cfg,
        List<DE_Assignment_Log__c> logs,
        Datetime now,
        List<DE_Assignment_Log__c> logUpdates,
        List<DE_Notifier.Item> notes,
        MonitorSummary summary
    ) {
        Set<Id> recordIds = new Set<Id>();
        for (DE_Assignment_Log__c l : logs) {
            recordIds.add(Id.valueOf(l.Record_Id__c));
        }
        Set<String> paths = DE_RecordQuery.requiredPaths(cfg, null);
        List<String> warnings = new List<String>();
        Map<Id, SObject> records = new Map<Id, SObject>(DE_RecordQuery.byIds(cfg.objectName, paths, recordIds, warnings));
        Set<String> detailFields = new Set<String>();
        for (List<DE_Condition__c> conds : cfg.slaConditions.values()) {
            detailFields.addAll(DE_Conditions.detailFields(conds));
        }
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.now = now;
        ctx.details = DE_RecordDetails.load(recordIds, detailFields);
        Set<Id> managerLookup = new Set<Id>();
        for (DE_Assignment_Log__c l : logs) {
            if (l.Assigned_User__c != null) {
                managerLookup.add(l.Assigned_User__c);
            }
        }
        Map<Id, User> users = new Map<Id, User>([SELECT Id, ManagerId FROM User WHERE Id IN :managerLookup]);
        List<ReassignRequest> reassignments = new List<ReassignRequest>();

        for (DE_Assignment_Log__c l : logs) {
            summary.checked++;
            SObject rec = records.get(Id.valueOf(l.Record_Id__c));
            if (rec == null) {
                cancel(l, 'Record no longer exists', logUpdates, summary);
                continue;
            }
            if (String.valueOf(rec.get(cfg.assignmentField)) != l.Assignee_Id__c) {
                cancel(l, 'Owner changed after assignment', logUpdates, summary);
                continue;
            }
            if (cfg.team.Apply_Active_Status_To_SLAs__c == true && String.isNotBlank(cfg.team.Active_Status_Field__c) && !cfg.activeStatusValues.isEmpty()) {
                Object status = DE_Conditions.readPath(rec, cfg.team.Active_Status_Field__c);
                if (status == null || !cfg.activeStatusValues.contains(String.valueOf(status).toLowerCase())) {
                    l.SLA_Status__c = l.SLA_Missed__c > 0 ? 'Missed' : 'Met';
                    l.Next_SLA_Check__c = null;
                    logUpdates.add(l);
                    continue;
                }
            }
            DE_Model.Member member = cfg.member(DE_Ids.toId(l.Assignee_Id__c));
            DE_Model.DistributorConfig dc = cfg.distributor(l.Distributor__c);
            Integer last = l.Last_SLA_Checkpoint__c == null ? 0 : l.Last_SLA_Checkpoint__c.intValue();
            DE_Record_Detail__c detail = ctx.details.get(rec.Id);
            Boolean done = false;
            Boolean reassigning = false;
            while (!done) {
                Checkpoint cp = nextCheckpoint(cfg, member, l.Assigned_At__c, rec, last, detail);
                if (cp == null) {
                    l.Next_SLA_Check__c = null;
                    l.SLA_Status__c = l.SLA_Missed__c > 0 ? 'Missed' : 'Met';
                    done = true;
                    continue;
                }
                if (cp.due > now) {
                    l.Next_SLA_Check__c = cp.due;
                    done = true;
                    continue;
                }
                List<DE_Condition__c> conds = cfg.slaConditions.get(cp.sla.Id);
                Boolean conditionTrue = conds == null || conds.isEmpty() || DE_Conditions.matches(rec, conds, cp.sla.Condition_Logic__c, ctx, null);
                if (cp.sla.Alert_Type__c == 'Continuous Field Monitoring' && !conditionTrue) {
                    Datetime windowEnd = l.Assigned_At__c.addMinutes(
                        cp.sla.Minutes_After_Assignment__c == null ? 0 : cp.sla.Minutes_After_Assignment__c.intValue()
                    );
                    if (now < windowEnd) {
                        l.Next_SLA_Check__c = now.addMinutes(DE_Settings.schedulerIntervalMinutes());
                        done = true;
                        continue;
                    }
                }
                last = cp.sla.Checkpoint__c.intValue();
                l.Last_SLA_Checkpoint__c = last;
                if (!conditionTrue) {
                    continue;
                }
                summary.missed++;
                l.SLA_Missed__c = (l.SLA_Missed__c == null ? 0 : l.SLA_Missed__c) + 1;
                l.Status__c = 'SLA Alert';
                String what = 'SLA ' + last + ' (' + cp.sla.Name + ') missed for ' + cfg.objectName + ' ' + l.Record_Name__c;
                if (cp.sla.Notify_Assignee__c != false && l.Assigned_User__c != null) {
                    notes.add(new DE_Notifier.Item(l.Assigned_User__c, rec.Id, what, 'Please action this record now.'));
                }
                User u = users.get(l.Assigned_User__c);
                if (cp.sla.Notify_Manager__c == true && u != null && u.ManagerId != null) {
                    notes.add(new DE_Notifier.Item(u.ManagerId, rec.Id, what, 'Assigned to a member of your team through ' + cfg.team.Name + '.'));
                }
                if (
                    dc != null &&
                    dc.dist.Auto_Reassign__c == true &&
                    last >= (dc.dist.Reassign_From_SLA__c == null ? 1 : dc.dist.Reassign_From_SLA__c.intValue())
                ) {
                    reassignments.add(new ReassignRequest(l, rec, dc));
                    reassigning = true;
                    done = true;
                }
            }
            if (!reassigning) {
                logUpdates.add(l);
            }
        }
        if (!reassignments.isEmpty()) {
            summary.reassigned += reassign(cfg, reassignments, now, ctx.details, logUpdates, summary.messages);
        }
    }

    public class ReassignRequest {
        public DE_Assignment_Log__c log;
        public SObject record;
        public DE_Model.DistributorConfig dc;
        public ReassignRequest(DE_Assignment_Log__c log, SObject record, DE_Model.DistributorConfig dc) {
            this.log = log;
            this.record = record;
            this.dc = dc;
        }
    }

    /** Auto reassign after a missed SLA. Returns the number of records reassigned. */
    public static Integer reassign(
        DE_Model.TeamConfig cfg,
        List<ReassignRequest> requests,
        Datetime now,
        Map<Id, DE_Record_Detail__c> details,
        List<DE_Assignment_Log__c> logUpdates,
        List<String> messages
    ) {
        String obj = cfg.objectName;
        Schema.SObjectType sType = DE_Schema.sobjectType(obj);
        List<SObject> targets = new List<SObject>();
        Set<Id> toggleOff = new Set<Id>();
        for (ReassignRequest r : requests) {
            SObject t = sType.newSObject(r.record.Id);
            t.put(cfg.assignmentField, DE_Ids.toId(r.dc.dist.Reassign_To_Id__c));
            if (DE_Schema.hasField(obj, 'DE_Is_Reassigned__c')) {
                t.put('DE_Is_Reassigned__c', true);
            }
            if (DE_Schema.hasField(obj, 'DE_Last_Reassigned__c')) {
                t.put('DE_Last_Reassigned__c', now);
            }
            DE_FieldUpdates.apply(t, obj, r.dc.dist.Reassign_Field_Updates__c, messages);
            targets.add(t);
            if (r.dc.dist.Toggle_User_Off__c == true && r.log.Assigned_User__c != null) {
                toggleOff.add(r.log.Assigned_User__c);
            }
        }
        Boolean previous = DE_TriggerHandler.bypass;
        DE_TriggerHandler.bypass = true;
        List<Database.SaveResult> saves;
        try {
            saves = Database.update(targets, false, AccessLevel.SYSTEM_MODE);
        } finally {
            DE_TriggerHandler.bypass = previous;
        }
        Integer ok = 0;
        List<DE_Assignment_Log__c> newLogs = new List<DE_Assignment_Log__c>();
        List<DE_Record_Detail__c> detailUpdates = new List<DE_Record_Detail__c>();
        Map<String, List<DE_Assignment_Log__c>> stickyByMode = new Map<String, List<DE_Assignment_Log__c>>();
        List<DE_Notifier.Item> notes = new List<DE_Notifier.Item>();
        for (Integer i = 0; i < saves.size(); i++) {
            ReassignRequest r = requests[i];
            if (!saves[i].isSuccess()) {
                r.log.Message__c = ('Reassignment failed: ' + saves[i].getErrors()[0].getMessage()).left(255);
                logUpdates.add(r.log);
                messages.add(r.log.Message__c);
                continue;
            }
            ok++;
            r.log.Status__c = 'Reassigned';
            r.log.Current__c = false;
            r.log.SLA_Status__c = 'Missed';
            r.log.Next_SLA_Check__c = null;
            String mode = r.dc.dist.Remove_Sticky_On_Reassign__c == null ? 'New Sticky Only' : r.dc.dist.Remove_Sticky_On_Reassign__c;
            if (!stickyByMode.containsKey(mode)) {
                stickyByMode.put(mode, new List<DE_Assignment_Log__c>());
            }
            stickyByMode.get(mode).add(r.log);
            logUpdates.add(r.log);
            DE_Record_Detail__c d = DE_RecordDetails.ensure(details, r.record.Id, obj);
            DE_RecordDetails.pushAssignee(d, DE_Ids.toId(r.log.Assignee_Id__c));
            detailUpdates.add(d);
            Id target = DE_Ids.toId(r.dc.dist.Reassign_To_Id__c);
            if (DE_Ids.isUser(target)) {
                newLogs.add(
                    new DE_Assignment_Log__c(
                        Record_Id__c = r.record.Id,
                        Object_API_Name__c = obj,
                        Record_Name__c = r.log.Record_Name__c,
                        Team__c = cfg.team.Id,
                        Distributor__c = r.dc.dist.Id,
                        Assignee_Id__c = target,
                        Assigned_User__c = target,
                        Previous_Owner_Id__c = r.log.Assignee_Id__c,
                        Method__c = 'Reassignment',
                        Type__c = 'Reassignment',
                        Status__c = 'Assigned',
                        Counts_As_Hit__c = false,
                        Current__c = true,
                        Assigned_At__c = now,
                        SLA_Status__c = 'Not Applicable'
                    )
                );
                notes.add(new DE_Notifier.Item(target, r.record.Id, 'Reassigned to you: ' + r.log.Record_Name__c, 'Reassigned after a missed SLA.'));
            }
            if (r.log.Assigned_User__c != null) {
                notes.add(
                    new DE_Notifier.Item(
                        r.log.Assigned_User__c,
                        r.record.Id,
                        'Record reassigned: ' + r.log.Record_Name__c,
                        'This record was taken back because its SLA was missed.'
                    )
                );
            }
        }
        for (String mode : stickyByMode.keySet()) {
            DE_StickyService.remove(stickyByMode.get(mode), mode);
        }
        Database.insert(newLogs, false, AccessLevel.SYSTEM_MODE);
        DE_RecordDetails.save(detailUpdates);
        if (!toggleOff.isEmpty()) {
            DE_AgentService.setOnline(toggleOff, false, 'Missed SLA', null, 'Auto Reassign');
        }
        DE_Notifier.send(notes);
        return ok;
    }
}
