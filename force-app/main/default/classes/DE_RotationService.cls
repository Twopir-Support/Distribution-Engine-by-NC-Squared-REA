/**
 * Round robin and weighting state for one team.
 *
 * Round robin: each (scope, member) has Last_Sequence__c; the team holds a monotonically increasing
 * Rotation_Sequence__c. The eligible member with the lowest sequence (never assigned = 0) is next.
 * Scope is the team ("T|teamId") or the distributor ("D|distributorId") per Round Robin Level.
 *
 * Weighting: per distributor ("W|distributorId") credits. When no eligible member has a credit of 1,
 * a new cycle adds each member's weight; members with credit >= 1 are served in round robin order.
 * Weight 2 = two assignments per cycle, 0.5 = one every other cycle, 0.25 = one in four.
 *
 * Callers must hold a FOR UPDATE lock on the team row (DE_TeamLock) before using this service.
 */
public without sharing class DE_RotationService {
    private DE_Model.TeamConfig cfg;
    private Decimal teamSequence;
    private Map<String, DE_Rotation_State__c> states = new Map<String, DE_Rotation_State__c>();
    private Set<String> dirty = new Set<String>();
    private Integer assignments = 0;

    public DE_RotationService(DE_Model.TeamConfig cfg) {
        this.cfg = cfg;
        this.teamSequence = cfg.team.Rotation_Sequence__c == null ? 0 : cfg.team.Rotation_Sequence__c;
        Id teamId = cfg.team.Id;
        for (DE_Rotation_State__c s : [
            SELECT Id, Name, Team__c, Scope_Key__c, Member_Key__c, Last_Sequence__c, Credit__c, Cycle__c, Replacement_Credits__c
            FROM DE_Rotation_State__c
            WHERE Team__c = :teamId
        ]) {
            states.put(s.Scope_Key__c, s);
        }
    }

    public String roundRobinScope(DE_Model.DistributorConfig dc) {
        return cfg.team.Round_Robin_Level__c == 'Distributor' ? 'D|' + dc.dist.Id : 'T|' + cfg.team.Id;
    }

    private DE_Rotation_State__c state(String scope, Id memberId) {
        String key = scope + '|' + memberId;
        DE_Rotation_State__c s = states.get(key);
        if (s == null) {
            s = new DE_Rotation_State__c(
                Name = key.left(80),
                Team__c = cfg.team.Id,
                Scope_Key__c = key,
                Member_Key__c = String.valueOf(memberId),
                Last_Sequence__c = 0,
                Credit__c = 0,
                Cycle__c = 0,
                Replacement_Credits__c = 0
            );
            states.put(key, s);
        }
        return s;
    }

    public Decimal sequence(String scope, Id memberId) {
        DE_Rotation_State__c s = states.get(scope + '|' + memberId);
        return s == null || s.Last_Sequence__c == null ? 0 : s.Last_Sequence__c;
    }

    /** Sort members into round robin order: lowest sequence first, then member number. */
    public List<DE_Model.Member> order(List<DE_Model.Member> members, String scope) {
        List<DE_Model.Member> sorted = new List<DE_Model.Member>(members);
        for (Integer i = 1; i < sorted.size(); i++) {
            DE_Model.Member cur = sorted[i];
            Integer j = i - 1;
            while (j >= 0 && before(cur, sorted[j], scope)) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = cur;
        }
        return sorted;
    }

    private Boolean before(DE_Model.Member a, DE_Model.Member b, String scope) {
        Decimal sa = sequence(scope, a.memberId);
        Decimal sb = sequence(scope, b.memberId);
        if (sa != sb) {
            return sa < sb;
        }
        return a.record.Name < b.record.Name;
    }

    public DE_Model.Member pickRoundRobin(List<DE_Model.Member> eligible, String scope) {
        if (eligible.isEmpty()) {
            return null;
        }
        return order(eligible, scope)[0];
    }

    public Boolean weightsDiffer(List<DE_Model.Member> eligible) {
        Decimal first;
        for (DE_Model.Member m : eligible) {
            if (first == null) {
                first = m.weight;
            } else if (m.weight != first) {
                return true;
            }
        }
        return false;
    }

    public DE_Model.Member pickWeighted(List<DE_Model.Member> eligible, DE_Model.DistributorConfig dc, String rrScope) {
        if (eligible.isEmpty()) {
            return null;
        }
        String wScope = 'W|' + dc.dist.Id;
        List<DE_Model.Member> withCredit = creditHolders(eligible, wScope);
        Integer guard = 0;
        while (withCredit.isEmpty() && guard < 8) {
            for (DE_Model.Member m : eligible) {
                DE_Rotation_State__c s = state(wScope, m.memberId);
                s.Credit__c = (s.Credit__c == null ? 0 : s.Credit__c) + m.weight;
                s.Cycle__c = (s.Cycle__c == null ? 0 : s.Cycle__c) + 1;
                dirty.add(s.Scope_Key__c);
            }
            withCredit = creditHolders(eligible, wScope);
            guard++;
        }
        DE_Model.Member picked = pickRoundRobin(withCredit.isEmpty() ? eligible : withCredit, rrScope);
        DE_Rotation_State__c s = state(wScope, picked.memberId);
        s.Credit__c = (s.Credit__c == null ? 0 : s.Credit__c) - 1;
        dirty.add(s.Scope_Key__c);
        return picked;
    }

    private List<DE_Model.Member> creditHolders(List<DE_Model.Member> eligible, String wScope) {
        List<DE_Model.Member> out = new List<DE_Model.Member>();
        for (DE_Model.Member m : eligible) {
            DE_Rotation_State__c s = states.get(wScope + '|' + m.memberId);
            if (s != null && s.Credit__c != null && s.Credit__c >= 1) {
                out.add(m);
            }
        }
        return out;
    }

    /**
     * Records a round robin hit. With a pending replacement credit (after a rejection) the member
     * keeps their place once, so they receive a replacement record on their usual turn.
     */
    public void recordHit(DE_Model.Member m, String scope, Boolean countsAsHit) {
        assignments++;
        if (!countsAsHit) {
            return;
        }
        DE_Rotation_State__c s = state(scope, m.memberId);
        if (s.Replacement_Credits__c != null && s.Replacement_Credits__c > 0) {
            s.Replacement_Credits__c -= 1;
        } else {
            teamSequence += 1;
            s.Last_Sequence__c = teamSequence;
        }
        dirty.add(s.Scope_Key__c);
    }

    /** Replace as Next Assignment: put the member at the front of the line. */
    public void moveToFront(Id memberId, String scope) {
        DE_Rotation_State__c s = state(scope, memberId);
        s.Last_Sequence__c = 0;
        dirty.add(s.Scope_Key__c);
    }

    /** Replace on Usual Assignment: owe the member one replacement record. */
    public void addReplacementCredit(Id memberId, String scope) {
        DE_Rotation_State__c s = state(scope, memberId);
        s.Replacement_Credits__c = (s.Replacement_Credits__c == null ? 0 : s.Replacement_Credits__c) + 1;
        dirty.add(s.Scope_Key__c);
    }

    public Integer assignmentCount() {
        return assignments;
    }

    /** Persists rotation states and the team counters. */
    public void save() {
        List<DE_Rotation_State__c> toSave = new List<DE_Rotation_State__c>();
        for (String k : dirty) {
            toSave.add(states.get(k));
        }
        if (!toSave.isEmpty()) {
            Database.upsert(toSave, DE_Rotation_State__c.Scope_Key__c, true, AccessLevel.SYSTEM_MODE);
        }
        if (assignments > 0 || !toSave.isEmpty()) {
            DE_Team__c t = new DE_Team__c(
                Id = cfg.team.Id,
                Rotation_Sequence__c = teamSequence,
                Total_Assignments__c = (cfg.team.Total_Assignments__c == null ? 0 : cfg.team.Total_Assignments__c) + assignments
            );
            if (assignments > 0) {
                t.Last_Assigned_At__c = System.now();
            }
            Database.update(t, true, AccessLevel.SYSTEM_MODE);
            cfg.team.Rotation_Sequence__c = teamSequence;
            cfg.team.Total_Assignments__c = t.Total_Assignments__c;
        }
        dirty.clear();
        assignments = 0;
    }
}
