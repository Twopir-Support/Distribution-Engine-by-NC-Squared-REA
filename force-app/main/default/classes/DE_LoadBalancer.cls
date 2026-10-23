/**
 * Load balancing: tops up the members with the lowest score.
 * Daily/Weekly/Monthly scores are Distribution Engine assignments in the period (team or distributor level);
 * Active scores are owned records in Active Status (count or field value). With weighting, score / weight is compared.
 */
public without sharing class DE_LoadBalancer {
    private DE_Model.TeamConfig cfg;
    private Datetime now;
    private Map<String, Map<Id, Decimal>> scores = new Map<String, Map<Id, Decimal>>();

    public DE_LoadBalancer(DE_Model.TeamConfig cfg, Datetime now) {
        this.cfg = cfg;
        this.now = now == null ? System.now() : now;
    }

    private String key(DE_Model.DistributorConfig dc) {
        return cfg.team.Load_Balancing_Level__c == 'Distributor' && cfg.team.Load_Balancing_Type__c != 'Active' ? 'D|' + dc.dist.Id : 'T';
    }

    public Map<Id, Decimal> scoresFor(DE_Model.DistributorConfig dc) {
        String k = key(dc);
        if (!scores.containsKey(k)) {
            Set<Id> memberIds = new Set<Id>();
            for (DE_Model.Member m : cfg.members) {
                memberIds.add(m.memberId);
            }
            String type = cfg.team.Load_Balancing_Type__c == null ? 'Daily' : cfg.team.Load_Balancing_Type__c;
            Map<Id, Decimal> s;
            if (type == 'Active') {
                s = DE_CapService.ownedCounts(cfg, memberIds, true, cfg.team.Balance_By__c == 'Field Value');
            } else {
                Set<String> excluded = new Set<String>();
                if (!DE_Settings.countLookupInBalance()) {
                    excluded.add('Lookup Owner');
                    excluded.add('Related Owner');
                }
                if (!DE_Settings.countStickyInBalance()) {
                    excluded.add('Sticky');
                }
                if (!DE_Settings.countPullAsHit()) {
                    excluded.add('Pull');
                }
                Boolean distScope = k.startsWith('D|');
                s = DE_CapService.logCounts(
                    distScope ? dc.dist.Id : cfg.team.Id,
                    distScope,
                    DE_CapService.windowStart(type, null, now, cfg.timezoneSid()),
                    memberIds,
                    excluded
                );
            }
            scores.put(k, s);
        }
        return scores.get(k);
    }

    public Decimal score(DE_Model.Member m, DE_Model.DistributorConfig dc) {
        Decimal s = scoresFor(dc).get(m.memberId);
        return s == null ? 0 : s;
    }

    public DE_Model.Member pick(List<DE_Model.Member> eligible, DE_Model.DistributorConfig dc, DE_RotationService rotation, String rrScope) {
        if (eligible.isEmpty()) {
            return null;
        }
        Boolean weighted = dc.dist.Weighting_Enabled__c != false && rotation.weightsDiffer(eligible);
        DE_Model.Member best;
        Decimal bestScore;
        for (DE_Model.Member m : rotation.order(eligible, rrScope)) {
            Decimal s = score(m, dc);
            if (weighted) {
                s = s / m.weight;
            }
            if (best == null || s < bestScore) {
                best = m;
                bestScore = s;
            }
        }
        return best;
    }

    public void recordAssignment(DE_Model.Member m, DE_Model.DistributorConfig dc, Decimal value) {
        Map<Id, Decimal> s = scoresFor(dc);
        Decimal add = cfg.team.Load_Balancing_Type__c == 'Active' && cfg.team.Balance_By__c == 'Field Value' ? (value == null ? 0 : value) : 1;
        s.put(m.memberId, (s.containsKey(m.memberId) ? s.get(m.memberId) : 0) + add);
    }
}
