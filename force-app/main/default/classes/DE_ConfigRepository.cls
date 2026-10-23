/**
 * Loads team configuration (distributors, members, caps, SLAs and conditions) for the engine.
 * Runs in system context: routing is an automated process that must see all configuration
 * regardless of the user whose action started it (for example a web-to-lead guest user).
 */
public without sharing class DE_ConfigRepository {
    private static final String CONDITION_FIELDS = 'Id, Team__c, Distributor__c, SLA__c, Cap__c, Purpose__c, Sequence__c, Field_API_Name__c, Operator__c, Value__c';

    /** Active teams for one object (or all objects when objectName is null), in execution order. */
    public static List<DE_Model.TeamConfig> activeTeams(String objectName) {
        return load(null, objectName, false);
    }

    public static DE_Model.TeamConfig team(Id teamId, Boolean includeInactive) {
        List<DE_Model.TeamConfig> teams = load(new Set<Id>{ teamId }, null, includeInactive);
        return teams.isEmpty() ? null : teams[0];
    }

    public static List<DE_Model.TeamConfig> load(Set<Id> teamIds, String objectName, Boolean includeInactive) {
        String soql =
            'SELECT Id, Name, Object_API_Name__c, Active__c, Execution_Order__c, Team_Type__c, Assignment_Field__c, Filter_Logic__c, ' +
            'Team_Hours__c, Holiday_Region__c, Round_Robin_Level__c, Load_Balancing_Level__c, Load_Balancing_Type__c, Balance_By__c, ' +
            'Balance_Field__c, Active_Status_Field__c, Active_Status_Values__c, Apply_Active_Status_To_SLAs__c, Weighting_Mode__c, ' +
            'Tag_Weights__c, Default_Tag_Weight__c, Respect_Hours_For_Triggers__c, Rejection_Limit__c, Rejections_Per_Day__c, ' +
            'Action_Tracking_Enabled__c, Action_Field__c, Tracked_Actions__c, Action_Respect_Hours__c, Track_Action_From_Any_User__c, ' +
            'Auto_Action_Activity_Types__c, SLA_Respect_Hours__c, Object_Sync_Enabled__c, Manager_User_Ids__c, ' +
            'Dynamic_Members_Enabled__c, Dynamic_Members_Logic__c, Rotation_Sequence__c, Total_Assignments__c, Last_Assigned_At__c, ' +
            '(SELECT Id, Name, Team__c, User__c, Queue_Id__c, Active__c, Weight__c, Member_Hours__c, Dynamic__c, Unique_Key__c FROM Members__r ORDER BY Name), ' +
            '(SELECT Id, Name, Team__c, Order__c, Active__c, Type__c, Method__c, Source_Type__c, Source_Id__c, Source_Field__c, ' +
            'Source_Ready_Value__c, Source_After_Value__c, Filter_Logic__c, Sort_Order__c, Assign_To__c, Selected_Member_Ids__c, ' +
            'Exclude_Members_Field__c, Assign_If_Unavailable__c, Assign_If_Offline__c, Weighting_Enabled__c, Respect_Team_Caps__c, ' +
            'Sticky_Enabled__c, Sticky_Field__c, Sticky_Days__c, Sticky_Level__c, Sticky_Retain_Unavailable__c, Sticky_Retain_Offline__c, ' +
            'Sticky_Only__c, Sticky_Cap_Behaviour__c, Lookup_Object__c, Lookup_Record_Field__c, Lookup_Target_Field__c, ' +
            'Lookup_Where_Logic__c, Lookup_Assign_Field__c, Lookup_Tie_Breaker_Field__c, Lookup_Tie_Breaker_Direction__c, ' +
            'Related_Field__c, Related_Secondary_Field__c, Dynamic_Owner_Field__c, Default_Owner_Id__c, Pull_Count__c, ' +
            'Field_Updates__c, Send_Email__c, Send_Notification__c, SLA_Enabled__c, Auto_Reassign__c, Reassign_From_SLA__c, ' +
            'Reassign_To_Id__c, Reassign_Field_Updates__c, Toggle_User_Off__c, Remove_Sticky_On_Reassign__c, Rejection_Enabled__c, ' +
            'Reject_To_Id__c, Reject_Field_Updates__c, Replace_Rejected__c, Treat_Manual_As_Rejection__c, Description__c ' +
            'FROM Distributors__r ORDER BY Order__c, Name), ' +
            '(SELECT Id, Name, Team__c, Checkpoint__c, Alert_Type__c, Minutes_After_Assignment__c, Check_After_Field__c, ' +
            'Condition_Logic__c, Stamp_Value__c, Notify_Assignee__c, Notify_Manager__c, Active__c FROM SLAs__r ORDER BY Checkpoint__c) ' +
            'FROM DE_Team__c WHERE Id != null';
        if (teamIds != null) {
            soql += ' AND Id IN :teamIds';
        }
        if (objectName != null) {
            soql += ' AND Object_API_Name__c = :objectName';
        }
        if (!includeInactive) {
            soql += ' AND Active__c = true';
        }
        soql += ' ORDER BY Execution_Order__c NULLS LAST, Name';
        List<DE_Team__c> teams = Database.query(soql);
        return build(teams, includeInactive);
    }

    private static List<DE_Model.TeamConfig> build(List<DE_Team__c> teams, Boolean includeInactive) {
        List<DE_Model.TeamConfig> out = new List<DE_Model.TeamConfig>();
        if (teams.isEmpty()) {
            return out;
        }
        Set<Id> teamIds = new Set<Id>();
        Set<Id> distIds = new Set<Id>();
        Set<Id> slaIds = new Set<Id>();
        Set<Id> shiftIds = new Set<Id>();
        Set<Id> userIds = new Set<Id>();
        for (DE_Team__c t : teams) {
            teamIds.add(t.Id);
            if (t.Team_Hours__c != null) {
                shiftIds.add(t.Team_Hours__c);
            }
            for (DE_Distributor__c d : t.Distributors__r) {
                distIds.add(d.Id);
            }
            for (DE_SLA__c s : t.SLAs__r) {
                slaIds.add(s.Id);
            }
            for (DE_Team_Member__c m : t.Members__r) {
                if (m.Member_Hours__c != null) {
                    shiftIds.add(m.Member_Hours__c);
                }
                if (m.User__c != null) {
                    userIds.add(m.User__c);
                }
            }
        }

        List<DE_Cap__c> caps = [
            SELECT Id, Name, Team__c, Distributor__c, Period__c, Custom_Length__c, Default_Cap__c, Tag_Caps__c, Criteria_Logic__c, Criteria_Source__c, Active__c
            FROM DE_Cap__c
            WHERE (Team__c IN :teamIds OR Distributor__c IN :distIds) AND Active__c = TRUE
            ORDER BY Name
        ];
        Set<Id> capIds = new Map<Id, DE_Cap__c>(caps).keySet();
        List<DE_Condition__c> conditions = Database.query(
            'SELECT ' +
                CONDITION_FIELDS +
                ' FROM DE_Condition__c WHERE Team__c IN :teamIds OR Distributor__c IN :distIds OR SLA__c IN :slaIds OR Cap__c IN :capIds ORDER BY Sequence__c'
        );
        Map<Id, DE_Shift__c> shifts = new Map<Id, DE_Shift__c>([SELECT Id, Name, Timezone__c, Schedule__c FROM DE_Shift__c WHERE Id IN :shiftIds]);
        Map<Id, User> users = new Map<Id, User>([SELECT Id, Name, IsActive, ManagerId, Email, TimeZoneSidKey FROM User WHERE Id IN :userIds]);
        Map<Id, DE_Agent__c> agents = agentsByUser(userIds);

        Map<Id, List<DE_Condition__c>> byParent = new Map<Id, List<DE_Condition__c>>();
        for (DE_Condition__c c : conditions) {
            Id parent = c.Cap__c != null ? c.Cap__c : (c.SLA__c != null ? c.SLA__c : (c.Distributor__c != null ? c.Distributor__c : c.Team__c));
            if (!byParent.containsKey(parent)) {
                byParent.put(parent, new List<DE_Condition__c>());
            }
            byParent.get(parent).add(c);
        }

        for (DE_Team__c t : teams) {
            DE_Model.TeamConfig cfg = new DE_Model.TeamConfig();
            cfg.team = t;
            cfg.objectName = DE_Schema.objectName(t.Object_API_Name__c);
            cfg.assignmentField = String.isBlank(t.Assignment_Field__c) ? 'OwnerId' : t.Assignment_Field__c.trim();
            cfg.teamCalendar = DE_ShiftCalendar.fromShift(shifts.get(t.Team_Hours__c));
            cfg.tagWeights = parseWeights(t.Tag_Weights__c);
            for (String v : DE_Conditions.splitValues(t.Active_Status_Values__c)) {
                cfg.activeStatusValues.add(v.toLowerCase());
            }
            for (DE_Condition__c c : nvl(byParent.get(t.Id))) {
                if (c.Purpose__c == 'Dynamic Membership') {
                    cfg.dynamicMembership.add(c);
                } else {
                    cfg.teamFilters.add(c);
                }
            }
            for (DE_Distributor__c d : t.Distributors__r) {
                if (!includeInactive && !d.Active__c) {
                    continue;
                }
                DE_Model.DistributorConfig dc = new DE_Model.DistributorConfig();
                dc.dist = d;
                for (DE_Condition__c c : nvl(byParent.get(d.Id))) {
                    if (c.Purpose__c == 'Member Filter') {
                        dc.memberFilters.add(c);
                    } else if (c.Purpose__c == 'Lookup Where') {
                        dc.lookupWhere.add(c);
                    } else {
                        dc.filters.add(c);
                    }
                }
                if (d.Assign_To__c == 'Selected Members') {
                    dc.selectedMembers = DE_Ids.parseList(d.Selected_Member_Ids__c);
                }
                cfg.distributors.add(dc);
            }
            for (DE_Cap__c cap : caps) {
                cfg.capCriteria.put(cap.Id, nvl(byParent.get(cap.Id)));
                if (cap.Team__c == t.Id) {
                    cfg.caps.add(cap);
                } else {
                    DE_Model.DistributorConfig dc = cfg.distributor(cap.Distributor__c);
                    if (dc != null) {
                        dc.caps.add(cap);
                    }
                }
            }
            for (DE_SLA__c s : t.SLAs__r) {
                if (s.Active__c) {
                    cfg.slas.add(s);
                    cfg.slaConditions.put(s.Id, nvl(byParent.get(s.Id)));
                }
            }
            for (DE_Team_Member__c m : t.Members__r) {
                DE_Model.Member mem = new DE_Model.Member();
                mem.record = m;
                mem.isQueue = m.User__c == null;
                mem.memberId = mem.isQueue ? DE_Ids.toId(m.Queue_Id__c) : m.User__c;
                if (mem.memberId == null) {
                    continue;
                }
                mem.user = users.get(m.User__c);
                mem.agent = agents.get(m.User__c);
                DE_Shift__c own = shifts.get(m.Member_Hours__c);
                mem.calendar = own != null ? DE_ShiftCalendar.fromShift(own) : cfg.teamCalendar;
                mem.tags = mem.agent == null ? new Set<String>() : DE_Model.parseTags(mem.agent.Tags__c);
                mem.weight = memberWeight(cfg, m, mem.tags);
                cfg.members.add(mem);
            }
            out.add(cfg);
        }
        return out;
    }

    private static List<DE_Condition__c> nvl(List<DE_Condition__c> items) {
        return items == null ? new List<DE_Condition__c>() : items;
    }

    public static Map<String, Decimal> parseWeights(String value) {
        Map<String, Decimal> out = new Map<String, Decimal>();
        Map<String, String> pairs = DE_Model.parsePairs(value);
        for (String k : pairs.keySet()) {
            try {
                out.put(k, Decimal.valueOf(pairs.get(k)));
            } catch (Exception e) {
                continue;
            }
        }
        return out;
    }

    /** Individual weight, or for tag weighting the highest weight among the member's tags. */
    public static Decimal memberWeight(DE_Model.TeamConfig cfg, DE_Team_Member__c m, Set<String> tags) {
        Decimal w;
        if (cfg.team.Weighting_Mode__c == 'Tag') {
            for (String tag : tags) {
                Decimal tw = cfg.tagWeights.get(tag);
                if (tw != null && (w == null || tw > w)) {
                    w = tw;
                }
            }
            if (w == null) {
                w = cfg.team.Default_Tag_Weight__c;
            }
        } else {
            w = m.Weight__c;
        }
        if (w == null) {
            w = 1;
        }
        return Math.min(4, Math.max(0.25, w));
    }

    public static Map<Id, DE_Agent__c> agentsByUser(Set<Id> userIds) {
        Map<Id, DE_Agent__c> out = new Map<Id, DE_Agent__c>();
        for (DE_Agent__c a : [
            SELECT Id, User__c, Online__c, Toggle_Reason__c, Toggle_Until__c, Tags__c, Last_Status_Change__c
            FROM DE_Agent__c
            WHERE User__c IN :userIds
        ]) {
            out.put(a.User__c, a);
        }
        return out;
    }
}
