/**
 * Manual distributors: a manager chooses the team member for a record from the record page.
 * Manual assignment is allowed even when the member is at a cap, and is counted for caps,
 * load balancing, SLAs and rejection like any other assignment.
 */
public without sharing class DE_ManualAssignService {
    public class MemberOption {
        @AuraEnabled
        public Id memberId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Boolean available;
        @AuraEnabled
        public String availability;
        @AuraEnabled
        public Integer assignedToday;
        @AuraEnabled
        public String capState;
    }

    public class TeamOption {
        @AuraEnabled
        public Id distributorId;
        @AuraEnabled
        public String teamName;
        @AuraEnabled
        public String distributorName;
        @AuraEnabled
        public List<MemberOption> members = new List<MemberOption>();
    }

    public static List<TeamOption> options(Id recordId) {
        String obj = recordId.getSobjectType().getDescribe().getName();
        List<TeamOption> out = new List<TeamOption>();
        List<DE_Model.TeamConfig> teams = DE_ConfigRepository.activeTeams(obj);
        DE_AvailabilityService availability = new DE_AvailabilityService(teams, System.now());
        for (DE_Model.TeamConfig cfg : teams) {
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                if (dc.type() != 'Manual') {
                    continue;
                }
                TeamOption t = new TeamOption();
                t.distributorId = dc.dist.Id;
                t.teamName = cfg.team.Name;
                t.distributorName = dc.dist.Name;
                Set<Id> ids = new Set<Id>();
                for (DE_Model.Member m : cfg.members) {
                    ids.add(m.memberId);
                }
                Map<Id, Decimal> today = DE_CapService.logCounts(
                    cfg.team.Id,
                    false,
                    DE_CapService.windowStart('Daily', null, System.now(), cfg.timezoneSid()),
                    ids,
                    null
                );
                DE_CapService caps = new DE_CapService(cfg, System.now());
                for (DE_Model.Member m : cfg.members) {
                    if (!m.isActive()) {
                        continue;
                    }
                    MemberOption o = new MemberOption();
                    o.memberId = m.memberId;
                    o.name = m.name();
                    String reason = availability.holidayFor(cfg) != null ? 'Team holiday' : availability.unavailableReason(m, false, false, false);
                    o.available = reason == null;
                    o.availability = reason == null ? 'Available' : reason;
                    o.assignedToday = today.containsKey(m.memberId) ? today.get(m.memberId).intValue() : 0;
                    String cap = caps.capReason(m, dc);
                    o.capState = cap == null ? 'Within caps' : cap;
                    t.members.add(o);
                }
                out.add(t);
            }
        }
        return out;
    }

    public static void assign(Id recordId, Id distributorId, Id memberId) {
        List<DE_Distributor__c> rows = [SELECT Id, Team__c FROM DE_Distributor__c WHERE Id = :distributorId LIMIT 1];
        if (rows.isEmpty()) {
            throw new DE_Permissions.AccessException('This manual distributor no longer exists.');
        }
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(rows[0].Team__c, false);
        DE_Model.DistributorConfig dc = cfg == null ? null : cfg.distributor(distributorId);
        if (dc == null || dc.type() != 'Manual') {
            throw new DE_Permissions.AccessException('This manual distributor is not active.');
        }
        DE_Model.Member member = cfg.member(memberId);
        if (member == null || !member.isActive()) {
            throw new DE_Permissions.AccessException('Choose an active member of team ' + cfg.team.Name + '.');
        }
        if (!recordId.getSobjectType().getDescribe().getName().equalsIgnoreCase(cfg.objectName)) {
            throw new DE_Permissions.AccessException('Team ' + cfg.team.Name + ' distributes ' + cfg.objectName + ' records.');
        }
        DE_TeamLock.lock(cfg);
        List<SObject> records = DE_RecordQuery.byIds(cfg.objectName, DE_RecordQuery.requiredPaths(cfg, dc), new Set<Id>{ recordId }, new List<String>());
        if (records.isEmpty()) {
            throw new DE_Permissions.AccessException('The record no longer exists.');
        }
        DE_DistributionCore.RunContext ctx = new DE_DistributionCore.RunContext(new List<DE_Model.TeamConfig>{ cfg }, System.now());
        ctx.logType = 'Manual';
        ctx.cond.details = DE_RecordDetails.load(new Set<Id>{ recordId }, null);
        DE_DistributionCore.TeamServices ts = ctx.servicesFor(cfg);
        String scope = ts.rotation.roundRobinScope(dc);

        DE_Model.Decision d = new DE_Model.Decision(records[0]);
        d.distributor = dc;
        d.member = member;
        d.assigneeId = member.memberId;
        d.previousOwnerId = (Id) records[0].get(cfg.assignmentField);
        d.method = 'Manual';
        d.countsAsHit = DE_Settings.countManualAsHit();
        d.trace.add('Manually assigned to ' + member.name() + ' by ' + UserInfo.getName() + '.');
        ts.rotation.recordHit(member, scope, d.countsAsHit);
        ts.caps.recordAssignment(member, dc, null);

        if (dc.dist.Treat_Manual_As_Rejection__c == true && d.previousOwnerId != null && d.previousOwnerId != member.memberId) {
            DE_Model.Member previous = cfg.member(d.previousOwnerId);
            if (previous != null) {
                DE_RecordDetails.pushAssignee(DE_RecordDetails.ensure(ctx.cond.details, recordId, cfg.objectName), previous.memberId);
                DE_RejectionService.applyReplacement(ts.rotation, dc, previous.memberId, scope);
                d.trace.add('Treated as a rejection by ' + previous.name() + '.');
            }
        }
        DE_AssignmentWriter.Result res = DE_AssignmentWriter.persist(cfg, new List<DE_Model.Decision>{ d }, ctx, false);
        ctx.saveServices();
        if (res.errors > 0) {
            throw new DE_Permissions.AccessException('The record could not be assigned: ' + res.errorByRecord.get(recordId));
        }
    }
}
