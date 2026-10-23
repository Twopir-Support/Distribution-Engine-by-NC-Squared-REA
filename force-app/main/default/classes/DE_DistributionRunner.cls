/**
 * Runs Standard distributors: for each active team (execution order) and each active Standard
 * distributor (order), takes records waiting at the source, applies filters and assigns them.
 * Records that pass filters but cannot be assigned stay at the source (overflow to later
 * distributors/teams) and are retried on the next run; after repeated failures they are put on hold.
 */
public without sharing class DE_DistributionRunner {
    public class Summary {
        public Integer processed = 0;
        public Integer assigned = 0;
        public Integer errors = 0;
        public Integer onHold = 0;
        public Id resumeAfterTeamId;
        public List<String> messages = new List<String>();
    }

    /**
     * @param onlyRecordIds limit to these records (null = everything waiting at sources)
     * @param resumeAfterTeamId skip teams up to and including this one (continuation after a limit stop)
     */
    public static Summary runStandard(Set<Id> onlyRecordIds, Id resumeAfterTeamId) {
        Summary summary = new Summary();
        List<DE_Model.TeamConfig> teams = new List<DE_Model.TeamConfig>();
        for (DE_Model.TeamConfig cfg : DE_ConfigRepository.activeTeams(null)) {
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                if (dc.type() == 'Standard') {
                    teams.add(cfg);
                    break;
                }
            }
        }
        if (teams.isEmpty()) {
            return summary;
        }
        Set<String> onlyObjects = new Set<String>();
        if (onlyRecordIds != null) {
            for (Id i : onlyRecordIds) {
                onlyObjects.add(i.getSobjectType().getDescribe().getName().toLowerCase());
            }
        }
        DE_DistributionCore.RunContext ctx = new DE_DistributionCore.RunContext(teams, System.now());
        ctx.logType = 'Standard';
        Integer budget = DE_Settings.recordsPerRun();
        Set<Id> assignedIds = new Set<Id>();
        Map<Id, String> unassignedReason = new Map<Id, String>();
        Map<Id, String> unassignedObject = new Map<Id, String>();
        Boolean skipping = resumeAfterTeamId != null;

        for (DE_Model.TeamConfig cfg : teams) {
            if (skipping) {
                skipping = cfg.team.Id != resumeAfterTeamId;
                continue;
            }
            if (onlyRecordIds != null && !onlyObjects.contains(cfg.objectName.toLowerCase())) {
                continue;
            }
            if (budget <= 0) {
                break;
            }
            if (Limits.getQueries() > Limits.getLimitQueries() * 0.7 || Limits.getDmlStatements() > Limits.getLimitDmlStatements() * 0.7) {
                summary.resumeAfterTeamId = previousTeamId(teams, cfg);
                summary.messages.add('Stopped before team ' + cfg.team.Name + ' to stay within limits; the next run continues from here.');
                break;
            }
            String holiday = ctx.availability.holidayFor(cfg);
            if (holiday != null) {
                summary.messages.add(cfg.team.Name + ': skipped for holiday ' + holiday + '.');
                continue;
            }
            try {
                DE_TeamLock.lock(cfg);
            } catch (DE_TeamLock.LockException e) {
                summary.messages.add(e.getMessage());
                continue;
            }
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                if (dc.type() != 'Standard' || budget <= 0) {
                    continue;
                }
                List<String> warnings = new List<String>();
                List<SObject> candidates;
                try {
                    candidates = candidatesFor(cfg, dc, onlyRecordIds, budget, warnings);
                } catch (Exception e) {
                    summary.errors++;
                    summary.messages.add(cfg.team.Name + ' / ' + dc.dist.Name + ': ' + e.getMessage());
                    continue;
                }
                summary.messages.addAll(warnings);
                List<SObject> ready = new List<SObject>();
                Set<Id> candidateIds = new Set<Id>();
                for (SObject r : candidates) {
                    if (!assignedIds.contains(r.Id)) {
                        candidateIds.add(r.Id);
                    }
                }
                Set<String> detailFields = DE_Conditions.detailFields(cfg.teamFilters);
                detailFields.addAll(DE_Conditions.detailFields(dc.filters));
                Map<Id, DE_Record_Detail__c> loaded = DE_RecordDetails.load(candidateIds, detailFields);
                ctx.cond.details.putAll(loaded);
                DE_DistributionCore.preloadCampaigns(dc, candidates, ctx);
                for (SObject r : candidates) {
                    if (ready.size() >= budget) {
                        break;
                    }
                    if (assignedIds.contains(r.Id)) {
                        continue;
                    }
                    DE_Record_Detail__c d = ctx.cond.details.get(r.Id);
                    if (DE_RecordDetails.isWaiting(d, (Datetime) r.get('CreatedDate'), ctx.now) || DE_RecordDetails.isOnHold(d, ctx.now)) {
                        continue;
                    }
                    if (DE_DistributionCore.passesFilters(cfg, dc, r, ctx, null)) {
                        ready.add(r);
                    }
                }
                if (ready.isEmpty()) {
                    continue;
                }
                List<DE_Model.Decision> decisions = DE_DistributionCore.distribute(cfg, dc, ready, ctx);
                DE_AssignmentWriter.Result res = DE_AssignmentWriter.persist(cfg, decisions, ctx, false);
                summary.processed += ready.size();
                summary.assigned += res.assigned;
                summary.errors += res.errors;
                budget -= ready.size();
                for (DE_Model.Decision d : decisions) {
                    if (d.status == 'Assigned') {
                        assignedIds.add(d.recordId);
                        unassignedReason.remove(d.recordId);
                    } else if (d.status == 'Unassigned' && !assignedIds.contains(d.recordId)) {
                        unassignedReason.put(d.recordId, cfg.team.Name + ' / ' + dc.dist.Name + ': ' + d.message);
                        unassignedObject.put(d.recordId, cfg.objectName);
                    }
                }
            }
            ctx.servicesFor(cfg).rotation.save();
        }
        summary.onHold = recordFailures(unassignedReason, unassignedObject, ctx);
        summary.messages.addAll(ctx.warnings);
        return summary;
    }

    private static Id previousTeamId(List<DE_Model.TeamConfig> teams, DE_Model.TeamConfig current) {
        Id prev = null;
        for (DE_Model.TeamConfig t : teams) {
            if (t.team.Id == current.team.Id) {
                return prev;
            }
            prev = t.team.Id;
        }
        return prev;
    }

    private static List<SObject> candidatesFor(
        DE_Model.TeamConfig cfg,
        DE_Model.DistributorConfig dc,
        Set<Id> onlyRecordIds,
        Integer budget,
        List<String> warnings
    ) {
        if (onlyRecordIds == null) {
            return DE_RecordQuery.sourceCandidates(cfg, dc, budget * 4, warnings);
        }
        List<SObject> out = new List<SObject>();
        Set<Id> ids = new Set<Id>();
        for (Id i : onlyRecordIds) {
            if (i.getSobjectType().getDescribe().getName().equalsIgnoreCase(cfg.objectName)) {
                ids.add(i);
            }
        }
        for (SObject r : DE_RecordQuery.byIds(cfg.objectName, DE_RecordQuery.requiredPaths(cfg, dc), ids, warnings)) {
            if (atSource(cfg, dc, r)) {
                out.add(r);
            }
        }
        return out;
    }

    public static Boolean atSource(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, SObject r) {
        if (dc.dist.Source_Type__c == 'Field Value') {
            Object v = DE_Conditions.readPath(r, dc.dist.Source_Field__c);
            return v != null && String.valueOf(v).equalsIgnoreCase(dc.dist.Source_Ready_Value__c);
        }
        Id source = DE_Ids.toId(dc.dist.Source_Id__c);
        if (source == null || r.get(cfg.assignmentField) != source) {
            return false;
        }
        if (String.isNotBlank(cfg.team.Active_Status_Field__c) && !cfg.activeStatusValues.isEmpty()) {
            Object s = DE_Conditions.readPath(r, cfg.team.Active_Status_Field__c);
            return s != null && cfg.activeStatusValues.contains(String.valueOf(s).toLowerCase());
        }
        return true;
    }

    /** Increments failed attempts and puts records on hold after the configured threshold. */
    private static Integer recordFailures(Map<Id, String> reasons, Map<Id, String> objects, DE_DistributionCore.RunContext ctx) {
        if (reasons.isEmpty()) {
            return 0;
        }
        Integer threshold = DE_Settings.holdAfterFailures();
        Integer holdMinutes = DE_Settings.holdMinutes();
        List<DE_Record_Detail__c> updates = new List<DE_Record_Detail__c>();
        List<DE_Assignment_Log__c> holdLogs = new List<DE_Assignment_Log__c>();
        for (Id recordId : reasons.keySet()) {
            DE_Record_Detail__c d = DE_RecordDetails.ensure(ctx.cond.details, recordId, objects.get(recordId));
            d.Failed_Attempts__c = (d.Failed_Attempts__c == null ? 0 : d.Failed_Attempts__c) + 1;
            d.Last_Error__c = reasons.get(recordId).left(255);
            if (d.Failed_Attempts__c >= threshold) {
                d.On_Hold_Until__c = ctx.now.addMinutes(holdMinutes);
                d.Failed_Attempts__c = 0;
                holdLogs.add(
                    new DE_Assignment_Log__c(
                        Record_Id__c = recordId,
                        Object_API_Name__c = objects.get(recordId),
                        Type__c = 'Standard',
                        Status__c = 'On Hold',
                        Current__c = false,
                        Assigned_At__c = ctx.now,
                        Message__c = ('On hold for ' + holdMinutes + ' minutes after ' + threshold + ' failed attempts. ' + reasons.get(recordId)).left(255)
                    )
                );
                DE_AssignmentWriter.linkRecord(holdLogs[holdLogs.size() - 1], objects.get(recordId), recordId);
            }
            updates.add(d);
        }
        DE_RecordDetails.save(updates);
        Database.insert(holdLogs, false, AccessLevel.SYSTEM_MODE);
        return holdLogs.size();
    }
}
