/**
 * Distribution Teams tab: teams, team members, distributors, caps, SLAs and describe helpers.
 * System Managers (and Admins) edit every team; Team Managers manage members, weights and caps
 * of teams that list them as managers.
 */
public with sharing class DE_AdminController {
    private static final Set<String> STANDARD_OBJECTS = new Set<String>{ 'Lead', 'Case', 'Opportunity', 'Account', 'Contact', 'Task' };

    // ------------------------------------------------------------------ DTOs

    public class CapInput {
        @AuraEnabled
        public DE_Cap__c cap { get; set; }
        @AuraEnabled
        public List<DE_Condition__c> criteria { get; set; }
    }

    public class SlaInput {
        @AuraEnabled
        public DE_SLA__c sla { get; set; }
        @AuraEnabled
        public List<DE_Condition__c> conditions { get; set; }
    }

    public class DistributorInput {
        @AuraEnabled
        public DE_Distributor__c distributor { get; set; }
        @AuraEnabled
        public List<DE_Condition__c> filters { get; set; }
        @AuraEnabled
        public List<DE_Condition__c> memberFilters { get; set; }
        @AuraEnabled
        public List<DE_Condition__c> lookupWhere { get; set; }
        @AuraEnabled
        public List<CapInput> caps { get; set; }
    }

    public class MemberRow {
        @AuraEnabled
        public DE_Team_Member__c record;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Boolean isQueue;
        @AuraEnabled
        public Boolean online;
        @AuraEnabled
        public String toggleReason;
        @AuraEnabled
        public String tags;
        @AuraEnabled
        public Boolean availableNow;
        @AuraEnabled
        public String availability;
        @AuraEnabled
        public Integer today;
        @AuraEnabled
        public String shiftName;
    }

    public class TeamRow {
        @AuraEnabled
        public DE_Team__c team;
        @AuraEnabled
        public Integer members;
        @AuraEnabled
        public Integer activeDistributors;
        @AuraEnabled
        public Integer availableNow;
    }

    public class TeamDetail {
        @AuraEnabled
        public DE_Team__c team;
        @AuraEnabled
        public List<MemberRow> members = new List<MemberRow>();
        @AuraEnabled
        public List<DistributorInput> distributors = new List<DistributorInput>();
        @AuraEnabled
        public List<DE_Condition__c> teamFilters = new List<DE_Condition__c>();
        @AuraEnabled
        public List<DE_Condition__c> dynamicConditions = new List<DE_Condition__c>();
        @AuraEnabled
        public List<CapInput> caps = new List<CapInput>();
        @AuraEnabled
        public List<SlaInput> slas = new List<SlaInput>();
        @AuraEnabled
        public Map<Id, String> ownerNames = new Map<Id, String>();
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public Boolean canManage;
        @AuraEnabled
        public String holiday;
    }

    // ------------------------------------------------------------------ describe helpers

    @AuraEnabled(cacheable=true)
    public static List<DE_Ui.Option> getObjectOptions() {
        List<DE_Ui.Option> out = new List<DE_Ui.Option>();
        for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
            String name = String.valueOf(t);
            if (!STANDARD_OBJECTS.contains(name) && !(name.endsWith('__c') && !name.startsWith('DE_'))) {
                continue;
            }
            Schema.DescribeSObjectResult d = t.getDescribe();
            if (!d.isUpdateable() || !d.isQueryable()) {
                continue;
            }
            out.add(new DE_Ui.Option(d.getLabel() + ' (' + d.getName() + ')', d.getName()));
        }
        out.sort();
        return out;
    }

    /** Fields of an object, one level of parent fields, and (for routed objects) DE classifier paths. */
    @AuraEnabled(cacheable=true)
    public static List<DE_Ui.Option> getFieldOptions(String objectName, Boolean includeClassifier) {
        if (!DE_Schema.objectExists(objectName)) {
            throw DE_Ui.error('Object ' + objectName + ' does not exist.');
        }
        List<DE_Ui.Option> out = new List<DE_Ui.Option>();
        for (Schema.SObjectField f : DE_Schema.fields(objectName).values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!d.isAccessible()) {
                continue;
            }
            out.add(option(d, d.getLabel(), d.getName()));
            if (d.getType() == Schema.DisplayType.REFERENCE && d.getRelationshipName() != null && d.getReferenceTo().size() == 1) {
                String parent = d.getReferenceTo()[0].getDescribe().getName();
                String parentLabel = d.getReferenceTo()[0].getDescribe().getLabel();
                for (Schema.SObjectField pf : DE_Schema.fields(parent).values()) {
                    Schema.DescribeFieldResult pd = pf.getDescribe();
                    if (pd.isAccessible() && pd.getType() != Schema.DisplayType.REFERENCE && pd.getType() != Schema.DisplayType.ADDRESS) {
                        out.add(option(pd, parentLabel + ' > ' + pd.getLabel(), d.getRelationshipName() + '.' + pd.getName()));
                    }
                }
            }
        }
        if (includeClassifier == true) {
            out.add(classifierOption('DE Territory', 'DE.Territory'));
            out.add(classifierOption('DE Stamps (all)', 'DE.Stamps'));
            out.add(classifierOption('DE Email/Website Domain', 'DE.Domain'));
            out.add(classifierOption('DE Personal Email', 'DE.PersonalEmail'));
            out.add(classifierOption('DE Match Confidence', 'DE.MatchConfidence'));
            out.add(classifierOption('DE Matched Account Id', 'DE.MatchedAccount'));
            out.add(classifierOption('DE Matched Account Type', 'DE.MatchedAccount.Type'));
            out.add(classifierOption('DE Matched Account Owner Id', 'DE.MatchedAccount.OwnerId'));
            out.add(classifierOption('DE Matched Contact Id', 'DE.MatchedContact'));
            out.add(classifierOption('DE Matched Lead Id', 'DE.MatchedLead'));
            for (DE_Stamp_Group__c g : [SELECT Name FROM DE_Stamp_Group__c WHERE Object_API_Name__c = :objectName WITH USER_MODE ORDER BY Name]) {
                out.add(classifierOption('DE Stamp Group > ' + g.Name, 'DE.Stamp.' + g.Name));
            }
        }
        out.sort();
        return out;
    }

    private static DE_Ui.Option option(Schema.DescribeFieldResult d, String label, String value) {
        DE_Ui.Option o = new DE_Ui.Option(label + ' (' + value + ')', value);
        o.type = String.valueOf(d.getType());
        if (d.getType() == Schema.DisplayType.PICKLIST || d.getType() == Schema.DisplayType.MULTIPICKLIST) {
            o.picklistValues = new List<String>();
            for (Schema.PicklistEntry e : d.getPicklistValues()) {
                if (e.isActive()) {
                    o.picklistValues.add(e.getValue());
                }
            }
        }
        return o;
    }

    private static DE_Ui.Option classifierOption(String label, String value) {
        DE_Ui.Option o = new DE_Ui.Option(label + ' (' + value + ')', value);
        o.type = 'STRING';
        o.kind = 'classifier';
        return o;
    }

    /** Searches active users and/or queues. kind: User, Queue or Both. */
    @AuraEnabled
    public static List<DE_Ui.Option> searchOwners(String term, String kind, String objectName) {
        List<DE_Ui.Option> out = new List<DE_Ui.Option>();
        String pattern = '%' + (term == null ? '' : String.escapeSingleQuotes(term.trim())) + '%';
        if (kind != 'Queue') {
            for (User u : [
                SELECT Id, Name, Username
                FROM User
                WHERE IsActive = TRUE AND UserType = 'Standard' AND Name LIKE :pattern
                WITH USER_MODE
                ORDER BY Name
                LIMIT 20
            ]) {
                DE_Ui.Option o = new DE_Ui.Option(u.Name + ' · ' + u.Username, u.Id);
                o.kind = 'User';
                out.add(o);
            }
        }
        if (kind != 'User') {
            Set<Id> allowed = null;
            if (String.isNotBlank(objectName)) {
                allowed = new Set<Id>();
                for (QueueSobject q : [SELECT QueueId FROM QueueSobject WHERE SobjectType = :objectName]) {
                    allowed.add(q.QueueId);
                }
            }
            for (Group g : [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name LIKE :pattern ORDER BY Name LIMIT 20]) {
                if (allowed == null || allowed.contains(g.Id)) {
                    DE_Ui.Option o = new DE_Ui.Option(g.Name + ' (queue)', g.Id);
                    o.kind = 'Queue';
                    out.add(o);
                }
            }
        }
        return out;
    }

    @AuraEnabled
    public static Map<Id, String> getOwnerNames(List<Id> ids) {
        return DE_Ui.ownerNames(new Set<Id>(ids));
    }

    @AuraEnabled(cacheable=true)
    public static List<DE_Ui.Option> getShiftOptions() {
        List<DE_Ui.Option> out = new List<DE_Ui.Option>();
        for (DE_Shift__c s : [SELECT Id, Name, Timezone__c FROM DE_Shift__c WITH USER_MODE ORDER BY Name]) {
            out.add(new DE_Ui.Option(s.Name + ' (' + s.Timezone__c + ')', s.Id));
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<DE_Ui.Option> getTimezoneOptions() {
        List<DE_Ui.Option> out = new List<DE_Ui.Option>();
        for (Schema.PicklistEntry e : User.TimeZoneSidKey.getDescribe().getPicklistValues()) {
            out.add(new DE_Ui.Option(e.getLabel(), e.getValue()));
        }
        return out;
    }

    // ------------------------------------------------------------------ teams

    @AuraEnabled
    public static List<TeamRow> getTeams() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view distribution teams');
        try {
            List<DE_Model.TeamConfig> teams = DE_ConfigRepository.load(null, null, true);
            DE_AvailabilityService availability = new DE_AvailabilityService(teams, System.now());
            List<TeamRow> out = new List<TeamRow>();
            for (DE_Model.TeamConfig cfg : teams) {
                TeamRow r = new TeamRow();
                r.team = cfg.team;
                r.members = 0;
                r.availableNow = 0;
                r.activeDistributors = 0;
                Boolean holiday = availability.holidayFor(cfg) != null;
                for (DE_Model.Member m : cfg.members) {
                    if (m.isActive()) {
                        r.members++;
                        if (!holiday && availability.unavailableReason(m, false, false, false) == null) {
                            r.availableNow++;
                        }
                    }
                }
                for (DE_Model.DistributorConfig dc : cfg.distributors) {
                    if (dc.dist.Active__c) {
                        r.activeDistributors++;
                    }
                }
                out.add(r);
            }
            return out;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static TeamDetail getTeamDetail(Id teamId) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view distribution teams');
        try {
            DE_Model.TeamConfig cfg = DE_ConfigRepository.team(teamId, true);
            if (cfg == null) {
                throw DE_Ui.error('This team no longer exists.');
            }
            TeamDetail d = new TeamDetail();
            d.team = cfg.team;
            d.canEdit = DE_Permissions.isSystemManager();
            d.canManage = DE_Permissions.canManageTeam(cfg.team);
            d.teamFilters = cfg.teamFilters;
            d.dynamicConditions = cfg.dynamicMembership;
            DE_AvailabilityService availability = new DE_AvailabilityService(new List<DE_Model.TeamConfig>{ cfg }, System.now());
            d.holiday = availability.holidayFor(cfg);
            Set<Id> memberIds = new Set<Id>();
            Set<Id> ownerIds = new Set<Id>();
            for (DE_Model.Member m : cfg.members) {
                memberIds.add(m.memberId);
            }
            Map<Id, Decimal> today = DE_CapService.logCounts(
                teamId,
                false,
                DE_CapService.windowStart('Daily', null, System.now(), cfg.timezoneSid()),
                memberIds,
                null
            );
            Map<Id, String> shiftNames = new Map<Id, String>();
            for (DE_Shift__c s : [SELECT Id, Name FROM DE_Shift__c WITH USER_MODE]) {
                shiftNames.put(s.Id, s.Name);
            }
            Map<Id, String> names = DE_Ui.ownerNames(memberIds);
            for (DE_Model.Member m : cfg.members) {
                MemberRow r = new MemberRow();
                r.record = m.record;
                r.name = names.containsKey(m.memberId) ? names.get(m.memberId) : String.valueOf(m.memberId);
                r.isQueue = m.isQueue;
                r.online = m.isOnline();
                r.toggleReason = m.agent == null ? null : m.agent.Toggle_Reason__c;
                r.tags = m.agent == null ? null : m.agent.Tags__c;
                String reason = !m.isActive()
                    ? 'Inactive'
                    : (d.holiday != null ? 'Holiday: ' + d.holiday : availability.unavailableReason(m, false, false, false));
                r.availableNow = reason == null;
                r.availability = reason == null ? 'Available' : reason;
                r.today = today.containsKey(m.memberId) ? today.get(m.memberId).intValue() : 0;
                r.shiftName = shiftNames.get(m.record.Member_Hours__c);
                d.members.add(r);
            }
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                DistributorInput di = new DistributorInput();
                di.distributor = dc.dist;
                di.filters = dc.filters;
                di.memberFilters = dc.memberFilters;
                di.lookupWhere = dc.lookupWhere;
                di.caps = new List<CapInput>();
                for (DE_Cap__c c : dc.caps) {
                    di.caps.add(capInput(c, cfg.capCriteria.get(c.Id)));
                }
                d.distributors.add(di);
                for (String f : new List<String>{ dc.dist.Source_Id__c, dc.dist.Default_Owner_Id__c, dc.dist.Reassign_To_Id__c, dc.dist.Reject_To_Id__c }) {
                    Id i = DE_Ids.toId(f);
                    if (i != null) {
                        ownerIds.add(i);
                    }
                }
                ownerIds.addAll(dc.selectedMembers);
            }
            ownerIds.addAll(DE_Ids.parseList(cfg.team.Manager_User_Ids__c));
            d.ownerNames = DE_Ui.ownerNames(ownerIds);
            d.ownerNames.putAll(names);
            for (DE_Cap__c c : cfg.caps) {
                d.caps.add(capInput(c, cfg.capCriteria.get(c.Id)));
            }
            for (DE_SLA__c s : [
                SELECT
                    Id,
                    Name,
                    Team__c,
                    Checkpoint__c,
                    Alert_Type__c,
                    Minutes_After_Assignment__c,
                    Check_After_Field__c,
                    Condition_Logic__c,
                    Stamp_Value__c,
                    Notify_Assignee__c,
                    Notify_Manager__c,
                    Active__c
                FROM DE_SLA__c
                WHERE Team__c = :teamId
                WITH USER_MODE
                ORDER BY Checkpoint__c
            ]) {
                SlaInput si = new SlaInput();
                si.sla = s;
                si.conditions = cfg.slaConditions.containsKey(s.Id) ? cfg.slaConditions.get(s.Id) : new List<DE_Condition__c>();
                d.slas.add(si);
            }
            return d;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    private static CapInput capInput(DE_Cap__c c, List<DE_Condition__c> criteria) {
        CapInput ci = new CapInput();
        ci.cap = c;
        ci.criteria = criteria == null ? new List<DE_Condition__c>() : criteria;
        return ci;
    }

    @AuraEnabled
    public static Id saveTeam(DE_Team__c team, List<DE_Condition__c> filters, List<DE_Condition__c> dynamicConditions) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'edit distribution teams');
        DE_Team__c existing = null;
        Boolean hasDistributors = false;
        if (team.Id != null) {
            existing = [SELECT Id, Object_API_Name__c, Assignment_Field__c FROM DE_Team__c WHERE Id = :team.Id WITH USER_MODE];
            hasDistributors = [SELECT COUNT() FROM DE_Distributor__c WHERE Team__c = :team.Id] > 0;
        }
        List<DE_Condition__c> f = DE_Ui.prepare(filters, 'Team Filter');
        List<DE_Condition__c> dyn = DE_Ui.prepare(dynamicConditions, 'Dynamic Membership');
        DE_Ui.throwIfErrors(DE_ConfigValidator.team(team, existing, hasDistributors, f, dyn));
        Savepoint sp = Database.setSavepoint();
        try {
            team.Object_API_Name__c = DE_Schema.objectName(team.Object_API_Name__c);
            if (team.Id == null) {
                team.Active__c = false;
                if (team.Execution_Order__c == null) {
                    AggregateResult ar = [SELECT MAX(Execution_Order__c) m FROM DE_Team__c];
                    Decimal m = (Decimal) ar.get('m');
                    team.Execution_Order__c = (m == null ? 0 : m) + 10;
                }
            }
            Database.upsert(team, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Team__c', team.Id, new Set<String>{ 'Team Filter' }, 'Team Filter', f);
            DE_Ui.replaceConditions('Team__c', team.Id, new Set<String>{ 'Dynamic Membership' }, 'Dynamic Membership', dyn);
            return team.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void setTeamActive(Id teamId, Boolean active) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'activate teams');
        try {
            Database.update(new DE_Team__c(Id = teamId, Active__c = active), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void saveTeamOrder(List<Id> teamIds) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'reorder teams');
        List<DE_Team__c> updates = new List<DE_Team__c>();
        Integer order = 10;
        for (Id i : teamIds) {
            updates.add(new DE_Team__c(Id = i, Execution_Order__c = order));
            order += 10;
        }
        try {
            Database.update(updates, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteTeam(Id teamId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'delete teams');
        Savepoint sp = Database.setSavepoint();
        try {
            List<Id> distIds = new List<Id>(new Map<Id, DE_Distributor__c>([SELECT Id FROM DE_Distributor__c WHERE Team__c = :teamId]).keySet());
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Team__c = :teamId OR Distributor__c IN :distIds], true, AccessLevel.USER_MODE);
            DE_Ui.deleteAll([SELECT Id FROM DE_Cap__c WHERE Team__c = :teamId OR Distributor__c IN :distIds], true, AccessLevel.USER_MODE);
            DE_Ui.deleteAll([SELECT Id FROM DE_Rotation_State__c WHERE Team__c = :teamId], true, AccessLevel.SYSTEM_MODE);
            Database.delete(new DE_Team__c(Id = teamId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    /** Clones a team with its members, distributors, conditions, caps and SLAs. The clone is inactive. */
    @AuraEnabled
    public static Id cloneTeam(Id teamId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'clone teams');
        Savepoint sp = Database.setSavepoint();
        try {
            DE_Model.TeamConfig cfg = DE_ConfigRepository.team(teamId, true);
            DE_Team__c t = cfg.team.clone(false, true, false, false);
            t.Name = (cfg.team.Name + ' (copy)').left(80);
            t.Active__c = false;
            t.Rotation_Sequence__c = 0;
            t.Total_Assignments__c = 0;
            t.Last_Assigned_At__c = null;
            Database.insert(t, true, AccessLevel.USER_MODE);
            List<DE_Team_Member__c> members = new List<DE_Team_Member__c>();
            for (DE_Model.Member m : cfg.members) {
                DE_Team_Member__c c = m.record.clone(false, true, false, false);
                c.Team__c = t.Id;
                c.Unique_Key__c = t.Id + '|' + m.memberId;
                members.add(c);
            }
            Database.insert(members, true, AccessLevel.USER_MODE);
            List<DE_Condition__c> conds = new List<DE_Condition__c>();
            for (DE_Condition__c c : cfg.teamFilters) {
                conds.add(cloneCondition(c, 'Team__c', t.Id));
            }
            for (DE_Condition__c c : cfg.dynamicMembership) {
                conds.add(cloneCondition(c, 'Team__c', t.Id));
            }
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                Id newId = cloneDistributorInto(cfg, dc, t.Id, dc.dist.Name);
            }
            cloneCaps(cfg.caps, cfg.capCriteria, 'Team__c', t.Id);
            for (DE_SLA__c s : cfg.slas) {
                DE_SLA__c ns = s.clone(false, true, false, false);
                ns.Team__c = t.Id;
                Database.insert(ns, true, AccessLevel.USER_MODE);
                for (DE_Condition__c c : cfg.slaConditions.get(s.Id)) {
                    conds.add(cloneCondition(c, 'SLA__c', ns.Id));
                }
            }
            Database.insert(conds, true, AccessLevel.USER_MODE);
            return t.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    private static DE_Condition__c cloneCondition(DE_Condition__c c, String parentField, Id parentId) {
        DE_Condition__c n = new DE_Condition__c(
            Sequence__c = c.Sequence__c,
            Field_API_Name__c = c.Field_API_Name__c,
            Operator__c = c.Operator__c,
            Value__c = c.Value__c,
            Purpose__c = c.Purpose__c
        );
        n.put(parentField, parentId);
        return n;
    }

    private static void cloneCaps(List<DE_Cap__c> caps, Map<Id, List<DE_Condition__c>> criteria, String parentField, Id parentId) {
        for (DE_Cap__c c : caps) {
            DE_Cap__c n = c.clone(false, true, false, false);
            n.Team__c = null;
            n.Distributor__c = null;
            n.put(parentField, parentId);
            Database.insert(n, true, AccessLevel.USER_MODE);
            List<DE_Condition__c> conds = new List<DE_Condition__c>();
            for (DE_Condition__c x : criteria.containsKey(c.Id) ? criteria.get(c.Id) : new List<DE_Condition__c>()) {
                conds.add(cloneCondition(x, 'Cap__c', n.Id));
            }
            Database.insert(conds, true, AccessLevel.USER_MODE);
        }
    }

    private static Id cloneDistributorInto(DE_Model.TeamConfig cfg, DE_Model.DistributorConfig dc, Id teamId, String name) {
        DE_Distributor__c d = dc.dist.clone(false, true, false, false);
        d.Team__c = teamId;
        d.Name = name.left(80);
        d.Active__c = false;
        Database.insert(d, true, AccessLevel.USER_MODE);
        List<DE_Condition__c> conds = new List<DE_Condition__c>();
        for (List<DE_Condition__c> conditionGroup : new List<List<DE_Condition__c>>{ dc.filters, dc.memberFilters, dc.lookupWhere }) {
            for (DE_Condition__c c : conditionGroup) {
                conds.add(cloneCondition(c, 'Distributor__c', d.Id));
            }
        }
        Database.insert(conds, true, AccessLevel.USER_MODE);
        cloneCaps(dc.caps, cfg.capCriteria, 'Distributor__c', d.Id);
        return d.Id;
    }

    // ------------------------------------------------------------------ members

    private static DE_Team__c teamFor(Id teamId) {
        return [SELECT Id, Name, Team_Type__c, Manager_User_Ids__c, Object_API_Name__c FROM DE_Team__c WHERE Id = :teamId WITH USER_MODE];
    }

    @AuraEnabled
    public static void addMembers(Id teamId, List<Id> memberIds) {
        DE_Team__c team = teamFor(teamId);
        DE_Permissions.require(DE_Permissions.canManageTeam(team), 'manage members of ' + team.Name);
        Boolean q2q = team.Team_Type__c == 'Queue to Queue';
        List<DE_Team_Member__c> rows = new List<DE_Team_Member__c>();
        Set<Id> users = new Set<Id>();
        for (Id m : memberIds) {
            if (q2q != DE_Ids.isQueue(m)) {
                throw DE_Ui.error(q2q ? 'Queue to Queue teams can only have queue members.' : 'Only users can be added to this team.');
            }
            rows.add(
                new DE_Team_Member__c(
                    Team__c = teamId,
                    User__c = q2q ? null : m,
                    Queue_Id__c = q2q ? String.valueOf(m) : null,
                    Active__c = true,
                    Weight__c = 1,
                    Unique_Key__c = teamId + '|' + m
                )
            );
            if (!q2q) {
                users.add(m);
            }
        }
        try {
            Database.upsert(rows, DE_Team_Member__c.Unique_Key__c, true, AccessLevel.USER_MODE);
            DE_AgentService.ensure(users);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void saveMembers(List<DE_Team_Member__c> members) {
        if (members == null || members.isEmpty()) {
            return;
        }
        Set<Id> ids = new Map<Id, DE_Team_Member__c>(members).keySet();
        Set<Id> teamIds = new Set<Id>();
        for (DE_Team_Member__c m : [SELECT Team__c FROM DE_Team_Member__c WHERE Id IN :ids WITH USER_MODE]) {
            teamIds.add(m.Team__c);
        }
        for (DE_Team__c t : [SELECT Id, Name, Manager_User_Ids__c FROM DE_Team__c WHERE Id IN :teamIds WITH USER_MODE]) {
            DE_Permissions.require(DE_Permissions.canManageTeam(t), 'manage members of ' + t.Name);
        }
        List<DE_Team_Member__c> updates = new List<DE_Team_Member__c>();
        for (DE_Team_Member__c m : members) {
            updates.add(new DE_Team_Member__c(Id = m.Id, Active__c = m.Active__c, Weight__c = m.Weight__c, Member_Hours__c = m.Member_Hours__c));
        }
        try {
            Database.update(updates, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void removeMember(Id memberId) {
        DE_Team_Member__c m = [SELECT Id, Team__c FROM DE_Team_Member__c WHERE Id = :memberId WITH USER_MODE];
        DE_Permissions.require(DE_Permissions.canManageTeam(teamFor(m.Team__c)), 'remove team members');
        try {
            Database.delete(m, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static Map<String, Integer> syncDynamicMembers(Id teamId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'sync dynamic members');
        try {
            return DE_DynamicMembers.sync(teamId);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ distributors

    @AuraEnabled
    public static Id saveDistributor(DistributorInput input) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'edit distributors');
        DE_Distributor__c d = input.distributor;
        DE_Team__c team = [SELECT Id, Object_API_Name__c, Name FROM DE_Team__c WHERE Id = :d.Team__c WITH USER_MODE];
        List<DE_Distributor__c> siblings = [SELECT Id, Type__c FROM DE_Distributor__c WHERE Team__c = :team.Id WITH USER_MODE];
        Set<Id> memberIds = new Set<Id>();
        for (DE_Team_Member__c m : [SELECT User__c, Queue_Id__c FROM DE_Team_Member__c WHERE Team__c = :team.Id WITH USER_MODE]) {
            memberIds.add(m.User__c != null ? m.User__c : DE_Ids.toId(m.Queue_Id__c));
        }
        List<DE_Condition__c> filters = DE_Ui.prepare(input.filters, 'Distributor Filter');
        List<DE_Condition__c> memberFilters = DE_Ui.prepare(input.memberFilters, 'Member Filter');
        List<DE_Condition__c> lookupWhere = DE_Ui.prepare(input.lookupWhere, 'Lookup Where');
        List<DE_Cap__c> caps = new List<DE_Cap__c>();
        if (input.caps != null) {
            for (CapInput c : input.caps) {
                caps.add(c.cap);
            }
        }
        DE_Ui.throwIfErrors(DE_ConfigValidator.distributor(d, team, siblings, filters, memberFilters, lookupWhere, caps, memberIds));
        Savepoint sp = Database.setSavepoint();
        try {
            if (d.Id == null) {
                d.Active__c = false;
                if (d.Order__c == null) {
                    d.Order__c = (siblings.size() + 1) * 10;
                }
            }
            Database.upsert(d, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Distributor__c', d.Id, new Set<String>{ 'Distributor Filter' }, 'Distributor Filter', filters);
            DE_Ui.replaceConditions('Distributor__c', d.Id, new Set<String>{ 'Member Filter' }, 'Member Filter', memberFilters);
            DE_Ui.replaceConditions('Distributor__c', d.Id, new Set<String>{ 'Lookup Where' }, 'Lookup Where', lookupWhere);
            replaceCaps('Distributor__c', d.Id, input.caps);
            return d.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void setDistributorActive(Id distributorId, Boolean active) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'activate distributors');
        try {
            Database.update(new DE_Distributor__c(Id = distributorId, Active__c = active), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void saveDistributorOrder(List<Id> distributorIds) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'reorder distributors');
        List<DE_Distributor__c> updates = new List<DE_Distributor__c>();
        Integer order = 10;
        for (Id i : distributorIds) {
            updates.add(new DE_Distributor__c(Id = i, Order__c = order));
            order += 10;
        }
        try {
            Database.update(updates, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static Id cloneDistributor(Id distributorId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'clone distributors');
        Savepoint sp = Database.setSavepoint();
        try {
            DE_Distributor__c d = [SELECT Team__c, Name, Type__c FROM DE_Distributor__c WHERE Id = :distributorId WITH USER_MODE];
            if (d.Type__c == 'Manual') {
                throw DE_Ui.error('A team can only have one Manual distributor.');
            }
            DE_Model.TeamConfig cfg = DE_ConfigRepository.team(d.Team__c, true);
            return cloneDistributorInto(cfg, cfg.distributor(distributorId), d.Team__c, d.Name + ' (copy)');
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteDistributor(Id distributorId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'delete distributors');
        Savepoint sp = Database.setSavepoint();
        try {
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Distributor__c = :distributorId], true, AccessLevel.USER_MODE);
            List<DE_Cap__c> caps = [SELECT Id FROM DE_Cap__c WHERE Distributor__c = :distributorId];
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Cap__c IN :caps], true, AccessLevel.USER_MODE);
            Database.delete(caps, true, AccessLevel.USER_MODE);
            Database.delete(new DE_Distributor__c(Id = distributorId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ caps and SLAs

    private static void replaceCaps(String parentField, Id parentId, List<CapInput> caps) {
        List<DE_Cap__c> existing = Database.queryWithBinds(
            'SELECT Id FROM DE_Cap__c WHERE ' + parentField + ' = :parentId',
            new Map<String, Object>{ 'parentId' => parentId },
            AccessLevel.USER_MODE
        );
        if (!existing.isEmpty()) {
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Cap__c IN :existing], true, AccessLevel.USER_MODE);
            Database.delete(existing, true, AccessLevel.USER_MODE);
        }
        if (caps == null) {
            return;
        }
        for (CapInput ci : caps) {
            DE_Cap__c c = ci.cap.clone(false, true, false, false);
            c.Team__c = null;
            c.Distributor__c = null;
            c.put(parentField, parentId);
            if (String.isBlank(c.Name)) {
                c.Name = (c.Period__c + ' cap').left(80);
            }
            if (c.Active__c == null) {
                c.Active__c = true;
            }
            Database.insert(c, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Cap__c', c.Id, new Set<String>{ 'Cap Criteria' }, 'Cap Criteria', ci.criteria);
        }
    }

    @AuraEnabled
    public static void saveTeamCaps(Id teamId, List<CapInput> caps) {
        DE_Team__c team = teamFor(teamId);
        DE_Permissions.require(DE_Permissions.canManageTeam(team), 'change caps for ' + team.Name);
        List<String> errors = new List<String>();
        if (caps != null && caps.size() > 3) {
            errors.add('A team can have at most three cap periods.');
        }
        for (CapInput c : caps == null ? new List<CapInput>() : caps) {
            errors.addAll(DE_ConfigValidator.cap(c.cap));
            if (c.cap.Period__c == 'Criteria' && c.cap.Criteria_Source__c != 'Distributor Filters' && c.criteria != null) {
                String err = DE_Conditions.validate(team.Object_API_Name__c, DE_Ui.prepare(c.criteria, 'Cap Criteria'), c.cap.Criteria_Logic__c);
                if (err != null) {
                    errors.add('Criteria cap: ' + err);
                }
            }
        }
        DE_Ui.throwIfErrors(errors);
        Savepoint sp = Database.setSavepoint();
        try {
            replaceCaps('Team__c', teamId, caps);
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void saveSlas(Id teamId, List<SlaInput> slas) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'change SLAs');
        DE_Team__c team = teamFor(teamId);
        List<String> errors = new List<String>();
        List<DE_SLA__c> rows = new List<DE_SLA__c>();
        if (slas != null && slas.size() > 3) {
            errors.add('A team can have at most three SLA checkpoints (per stamp).');
        }
        for (SlaInput s : slas == null ? new List<SlaInput>() : slas) {
            errors.addAll(DE_ConfigValidator.sla(s.sla, team.Object_API_Name__c, DE_Ui.prepare(s.conditions, 'SLA Condition')));
            rows.add(s.sla);
        }
        String order = DE_ConfigValidator.slaOrder(rows);
        if (order != null) {
            errors.add(order);
        }
        DE_Ui.throwIfErrors(errors);
        Savepoint sp = Database.setSavepoint();
        try {
            List<DE_SLA__c> existing = [SELECT Id FROM DE_SLA__c WHERE Team__c = :teamId WITH USER_MODE];
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE SLA__c IN :existing], true, AccessLevel.USER_MODE);
            Database.delete(existing, true, AccessLevel.USER_MODE);
            for (SlaInput s : slas == null ? new List<SlaInput>() : slas) {
                DE_SLA__c n = s.sla.clone(false, true, false, false);
                n.Team__c = teamId;
                if (String.isBlank(n.Name)) {
                    n.Name = 'SLA ' + n.Checkpoint__c;
                }
                Database.insert(n, true, AccessLevel.USER_MODE);
                DE_Ui.replaceConditions('SLA__c', n.Id, new Set<String>{ 'SLA Condition' }, 'SLA Condition', s.conditions);
            }
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ distribution viewer

    public class ViewerNode {
        @AuraEnabled
        public String source;
        @AuraEnabled
        public String teamName;
        @AuraEnabled
        public Boolean teamActive;
        @AuraEnabled
        public String distributorName;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String method;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public Integer filters;
        @AuraEnabled
        public Integer members;
    }

    @AuraEnabled
    public static List<ViewerNode> getDistributionViewer() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view the distribution viewer');
        List<ViewerNode> out = new List<ViewerNode>();
        List<DE_Model.TeamConfig> teams = DE_ConfigRepository.load(null, null, true);
        Set<Id> sourceIds = new Set<Id>();
        for (DE_Model.TeamConfig cfg : teams) {
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                Id s = DE_Ids.toId(dc.dist.Source_Id__c);
                if (s != null) {
                    sourceIds.add(s);
                }
            }
        }
        Map<Id, String> names = DE_Ui.ownerNames(sourceIds);
        for (DE_Model.TeamConfig cfg : teams) {
            Integer activeMembers = 0;
            for (DE_Model.Member m : cfg.members) {
                if (m.isActive()) {
                    activeMembers++;
                }
            }
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                ViewerNode n = new ViewerNode();
                Id s = DE_Ids.toId(dc.dist.Source_Id__c);
                n.source = dc.dist.Source_Type__c == 'Field Value'
                    ? cfg.objectName + '.' + dc.dist.Source_Field__c + ' = ' + dc.dist.Source_Ready_Value__c
                    : (s == null ? 'Any ' + cfg.objectName : names.get(s));
                n.teamName = cfg.team.Name;
                n.teamActive = cfg.team.Active__c;
                n.distributorName = dc.dist.Name;
                n.type = dc.type();
                n.method = dc.method();
                n.active = dc.dist.Active__c;
                n.filters = dc.filters.size() + cfg.teamFilters.size();
                n.members = dc.selectedMembers.isEmpty() ? activeMembers : dc.selectedMembers.size();
                out.add(n);
            }
        }
        return out;
    }
}
