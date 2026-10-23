/**
 * Pull distributors ("Get Next"): a member requests work and receives up to the distributor's
 * pull count from its source, respecting filters, member filters and caps.
 */
public without sharing class DE_PullService {
    public class PullOption {
        @AuraEnabled
        public Id distributorId;
        @AuraEnabled
        public String teamName;
        @AuraEnabled
        public String distributorName;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public Integer waiting;
        @AuraEnabled
        public Integer pullCount;
    }

    public class PullResult {
        @AuraEnabled
        public List<Id> recordIds = new List<Id>();
        @AuraEnabled
        public List<String> recordNames = new List<String>();
        @AuraEnabled
        public String message;
    }

    public static List<PullOption> options(Id userId) {
        Set<Id> teamIds = new Set<Id>();
        for (DE_Team_Member__c m : [SELECT Team__c FROM DE_Team_Member__c WHERE User__c = :userId AND Active__c = TRUE AND Team__r.Active__c = TRUE]) {
            teamIds.add(m.Team__c);
        }
        List<PullOption> out = new List<PullOption>();
        if (teamIds.isEmpty()) {
            return out;
        }
        for (DE_Model.TeamConfig cfg : DE_ConfigRepository.load(teamIds, null, false)) {
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                if (dc.type() != 'Pull') {
                    continue;
                }
                PullOption o = new PullOption();
                o.distributorId = dc.dist.Id;
                o.teamName = cfg.team.Name;
                o.distributorName = dc.dist.Name;
                o.objectName = cfg.objectName;
                o.pullCount = dc.dist.Pull_Count__c == null ? 1 : dc.dist.Pull_Count__c.intValue();
                try {
                    o.waiting = DE_RecordQuery.countAtSource(cfg, dc);
                } catch (Exception e) {
                    o.waiting = 0;
                }
                out.add(o);
            }
        }
        return out;
    }

    public static PullResult pull(Id userId, Id distributorId) {
        PullResult result = new PullResult();
        List<DE_Distributor__c> rows = [SELECT Id, Team__c FROM DE_Distributor__c WHERE Id = :distributorId LIMIT 1];
        if (rows.isEmpty()) {
            throw new DE_Permissions.AccessException('This pull distributor no longer exists.');
        }
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(rows[0].Team__c, false);
        DE_Model.DistributorConfig dc = cfg == null ? null : cfg.distributor(distributorId);
        if (dc == null || dc.type() != 'Pull') {
            throw new DE_Permissions.AccessException('This pull distributor is not active.');
        }
        DE_Model.Member me = cfg.member(userId);
        if (me == null || !me.isActive()) {
            throw new DE_Permissions.AccessException('You are not an active member of team ' + cfg.team.Name + '.');
        }
        DE_TeamLock.lock(cfg);
        Integer wanted = dc.dist.Pull_Count__c == null ? 1 : Math.max(1, Math.min(100, dc.dist.Pull_Count__c.intValue()));
        DE_DistributionCore.RunContext ctx = new DE_DistributionCore.RunContext(new List<DE_Model.TeamConfig>{ cfg }, System.now());
        ctx.logType = 'Pull';
        ctx.onlyMemberId = userId;
        ctx.onlyMemberIgnoresAvailability = true;
        List<String> warnings = new List<String>();
        List<SObject> candidates = DE_RecordQuery.sourceCandidates(cfg, dc, Math.min(2000, wanted * 20), warnings);
        ctx.cond.details = DE_RecordDetails.load(new Map<Id, SObject>(candidates).keySet(), DE_Conditions.detailFields(dc.filters));
        List<SObject> ready = new List<SObject>();
        for (SObject r : candidates) {
            DE_Record_Detail__c d = ctx.cond.details.get(r.Id);
            if (!DE_RecordDetails.isWaiting(d, (Datetime) r.get('CreatedDate'), ctx.now) && DE_DistributionCore.passesFilters(cfg, dc, r, ctx, null)) {
                ready.add(r);
            }
        }
        String nameField = DE_Schema.nameField(cfg.objectName);
        Integer index = 0;
        while (result.recordIds.size() < wanted && index < ready.size()) {
            List<SObject> chunk = new List<SObject>();
            while (chunk.size() < wanted - result.recordIds.size() && index < ready.size()) {
                chunk.add(ready[index++]);
            }
            List<DE_Model.Decision> decisions = DE_DistributionCore.distribute(cfg, dc, chunk, ctx);
            DE_AssignmentWriter.persist(cfg, decisions, ctx, false);
            Boolean anyAssigned = false;
            for (DE_Model.Decision d : decisions) {
                if (d.status == 'Assigned') {
                    anyAssigned = true;
                    result.recordIds.add(d.recordId);
                    result.recordNames.add(String.valueOf(d.record.get(nameField)));
                } else if (d.message != null && d.message.startsWith('No eligible') && !anyAssigned) {
                    result.message = 'You cannot receive more records right now (for example a cap has been reached).';
                }
            }
            if (!anyAssigned && result.message != null) {
                break;
            }
        }
        ctx.saveServices();
        if (result.recordIds.isEmpty() && result.message == null) {
            result.message = 'No records are available to pull right now.';
        }
        return result;
    }
}
