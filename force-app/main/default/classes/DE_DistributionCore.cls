/**
 * Decides who receives each record for one distributor. Pure decision logic: it updates in-memory
 * rotation, cap and balancing state but performs no record DML (see DE_AssignmentWriter).
 *
 * Order per record: sticky match -> eligibility (availability, member filters, exclusions,
 * caps, tracked previous assignees) -> method (round robin / weighted / load balancing / owner methods).
 */
public without sharing class DE_DistributionCore {
    public class RunContext {
        public Datetime now = System.now();
        public Boolean dryRun = false;
        public Boolean ignoreCaps = false;
        public Boolean ignoreHours = false;
        public Id onlyMemberId;
        public Boolean onlyMemberIgnoresAvailability = false;
        public String logType = 'Standard';
        public DE_Conditions.Context cond = new DE_Conditions.Context();
        public DE_AvailabilityService availability;
        public List<String> warnings = new List<String>();
        private Map<Id, TeamServices> services = new Map<Id, TeamServices>();

        public RunContext(List<DE_Model.TeamConfig> teams, Datetime now) {
            this.now = now == null ? System.now() : now;
            this.cond.now = this.now;
            this.availability = new DE_AvailabilityService(teams, this.now);
        }

        public TeamServices servicesFor(DE_Model.TeamConfig cfg) {
            if (!services.containsKey(cfg.team.Id)) {
                TeamServices ts = new TeamServices();
                ts.caps = new DE_CapService(cfg, now);
                ts.rotation = new DE_RotationService(cfg);
                ts.balancer = new DE_LoadBalancer(cfg, now);
                services.put(cfg.team.Id, ts);
            }
            return services.get(cfg.team.Id);
        }

        /** Persists rotation state for every team touched in this run (no-op for dry runs). */
        public void saveServices() {
            if (dryRun) {
                return;
            }
            for (TeamServices ts : services.values()) {
                ts.rotation.save();
            }
        }
    }

    public class TeamServices {
        public DE_CapService caps;
        public DE_RotationService rotation;
        public DE_LoadBalancer balancer;
    }

    // ------------------------------------------------------------------ filters

    public static Boolean passesFilters(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, SObject rec, RunContext ctx, List<String> trace) {
        try {
            if (!cfg.teamFilters.isEmpty()) {
                if (trace != null) {
                    trace.add('Team filters:');
                }
                if (!DE_Conditions.matches(rec, cfg.teamFilters, cfg.team.Filter_Logic__c, ctx.cond, trace)) {
                    return false;
                }
            }
            if (!dc.filters.isEmpty()) {
                if (trace != null) {
                    trace.add('Distributor filters:');
                }
                if (!DE_Conditions.matches(rec, dc.filters, dc.dist.Filter_Logic__c, ctx.cond, trace)) {
                    return false;
                }
            }
            return true;
        } catch (Exception e) {
            if (trace != null) {
                trace.add('Filter error: ' + e.getMessage());
            }
            ctx.warnings.add(dc.dist.Name + ': ' + e.getMessage());
            return false;
        }
    }

    /** Member filters: Tag:<Collection>, DynamicTag:<Collection>, Territory, Stamp:<Group>. All rows must pass. */
    public static Boolean memberFiltersPass(DE_Model.Member m, DE_Model.DistributorConfig dc, SObject rec, RunContext ctx) {
        for (DE_Condition__c c : dc.memberFilters) {
            String f = c.Field_API_Name__c.trim();
            String lower = f.toLowerCase();
            String op = c.Operator__c == null ? 'includes' : c.Operator__c.toLowerCase();
            List<String> wanted = lowerList(DE_Conditions.splitValues(c.Value__c));
            if (lower.startsWith('tag:')) {
                if (!setTest(m.tagsIn(f.substringAfter(':')), wanted, op)) {
                    return false;
                }
            } else if (lower.startsWith('dynamictag:')) {
                Object v;
                try {
                    v = DE_Conditions.readPath(rec, c.Value__c);
                } catch (Exception e) {
                    v = null;
                }
                List<String> recordValues = v == null ? new List<String>() : lowerList(DE_Conditions.splitValues(String.valueOf(v)));
                if (recordValues.isEmpty() || !setTest(m.tagsIn(f.substringAfter(':')), recordValues, op == 'includes all' ? 'includes all' : 'includes')) {
                    return false;
                }
            } else if (lower == 'territory') {
                DE_Record_Detail__c d = ctx.cond.details.get(rec.Id);
                String territory = d == null ? null : d.Territory_Name__c;
                if (String.isBlank(territory)) {
                    return false;
                }
                if (!wanted.isEmpty() && !wanted.contains(territory.toLowerCase())) {
                    return false;
                }
                Boolean has = m.tagsIn('Territory').contains(territory.toLowerCase());
                if ((op == 'does not include' && has) || (op != 'does not include' && !has)) {
                    return false;
                }
            } else if (lower.startsWith('stamp:')) {
                String groupName = f.substringAfter(':');
                DE_Record_Detail__c d = ctx.cond.details.get(rec.Id);
                String stamps = d == null ? null : DE_Conditions.stampsInGroup(d.Stamps__c, groupName);
                List<String> recordStamps = lowerList(DE_Conditions.splitValues(stamps));
                if (recordStamps.isEmpty()) {
                    return false;
                }
                if (!setTest(m.tagsIn('StampGroup.' + groupName), recordStamps, op)) {
                    return false;
                }
            }
        }
        return true;
    }

    private static List<String> lowerList(List<String> values) {
        List<String> out = new List<String>();
        for (String v : values) {
            out.add(v.toLowerCase());
        }
        return out;
    }

    private static Boolean setTest(Set<String> have, List<String> wanted, String op) {
        Integer hits = 0;
        for (String w : wanted) {
            if (have.contains(w)) {
                hits++;
            }
        }
        if (op == 'does not include') {
            return hits == 0;
        }
        if (op == 'includes all') {
            return !wanted.isEmpty() && hits == new Set<String>(wanted).size();
        }
        return hits > 0;
    }

    private static Set<Id> excludedIds(DE_Model.DistributorConfig dc, SObject rec) {
        if (String.isBlank(dc.dist.Exclude_Members_Field__c)) {
            return new Set<Id>();
        }
        try {
            Object v = DE_Conditions.readPath(rec, dc.dist.Exclude_Members_Field__c);
            return v == null ? new Set<Id>() : DE_Ids.parseList(String.valueOf(v));
        } catch (Exception e) {
            return new Set<Id>();
        }
    }

    private static Decimal balanceValue(DE_Model.TeamConfig cfg, SObject rec) {
        if (cfg.team.Balance_By__c != 'Field Value' || String.isBlank(cfg.team.Balance_Field__c)) {
            return null;
        }
        try {
            Object v = DE_Conditions.readPath(rec, cfg.team.Balance_Field__c);
            return v == null ? 0 : Decimal.valueOf(String.valueOf(v)).round(System.RoundingMode.DOWN);
        } catch (Exception e) {
            return 0;
        }
    }

    // ------------------------------------------------------------------ distribution

    /**
     * Returns one decision per record. Records that cannot be assigned get status 'Unassigned'
     * and a message; the caller decides whether they overflow, retry or fall back.
     */
    public static List<DE_Model.Decision> distribute(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, List<SObject> records, RunContext ctx) {
        List<DE_Model.Decision> out = new List<DE_Model.Decision>();
        if (records.isEmpty()) {
            return out;
        }
        TeamServices ts = ctx.servicesFor(cfg);
        String method = dc.method();
        String rrScope = ts.rotation.roundRobinScope(dc);
        Integer tracked = DE_Settings.previousAssigneesTracked();
        Boolean pull = ctx.logType == 'Pull';

        Set<Id> activeMemberIds = new Set<Id>();
        Map<Id, String> baseReason = new Map<Id, String>();
        for (DE_Model.Member m : cfg.members) {
            String r = null;
            if (!m.isActive()) {
                r = 'Inactive member or user';
            } else {
                activeMemberIds.add(m.memberId);
                if (!dc.selectedMembers.isEmpty() && !dc.selectedMembers.contains(m.memberId)) {
                    r = 'Not a selected member of this distributor';
                } else if (ctx.onlyMemberId != null && m.memberId != ctx.onlyMemberId) {
                    r = 'Not the requesting user';
                } else if (!(ctx.onlyMemberId != null && ctx.onlyMemberIgnoresAvailability)) {
                    r = ctx.availability.unavailableReason(m, dc.dist.Assign_If_Unavailable__c, dc.dist.Assign_If_Offline__c, ctx.ignoreHours);
                }
            }
            baseReason.put(m.memberId, r);
        }

        Map<Id, Id> fixedOwners = new Map<Id, Id>();
        if (method == 'Lookup Owner') {
            fixedOwners = DE_OwnerResolver.lookupOwners(cfg, dc, records, activeMemberIds, ctx.warnings);
        } else if (method == 'Related Owner') {
            fixedOwners = DE_OwnerResolver.relatedOwners(dc, records, ctx.cond.details, activeMemberIds);
        } else if (method == 'Dynamic Owner') {
            fixedOwners = DE_OwnerResolver.dynamicOwners(dc, records);
        }

        Map<Id, String> stickyKeys = new Map<Id, String>();
        Map<String, Id> stickyOwners = new Map<String, Id>();
        Boolean stickyOn = dc.dist.Sticky_Enabled__c == true && (method == 'Round Robin' || method == 'Load Balancing');
        if (stickyOn) {
            for (SObject r : records) {
                String k = DE_StickyService.key(cfg, dc, r);
                if (k != null) {
                    stickyKeys.put(r.Id, k);
                }
            }
            stickyOwners = DE_StickyService.lookup(
                new Set<String>(stickyKeys.values()),
                dc.dist.Sticky_Days__c == null ? 90 : dc.dist.Sticky_Days__c.intValue(),
                ctx.now
            );
        }

        for (SObject rec : records) {
            DE_Model.Decision d = new DE_Model.Decision(rec);
            d.distributor = dc;
            d.previousOwnerId = (Id) rec.get(cfg.assignmentField);
            d.balanceValue = balanceValue(cfg, rec);
            d.trace.add('Team ' + cfg.team.Name + ' → distributor ' + dc.dist.Name + ' (' + dc.type() + ', ' + method + ')');
            out.add(d);

            // Current Owner (trigger): keep the owner, log and track.
            if (method == 'Current Owner') {
                d.assigneeId = d.previousOwnerId;
                d.member = cfg.member(d.previousOwnerId);
                d.method = 'Current Owner';
                d.countsAsHit = false;
                if (d.member != null) {
                    recordCounts(ts, cfg, dc, d, rrScope);
                }
                continue;
            }

            // Owner methods.
            if (method == 'Lookup Owner' || method == 'Related Owner' || method == 'Dynamic Owner') {
                Id owner = fixedOwners.get(rec.Id);
                if (owner == null) {
                    unassigned(d, 'No ' + method.toLowerCase() + ' match for this record');
                    continue;
                }
                d.assigneeId = owner;
                d.member = cfg.member(owner);
                d.method = method;
                d.countsAsHit = false;
                d.trace.add(method + ' → ' + (d.member == null ? String.valueOf(owner) : d.member.name()));
                if (d.member != null) {
                    recordCounts(ts, cfg, dc, d, rrScope);
                }
                continue;
            }

            // Sticky match.
            String key = stickyKeys.get(rec.Id);
            d.stickyKey = key;
            if (key != null && stickyOwners.containsKey(key)) {
                DE_Model.Member sm = cfg.member(stickyOwners.get(key));
                if (sm != null && sm.isActive()) {
                    String reason = baseReason.get(sm.memberId);
                    Boolean availableEnough =
                        reason == null ||
                        dc.dist.Sticky_Retain_Unavailable__c == true ||
                        (reason.startsWith('Toggled offline') && dc.dist.Sticky_Retain_Offline__c == true);
                    if (reason == 'Not a selected member of this distributor' || reason == 'Not the requesting user') {
                        availableEnough = false;
                    }
                    String behaviour = dc.dist.Sticky_Cap_Behaviour__c == null ? 'Ignore Caps' : dc.dist.Sticky_Cap_Behaviour__c;
                    String capReason = ctx.ignoreCaps || behaviour == 'Ignore Caps' ? null : ts.caps.capReason(sm, dc);
                    if (availableEnough && capReason == null) {
                        d.member = sm;
                        d.assigneeId = sm.memberId;
                        d.method = 'Sticky';
                        d.sticky = true;
                        d.countsAsHit = false;
                        d.trace.add('Sticky match on ' + dc.dist.Sticky_Field__c + ' → ' + sm.name());
                        recordCounts(ts, cfg, dc, d, rrScope);
                        continue;
                    }
                    d.trace.add('Sticky match ' + sm.name() + ' skipped: ' + (capReason != null ? capReason : reason));
                    if (capReason != null && behaviour == 'Respect Caps - Don\'t Assign') {
                        unassigned(d, 'Sticky member is at cap');
                        continue;
                    }
                }
            }
            if (stickyOn && dc.dist.Sticky_Only__c == true) {
                unassigned(d, 'No sticky match and round robin is disabled for this distributor');
                continue;
            }

            // Eligibility.
            DE_Record_Detail__c detail = ctx.cond.details.get(rec.Id);
            Set<Id> recent = DE_RecordDetails.recentAssignees(detail, tracked);
            Set<Id> excluded = excludedIds(dc, rec);
            List<DE_Model.Member> eligible = new List<DE_Model.Member>();
            List<DE_Model.Member> previouslyAssigned = new List<DE_Model.Member>();
            for (DE_Model.Member m : cfg.members) {
                String reason = baseReason.get(m.memberId);
                if (reason == null && !memberFiltersPass(m, dc, rec, ctx)) {
                    reason = 'Does not match the team member filter';
                }
                if (reason == null && excluded.contains(m.memberId)) {
                    reason = 'Excluded by ' + dc.dist.Exclude_Members_Field__c;
                }
                if (reason == null && !ctx.ignoreCaps) {
                    reason = ts.caps.capReason(m, dc);
                }
                if (reason == null && recent.contains(m.memberId)) {
                    previouslyAssigned.add(m);
                    reason = 'Already received this record';
                }
                if (reason == null) {
                    eligible.add(m);
                }
                d.trace.add('  ' + m.name() + ': ' + (reason == null ? 'eligible' : reason));
            }
            if (eligible.isEmpty() && previouslyAssigned.size() == 1) {
                eligible = previouslyAssigned;
                d.trace.add('  Only a previous assignee is available, so they receive the record.');
            }
            if (eligible.isEmpty()) {
                unassigned(d, 'No eligible team member');
                continue;
            }

            DE_Model.Member picked;
            if (method == 'Load Balancing') {
                picked = ts.balancer.pick(eligible, dc, ts.rotation, rrScope);
                d.method = 'Load Balancing';
            } else {
                Boolean weighted = dc.dist.Weighting_Enabled__c != false && ts.rotation.weightsDiffer(eligible);
                picked = weighted ? ts.rotation.pickWeighted(eligible, dc, rrScope) : ts.rotation.pickRoundRobin(eligible, rrScope);
                d.method = pull ? 'Pull' : 'Round Robin';
            }
            d.member = picked;
            d.assigneeId = picked.memberId;
            d.countsAsHit = pull ? DE_Settings.countPullAsHit() : true;
            d.trace.add('Assigned to ' + picked.name() + ' by ' + d.method);
            recordCounts(ts, cfg, dc, d, rrScope);
        }
        return out;
    }

    private static void unassigned(DE_Model.Decision d, String message) {
        d.status = 'Unassigned';
        d.message = message;
        d.trace.add('Not assigned: ' + message);
    }

    private static void recordCounts(TeamServices ts, DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, DE_Model.Decision d, String rrScope) {
        if (d.member == null) {
            return;
        }
        ts.rotation.recordHit(d.member, rrScope, d.countsAsHit);
        ts.caps.recordAssignment(d.member, dc, d.balanceValue);
        if (cfg.team.Load_Balancing_Type__c != null) {
            ts.balancer.recordAssignment(d.member, dc, d.balanceValue);
        }
    }
}
