/**
 * Team-level and distributor-level caps.
 *  - Fixed periods (Hourly, Half-hourly, Daily, Weekly, Monthly) reset at boundaries in the team timezone.
 *  - Custom periods (minutes, hours, days) are rolling windows.
 *  - Active caps count (or sum the balance field of) records owned in Active Status.
 *  - Criteria caps count owned records matching the cap's criteria (or the distributor filters).
 * Counts come from Distribution Logs and are incremented in memory during a run.
 */
public without sharing class DE_CapService {
    public static final List<String> COUNTED_STATUSES = new List<String>{ 'Assigned', 'SLA Alert', 'Reassigned' };

    private DE_Model.TeamConfig cfg;
    private Datetime now;
    private Map<String, Map<Id, Decimal>> counts = new Map<String, Map<Id, Decimal>>();

    public DE_CapService(DE_Model.TeamConfig cfg, Datetime now) {
        this.cfg = cfg;
        this.now = now == null ? System.now() : now;
    }

    // ------------------------------------------------------------------ windows

    public static Datetime windowStart(String period, Decimal customLength, Datetime now, String timezoneSid) {
        DE_ShiftCalendar cal = DE_ShiftCalendar.always(timezoneSid);
        Long offset = TimeZone.getTimeZone(cal.timezoneSid).getOffset(now);
        Long localMs = now.getTime() + offset;
        switch on period {
            when 'Hourly' {
                return Datetime.newInstance(localMs - Math.mod(localMs, 3600000L) - offset);
            }
            when 'Half-hourly' {
                return Datetime.newInstance(localMs - Math.mod(localMs, 1800000L) - offset);
            }
            when 'Daily' {
                return cal.localMidnight(now);
            }
            when 'Weekly' {
                Date d = cal.localDate(now);
                Integer idx = DE_ShiftCalendar.dayIndex(d); // 0 = Monday
                Integer back = DE_Settings.weekStartDay() == 7 ? Math.mod(idx + 1, 7) : idx;
                return Datetime.newInstance(cal.utcMs(d.addDays(-back), 0));
            }
            when 'Monthly' {
                return Datetime.newInstance(cal.utcMs(cal.localDate(now).toStartOfMonth(), 0));
            }
            when 'Custom Minutes' {
                return now.addMinutes(-intOf(customLength, 60));
            }
            when 'Custom Hours' {
                return now.addHours(-intOf(customLength, 1));
            }
            when 'Custom Days' {
                return now.addDays(-intOf(customLength, 1));
            }
            when else {
                return null;
            }
        }
    }

    private static Integer intOf(Decimal d, Integer fallback) {
        return d == null ? fallback : d.intValue();
    }

    // ------------------------------------------------------------------ cap values

    /** The cap that applies to a member: first matching tag line, else default. Null means unlimited. */
    public static Decimal capFor(DE_Cap__c cap, DE_Model.Member m) {
        if (String.isNotBlank(cap.Tag_Caps__c)) {
            for (String line : cap.Tag_Caps__c.split('\\n')) {
                if (!line.contains('=')) {
                    continue;
                }
                String tag = line.substringBefore('=').trim().toLowerCase();
                if (m.tags.contains(tag)) {
                    String v = line.substringAfter('=').trim();
                    return String.isBlank(v) ? null : Decimal.valueOf(v);
                }
            }
        }
        return cap.Default_Cap__c;
    }

    // ------------------------------------------------------------------ evaluation

    /** Returns why the member is at a cap, or null when under every applicable cap. */
    public String capReason(DE_Model.Member m, DE_Model.DistributorConfig dc) {
        List<DE_Cap__c> caps = new List<DE_Cap__c>(dc.caps);
        if (dc.dist.Respect_Team_Caps__c != false) {
            caps.addAll(cfg.caps);
        }
        for (DE_Cap__c cap : caps) {
            Decimal limitValue = capFor(cap, m);
            if (limitValue == null) {
                continue;
            }
            Decimal used = countFor(cap, dc).get(m.memberId);
            used = used == null ? 0 : used;
            if (used >= limitValue) {
                String scope = cap.Distributor__c != null ? 'distributor' : 'team';
                return 'At ' + scope + ' ' + cap.Period__c.toLowerCase() + ' cap (' + used.setScale(0) + ' of ' + limitValue.setScale(0) + ')';
            }
        }
        return null;
    }

    /** Called after each assignment so later records in the same run see the new counts. */
    public void recordAssignment(DE_Model.Member m, DE_Model.DistributorConfig dc, Decimal value) {
        List<DE_Cap__c> caps = new List<DE_Cap__c>(dc.caps);
        caps.addAll(cfg.caps);
        for (DE_Cap__c cap : caps) {
            String key = cacheKey(cap, dc);
            if (!counts.containsKey(key)) {
                continue;
            }
            Map<Id, Decimal> c = counts.get(key);
            Decimal add = (cap.Period__c == 'Active' && cfg.team.Balance_By__c == 'Field Value') ? (value == null ? 0 : value) : 1;
            c.put(m.memberId, (c.containsKey(m.memberId) ? c.get(m.memberId) : 0) + add);
        }
    }

    private String cacheKey(DE_Cap__c cap, DE_Model.DistributorConfig dc) {
        // Criteria caps using distributor filters depend on the distributor.
        return cap.Id + (cap.Period__c == 'Criteria' && cap.Criteria_Source__c == 'Distributor Filters' ? '|' + dc.dist.Id : '');
    }

    private Map<Id, Decimal> countFor(DE_Cap__c cap, DE_Model.DistributorConfig dc) {
        String key = cacheKey(cap, dc);
        if (!counts.containsKey(key)) {
            Set<Id> memberIds = new Set<Id>();
            for (DE_Model.Member m : cfg.members) {
                memberIds.add(m.memberId);
            }
            Map<Id, Decimal> c;
            if (cap.Period__c == 'Active') {
                c = ownedCounts(cfg, memberIds, true, cfg.team.Balance_By__c == 'Field Value');
            } else if (cap.Period__c == 'Criteria') {
                List<DE_Condition__c> criteria = new List<DE_Condition__c>();
                String logic = cap.Criteria_Logic__c;
                if (cap.Criteria_Source__c == 'Distributor Filters') {
                    criteria.addAll(cfg.teamFilters);
                    criteria.addAll(dc.filters);
                    logic = null;
                } else {
                    criteria.addAll(cfg.capCriteria.get(cap.Id));
                }
                c = criteriaCounts(cfg, memberIds, criteria, logic);
            } else {
                Id scopeId = cap.Distributor__c != null ? cap.Distributor__c : cfg.team.Id;
                c = logCounts(scopeId, cap.Distributor__c != null, windowStart(cap.Period__c, cap.Custom_Length__c, now, cfg.timezoneSid()), memberIds, null);
            }
            counts.put(key, c);
        }
        return counts.get(key);
    }

    /** Assignment counts per assignee from Distribution Logs since a point in time. */
    public static Map<Id, Decimal> logCounts(Id scopeId, Boolean isDistributorScope, Datetime since, Set<Id> memberIds, Set<String> excludeMethods) {
        Map<Id, Decimal> out = new Map<Id, Decimal>();
        List<String> keys = new List<String>();
        for (Id i : memberIds) {
            keys.add(String.valueOf(i));
        }
        String soql =
            'SELECT Assignee_Id__c a, COUNT(Id) c FROM DE_Assignment_Log__c WHERE Assignee_Id__c IN :keys AND Status__c IN :statuses AND Assigned_At__c >= :since AND ' +
            (isDistributorScope ? 'Distributor__c = :scopeId' : 'Team__c = :scopeId');
        Map<String, Object> binds = new Map<String, Object>{ 'keys' => keys, 'statuses' => COUNTED_STATUSES, 'since' => since, 'scopeId' => scopeId };
        if (excludeMethods != null && !excludeMethods.isEmpty()) {
            soql += ' AND Method__c NOT IN :methods';
            binds.put('methods', new List<String>(excludeMethods));
        }
        soql += ' GROUP BY Assignee_Id__c';
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            out.put(Id.valueOf((String) ar.get('a')), (Decimal) ar.get('c'));
        }
        return out;
    }

    /** Records owned per member, optionally only those in Active Status, counted or summed by the balance field. */
    public static Map<Id, Decimal> ownedCounts(DE_Model.TeamConfig cfg, Set<Id> memberIds, Boolean activeOnly, Boolean byValue) {
        Map<Id, Decimal> out = new Map<Id, Decimal>();
        String obj = cfg.objectName;
        String af = cfg.assignmentField;
        Map<String, Object> binds = new Map<String, Object>{ 'ids' => memberIds };
        String measure = 'COUNT(Id)';
        String bf = byValue ? DE_Schema.canonicalPath(obj, cfg.team.Balance_Field__c) : null;
        if (bf != null) {
            measure = 'SUM(' + bf + ')';
        }
        String soql = 'SELECT ' + af + ' a, ' + measure + ' c FROM ' + obj + ' WHERE ' + af + ' IN :ids';
        if (activeOnly && String.isNotBlank(cfg.team.Active_Status_Field__c) && !cfg.activeStatusValues.isEmpty()) {
            String sf = DE_Schema.canonicalPath(obj, cfg.team.Active_Status_Field__c);
            if (sf != null) {
                soql += ' AND ' + sf + ' IN :vals';
                binds.put('vals', DE_Conditions.splitValues(cfg.team.Active_Status_Values__c));
            }
        }
        soql += ' GROUP BY ' + af;
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            Object v = ar.get('c');
            Decimal d = v == null ? 0 : Decimal.valueOf(String.valueOf(v)).round(System.RoundingMode.DOWN);
            out.put((Id) ar.get('a'), d);
        }
        return out;
    }

    /** Owned records matching criteria, per member (up to 5000 records evaluated). */
    public static Map<Id, Decimal> criteriaCounts(DE_Model.TeamConfig cfg, Set<Id> memberIds, List<DE_Condition__c> criteria, String logic) {
        Map<Id, Decimal> out = new Map<Id, Decimal>();
        Set<String> paths = DE_Conditions.recordPaths(criteria);
        paths.add('Id');
        paths.add(cfg.assignmentField);
        String soql =
            'SELECT ' +
            DE_RecordQuery.selectList(cfg.objectName, paths, null) +
            ' FROM ' +
            cfg.objectName +
            ' WHERE ' +
            cfg.assignmentField +
            ' IN :ids LIMIT 5000';
        List<SObject> rows = Database.queryWithBinds(soql, new Map<String, Object>{ 'ids' => memberIds }, AccessLevel.SYSTEM_MODE);
        Set<Id> rowIds = new Map<Id, SObject>(rows).keySet();
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.details = DE_RecordDetails.load(rowIds, DE_Conditions.detailFields(criteria));
        for (SObject r : rows) {
            if (DE_Conditions.matches(r, criteria, logic, ctx, null)) {
                Id owner = (Id) r.get(cfg.assignmentField);
                out.put(owner, (out.containsKey(owner) ? out.get(owner) : 0) + 1);
            }
        }
        return out;
    }
}
