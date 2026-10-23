/**
 * Trigger distributors: immediate assignment when a record is flagged on update
 * (DE_Trigger_Distribution__c = true) or when the API / Flow action is called.
 * No retry: when no member can be assigned, the first matching distributor's Default Owner is used.
 * Distribution hours are ignored unless the team respects hours for triggers.
 */
public without sharing class DE_TriggerDistribution {
    public class Outcome {
        public Integer assigned = 0;
        public Integer defaulted = 0;
        public Integer failed = 0;
        public Map<Id, String> messageByRecord = new Map<Id, String>();
    }

    public static void beforeUpdate(String objectName, List<SObject> newRecords, Map<Id, SObject> oldMap) {
        if (!DE_Settings.triggerDistributionEnabled() || !DE_Schema.hasField(objectName, 'DE_Trigger_Distribution__c')) {
            return;
        }
        List<SObject> flagged = new List<SObject>();
        for (SObject r : newRecords) {
            if (r.get('DE_Trigger_Distribution__c') == true) {
                flagged.add(r);
            }
        }
        if (flagged.isEmpty()) {
            return;
        }
        run(objectName, flagged, 'Trigger', true);
        Boolean hasTriggered = DE_Schema.hasField(objectName, 'DE_Is_Triggered__c');
        for (SObject r : flagged) {
            r.put('DE_Trigger_Distribution__c', false);
            if (hasTriggered) {
                r.put('DE_Is_Triggered__c', true);
            }
        }
    }

    /** Distributes records through active Trigger distributors in team and distributor order. */
    public static Outcome run(String objectName, List<SObject> records, String logType, Boolean inPlace) {
        Outcome outcome = new Outcome();
        List<DE_Model.TeamConfig> teams = new List<DE_Model.TeamConfig>();
        for (DE_Model.TeamConfig cfg : DE_ConfigRepository.activeTeams(DE_Schema.objectName(objectName))) {
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                if (dc.type() == 'Trigger') {
                    teams.add(cfg);
                    break;
                }
            }
        }
        if (teams.isEmpty() || records.isEmpty()) {
            return outcome;
        }
        DE_DistributionCore.RunContext ctx = new DE_DistributionCore.RunContext(teams, System.now());
        ctx.logType = logType;
        Set<Id> ids = new Map<Id, SObject>(records).keySet();
        Set<String> detailFields = new Set<String>();
        for (DE_Model.TeamConfig cfg : teams) {
            detailFields.addAll(DE_Conditions.detailFields(cfg.teamFilters));
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                detailFields.addAll(DE_Conditions.detailFields(dc.filters));
            }
        }
        ctx.cond.details = DE_RecordDetails.load(ids, detailFields);

        List<SObject> remaining = new List<SObject>(records);
        Map<Id, DE_Model.DistributorConfig> firstMatch = new Map<Id, DE_Model.DistributorConfig>();
        Map<Id, DE_Model.TeamConfig> firstTeam = new Map<Id, DE_Model.TeamConfig>();
        for (DE_Model.TeamConfig cfg : teams) {
            if (remaining.isEmpty()) {
                break;
            }
            if (ctx.availability.holidayFor(cfg) != null) {
                continue;
            }
            DE_TeamLock.lock(cfg);
            ctx.ignoreHours = cfg.team.Respect_Hours_For_Triggers__c != true;
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                if (dc.type() != 'Trigger' || remaining.isEmpty()) {
                    continue;
                }
                List<SObject> subset = new List<SObject>();
                for (SObject r : remaining) {
                    if (DE_DistributionCore.passesFilters(cfg, dc, r, ctx, null)) {
                        subset.add(r);
                        if (!firstMatch.containsKey(r.Id)) {
                            firstMatch.put(r.Id, dc);
                            firstTeam.put(r.Id, cfg);
                        }
                    }
                }
                if (subset.isEmpty()) {
                    continue;
                }
                List<DE_Model.Decision> decisions = DE_DistributionCore.distribute(cfg, dc, subset, ctx);
                DE_AssignmentWriter.Result res = DE_AssignmentWriter.persist(cfg, decisions, ctx, inPlace);
                outcome.assigned += res.assigned;
                Set<Id> done = new Set<Id>();
                for (DE_Model.Decision d : decisions) {
                    if (d.status == 'Assigned') {
                        done.add(d.recordId);
                    } else if (d.status == 'Unassigned') {
                        outcome.messageByRecord.put(d.recordId, d.message);
                    }
                }
                List<SObject> next = new List<SObject>();
                for (SObject r : remaining) {
                    if (!done.contains(r.Id)) {
                        next.add(r);
                    }
                }
                remaining = next;
            }
            ctx.servicesFor(cfg).rotation.save();
        }
        applyDefaults(remaining, firstMatch, firstTeam, ctx, inPlace, outcome);
        return outcome;
    }

    private static void applyDefaults(
        List<SObject> remaining,
        Map<Id, DE_Model.DistributorConfig> firstMatch,
        Map<Id, DE_Model.TeamConfig> firstTeam,
        DE_DistributionCore.RunContext ctx,
        Boolean inPlace,
        Outcome outcome
    ) {
        Map<Id, List<DE_Model.Decision>> defaultsByTeam = new Map<Id, List<DE_Model.Decision>>();
        Map<Id, DE_Model.TeamConfig> teamById = new Map<Id, DE_Model.TeamConfig>();
        List<DE_Assignment_Log__c> errors = new List<DE_Assignment_Log__c>();
        for (SObject r : remaining) {
            DE_Model.DistributorConfig dc = firstMatch.get(r.Id);
            DE_Model.TeamConfig cfg = firstTeam.get(r.Id);
            Id fallback = dc == null ? null : DE_Ids.toId(dc.dist.Default_Owner_Id__c);
            if (fallback != null) {
                DE_Model.Decision d = new DE_Model.Decision(r);
                d.distributor = dc;
                d.assigneeId = fallback;
                d.previousOwnerId = (Id) r.get(cfg.assignmentField);
                d.method = 'Default Owner';
                d.countsAsHit = false;
                d.trace.add('No trigger distributor could assign; default owner used.');
                if (!defaultsByTeam.containsKey(cfg.team.Id)) {
                    defaultsByTeam.put(cfg.team.Id, new List<DE_Model.Decision>());
                    teamById.put(cfg.team.Id, cfg);
                }
                defaultsByTeam.get(cfg.team.Id).add(d);
                continue;
            }
            outcome.failed++;
            String msg = outcome.messageByRecord.containsKey(r.Id) ? outcome.messageByRecord.get(r.Id) : 'No trigger distributor matched this record';
            errors.add(
                new DE_Assignment_Log__c(
                    Record_Id__c = r.Id,
                    Object_API_Name__c = r.getSObjectType().getDescribe().getName(),
                    Team__c = cfg == null ? null : cfg.team.Id,
                    Distributor__c = dc == null ? null : dc.dist.Id,
                    Type__c = ctx.logType,
                    Status__c = 'Error',
                    Current__c = false,
                    Assigned_At__c = ctx.now,
                    Message__c = ('No trigger distributor could assign this record: ' + msg).left(255)
                )
            );
        }
        for (Id teamId : defaultsByTeam.keySet()) {
            DE_AssignmentWriter.Result res = DE_AssignmentWriter.persist(teamById.get(teamId), defaultsByTeam.get(teamId), ctx, inPlace);
            outcome.defaulted += res.assigned;
        }
        if (!errors.isEmpty() && !ctx.dryRun) {
            Database.insert(errors, false, AccessLevel.SYSTEM_MODE);
        }
    }

    /** Flow/Apex entry point outside a trigger: loads the records, distributes and saves them. */
    public static Outcome distributeIds(Set<Id> recordIds, String logType) {
        Outcome total = new Outcome();
        Map<String, Set<Id>> byObject = new Map<String, Set<Id>>();
        for (Id i : recordIds) {
            String o = i.getSobjectType().getDescribe().getName();
            if (!byObject.containsKey(o)) {
                byObject.put(o, new Set<Id>());
            }
            byObject.get(o).add(i);
        }
        for (String obj : byObject.keySet()) {
            Set<String> paths = new Set<String>{ 'Id' };
            for (DE_Model.TeamConfig cfg : DE_ConfigRepository.activeTeams(obj)) {
                paths.addAll(DE_RecordQuery.requiredPaths(cfg, null));
            }
            if (paths.size() == 1) {
                continue;
            }
            List<SObject> records = DE_RecordQuery.byIds(obj, paths, byObject.get(obj), new List<String>());
            Outcome o = run(obj, records, logType, false);
            total.assigned += o.assigned;
            total.defaulted += o.defaulted;
            total.failed += o.failed;
            total.messageByRecord.putAll(o.messageByRecord);
        }
        return total;
    }
}
