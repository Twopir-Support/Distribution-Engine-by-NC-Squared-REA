/**
 * Builds and runs the dynamic SOQL that loads routed records with every field the
 * configuration needs. Field paths typed by admins are validated with DE_Schema before use,
 * so a misconfigured path is reported instead of breaking the query.
 */
public without sharing class DE_RecordQuery {
    public static final List<String> TRACKING_FIELDS = new List<String>{
        'DE_Is_Distributed__c',
        'DE_Last_Distributed__c',
        'DE_Distribution_Count__c',
        'DE_Is_Reassigned__c',
        'DE_Last_Reassigned__c',
        'DE_Trigger_Distribution__c',
        'DE_Is_Triggered__c',
        'DE_Is_Rejected__c',
        'DE_Last_Rejected__c',
        'DE_Is_Archived__c',
        'DE_Source_Queue__c',
        'DE_Time_To_Action__c',
        'DE_Territory__c'
    };

    /** Every record path the team and distributor configuration reads. */
    public static Set<String> requiredPaths(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc) {
        Set<String> paths = new Set<String>{ 'Id', 'CreatedDate', 'LastModifiedDate', 'LastModifiedById', cfg.assignmentField };
        String obj = cfg.objectName;
        paths.add(DE_Schema.nameField(obj));
        for (String f : TRACKING_FIELDS) {
            if (DE_Schema.hasField(obj, f)) {
                paths.add(f);
            }
        }
        paths.addAll(DE_Conditions.recordPaths(cfg.teamFilters));
        addIfSet(paths, cfg.team.Active_Status_Field__c);
        addIfSet(paths, cfg.team.Balance_Field__c);
        addIfSet(paths, cfg.team.Action_Field__c);
        List<DE_Model.DistributorConfig> dists = dc == null ? cfg.distributors : new List<DE_Model.DistributorConfig>{ dc };
        for (DE_Model.DistributorConfig d : dists) {
            paths.addAll(DE_Conditions.recordPaths(d.filters));
            for (DE_Condition__c c : d.memberFilters) {
                if (c.Field_API_Name__c != null && c.Field_API_Name__c.toLowerCase().startsWith('dynamictag:')) {
                    addIfSet(paths, c.Value__c);
                }
            }
            addIfSet(paths, d.dist.Exclude_Members_Field__c);
            addIfSet(paths, d.dist.Sticky_Field__c);
            addIfSet(paths, d.dist.Lookup_Record_Field__c);
            addIfSet(paths, d.dist.Dynamic_Owner_Field__c);
            addIfSet(paths, d.dist.Source_Field__c);
            if (!DE_Conditions.isDetailPath(d.dist.Related_Field__c)) {
                addIfSet(paths, d.dist.Related_Field__c);
            }
            if (!DE_Conditions.isDetailPath(d.dist.Related_Secondary_Field__c)) {
                addIfSet(paths, d.dist.Related_Secondary_Field__c);
            }
            for (String s : sortFields(d.dist.Sort_Order__c)) {
                paths.add(s);
            }
        }
        for (List<DE_Condition__c> conds : cfg.slaConditions.values()) {
            paths.addAll(DE_Conditions.recordPaths(conds));
        }
        for (DE_SLA__c s : cfg.slas) {
            addIfSet(paths, s.Check_After_Field__c);
        }
        return paths;
    }

    private static void addIfSet(Set<String> paths, String value) {
        if (String.isNotBlank(value)) {
            paths.add(value.trim());
        }
    }

    /** Builds a SELECT list of valid, canonical paths. Invalid paths are reported in warnings. */
    public static String selectList(String objectName, Set<String> paths, List<String> warnings) {
        Set<String> valid = new Set<String>();
        Set<String> seen = new Set<String>();
        for (String p : paths) {
            if (String.isBlank(p) || seen.contains(p.toLowerCase())) {
                continue;
            }
            seen.add(p.toLowerCase());
            String canonical = DE_Schema.canonicalPath(objectName, p);
            if (canonical == null) {
                if (warnings != null) {
                    warnings.add('Field ' + p + ' does not exist on ' + objectName + ' and was ignored.');
                }
                continue;
            }
            valid.add(canonical);
        }
        Set<String> lowered = new Set<String>();
        List<String> out = new List<String>();
        for (String v : valid) {
            if (!lowered.contains(v.toLowerCase())) {
                lowered.add(v.toLowerCase());
                out.add(v);
            }
        }
        return String.join(out, ', ');
    }

    public static List<SObject> byIds(String objectName, Set<String> paths, Set<Id> ids, List<String> warnings) {
        if (ids == null || ids.isEmpty()) {
            return new List<SObject>();
        }
        String soql = 'SELECT ' + selectList(objectName, paths, warnings) + ' FROM ' + objectName + ' WHERE Id IN :ids';
        return Database.queryWithBinds(soql, new Map<String, Object>{ 'ids' => ids }, AccessLevel.SYSTEM_MODE);
    }

    /** Parses "Field ASC, Other DESC" into field names. */
    public static List<String> sortFields(String sortOrder) {
        List<String> out = new List<String>();
        if (String.isBlank(sortOrder)) {
            return out;
        }
        for (String part : sortOrder.split(',')) {
            String f = part.trim().split('\\s+')[0];
            if (String.isNotBlank(f)) {
                out.add(f);
            }
        }
        return out;
    }

    /** Returns a validated ORDER BY clause (without the keywords), defaulting to CreatedDate ASC. */
    public static String orderBy(String objectName, String sortOrder, List<String> warnings) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(sortOrder)) {
            for (String part : sortOrder.split(',')) {
                List<String> tokens = part.trim().split('\\s+');
                if (tokens.isEmpty() || String.isBlank(tokens[0])) {
                    continue;
                }
                Schema.DescribeFieldResult fd = DE_Schema.resolvePath(objectName, tokens[0]);
                if (fd == null || !fd.isSortable()) {
                    if (warnings != null) {
                        warnings.add('Sort field ' + tokens[0] + ' is not sortable on ' + objectName + ' and was ignored.');
                    }
                    continue;
                }
                String dir = tokens.size() > 1 && tokens[1].equalsIgnoreCase('DESC') ? 'DESC NULLS LAST' : 'ASC NULLS LAST';
                parts.add(DE_Schema.canonicalPath(objectName, tokens[0]) + ' ' + dir);
            }
        }
        if (parts.isEmpty()) {
            parts.add('CreatedDate ASC');
        }
        parts.add('Id ASC');
        return String.join(parts, ', ');
    }

    /**
     * Records waiting at a distributor's source. Team Active Status is applied in SOQL;
     * field filters are evaluated in Apex by the engine.
     */
    public static List<SObject> sourceCandidates(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, Integer maxRows, List<String> warnings) {
        DE_Distributor__c d = dc.dist;
        String obj = cfg.objectName;
        Map<String, Object> binds = new Map<String, Object>();
        String whereClause;
        if (d.Source_Type__c == 'Field Value') {
            String sf = DE_Schema.canonicalPath(obj, d.Source_Field__c);
            if (sf == null) {
                warnings.add('Source field ' + d.Source_Field__c + ' does not exist on ' + obj + '.');
                return new List<SObject>();
            }
            whereClause = sf + ' = :ready';
            binds.put('ready', d.Source_Ready_Value__c);
        } else {
            Id sourceId = DE_Ids.toId(d.Source_Id__c);
            if (sourceId == null) {
                warnings.add('Distributor ' + d.Name + ' has no valid source.');
                return new List<SObject>();
            }
            whereClause = cfg.assignmentField + ' = :sourceId';
            binds.put('sourceId', sourceId);
        }
        if (String.isNotBlank(cfg.team.Active_Status_Field__c) && !cfg.activeStatusValues.isEmpty()) {
            String af = DE_Schema.canonicalPath(obj, cfg.team.Active_Status_Field__c);
            if (af != null) {
                whereClause += ' AND ' + af + ' IN :activeValues';
                binds.put('activeValues', DE_Conditions.splitValues(cfg.team.Active_Status_Values__c));
            }
        }
        String soql =
            'SELECT ' +
            selectList(obj, requiredPaths(cfg, dc), warnings) +
            ' FROM ' +
            obj +
            ' WHERE ' +
            whereClause +
            ' ORDER BY ' +
            orderBy(obj, d.Sort_Order__c, warnings) +
            ' LIMIT ' +
            Math.max(1, Math.min(2000, maxRows));
        return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /** Count of records waiting at a distributor's source (for the console). */
    public static Integer countAtSource(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc) {
        DE_Distributor__c d = dc.dist;
        Map<String, Object> binds = new Map<String, Object>();
        String whereClause;
        if (d.Source_Type__c == 'Field Value') {
            String sf = DE_Schema.canonicalPath(cfg.objectName, d.Source_Field__c);
            if (sf == null) {
                return 0;
            }
            whereClause = sf + ' = :ready';
            binds.put('ready', d.Source_Ready_Value__c);
        } else {
            Id sourceId = DE_Ids.toId(d.Source_Id__c);
            if (sourceId == null) {
                return 0;
            }
            whereClause = cfg.assignmentField + ' = :sourceId';
            binds.put('sourceId', sourceId);
        }
        return Database.countQueryWithBinds('SELECT COUNT() FROM ' + cfg.objectName + ' WHERE ' + whereClause, binds, AccessLevel.SYSTEM_MODE);
    }
}
