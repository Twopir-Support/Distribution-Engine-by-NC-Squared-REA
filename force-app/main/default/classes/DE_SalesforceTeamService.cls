/**
 * Role assignment ("Salesforce Teams"): instead of changing the owner, the selected member is added to the
 * record's Account, Opportunity or Case team with a role (and, optionally, the member's default team).
 *
 * Team objects are created dynamically so the class compiles and runs in orgs where Account Teams,
 * Opportunity Teams or Case Teams are not enabled; there the assignment is reported as an error.
 */
public without sharing class DE_SalesforceTeamService {
    public static final Set<String> SUPPORTED = new Set<String>{ 'account', 'opportunity', 'case' };

    public class Result {
        public Id teamMemberId;
        public String error;
        public String role;
    }

    public static Boolean isSupported(String objectName) {
        return objectName != null && SUPPORTED.contains(objectName.toLowerCase()) && teamObject(objectName) != null;
    }

    /** API name of the team member object for a record object, when it exists in this org. */
    public static String teamObject(String objectName) {
        String lower = objectName == null ? '' : objectName.toLowerCase();
        String api = lower == 'account' ? 'AccountTeamMember' : lower == 'opportunity' ? 'OpportunityTeamMember' : lower == 'case' ? 'CaseTeamMember' : null;
        return api != null && Schema.getGlobalDescribe().containsKey(api.toLowerCase()) ? api : null;
    }

    /** Parses "Account=Edit;Opportunity=Read;Case=None" into a lower-case key map. */
    public static Map<String, String> accessLevels(String value) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(value)) {
            return out;
        }
        for (String part : value.split('[;\\n,]')) {
            if (part.contains('=')) {
                out.put(part.substringBefore('=').trim().toLowerCase(), part.substringAfter('=').trim());
            }
        }
        return out;
    }

    /**
     * Adds each decision's assignee to the record's team. Decisions must be for one object and already have
     * an assignee user. Returns one result per record id; failed records carry an error message.
     */
    public static Map<Id, Result> addMembers(String objectName, DE_Model.DistributorConfig dc, List<DE_Model.Decision> decisions) {
        Map<Id, Result> out = new Map<Id, Result>();
        String api = teamObject(objectName);
        for (DE_Model.Decision d : decisions) {
            Result r = new Result();
            r.role = dc.dist.Team_Role__c;
            out.put(d.recordId, r);
            if (api == null) {
                r.error = 'Role assignment needs ' + objectName + ' teams, which are not enabled in this org.';
            } else if (d.assigneeId == null || d.assigneeId.getSobjectType() != User.SObjectType) {
                r.error = 'Role assignment can only add users to a team.';
            }
        }
        if (api == null) {
            return out;
        }
        String lower = objectName.toLowerCase();
        Map<String, String> access = accessLevels(dc.dist.Team_Access_Level__c);
        Id caseRoleId = null;
        if (lower == 'case' && String.isNotBlank(dc.dist.Team_Role__c)) {
            List<SObject> roles = Database.query(
                'SELECT Id FROM CaseTeamRole WHERE Name = \'' + String.escapeSingleQuotes(dc.dist.Team_Role__c) + '\' LIMIT 1'
            );
            if (roles.isEmpty()) {
                for (Result r : out.values()) {
                    r.error = r.error == null ? 'Case team role "' + dc.dist.Team_Role__c + '" does not exist.' : r.error;
                }
                return out;
            }
            caseRoleId = roles[0].Id;
        }
        List<SObject> rows = new List<SObject>();
        List<Id> rowRecord = new List<Id>();
        Schema.SObjectType memberType = Schema.getGlobalDescribe().get(api.toLowerCase());
        for (DE_Model.Decision d : decisions) {
            if (out.get(d.recordId).error != null) {
                continue;
            }
            if (String.isNotBlank(dc.dist.Team_Role__c)) {
                rows.add(memberRow(memberType, lower, d.recordId, d.assigneeId, dc.dist.Team_Role__c, caseRoleId, access));
                rowRecord.add(d.recordId);
            }
        }
        if (dc.dist.Assign_Default_Team__c == true && lower != 'case') {
            Set<Id> owners = new Set<Id>();
            for (DE_Model.Decision d : decisions) {
                if (out.get(d.recordId).error == null) {
                    owners.add(d.assigneeId);
                }
            }
            Map<Id, List<SObject>> defaults = defaultTeams(lower, owners);
            for (DE_Model.Decision d : decisions) {
                if (out.get(d.recordId).error != null || !defaults.containsKey(d.assigneeId)) {
                    continue;
                }
                for (SObject def : defaults.get(d.assigneeId)) {
                    rows.add(copyDefault(memberType, lower, d.recordId, def));
                    rowRecord.add(d.recordId);
                }
            }
        }
        List<Database.SaveResult> saves = Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < saves.size(); i++) {
            Result r = out.get(rowRecord[i]);
            if (saves[i].isSuccess()) {
                if (r.teamMemberId == null) {
                    r.teamMemberId = saves[i].getId();
                }
            } else if (r.error == null) {
                r.error = 'Could not add the team member: ' + saves[i].getErrors()[0].getMessage();
            }
        }
        for (DE_Model.Decision d : decisions) {
            Result r = out.get(d.recordId);
            if (r.error == null && r.teamMemberId == null) {
                r.error = 'The assignee has no default team and no team role is set.';
            }
        }
        return out;
    }

    private static SObject memberRow(Schema.SObjectType t, String lower, Id recordId, Id userId, String role, Id caseRoleId, Map<String, String> access) {
        SObject row = t.newSObject();
        if (lower == 'case') {
            row.put('ParentId', recordId);
            row.put('MemberId', userId);
            row.put('TeamRoleId', caseRoleId);
            return row;
        }
        row.put('UserId', userId);
        row.put('TeamMemberRole', role);
        if (lower == 'account') {
            row.put('AccountId', recordId);
            row.put('AccountAccessLevel', access.containsKey('account') ? access.get('account') : 'Read');
            row.put('OpportunityAccessLevel', access.containsKey('opportunity') ? access.get('opportunity') : 'None');
            row.put('CaseAccessLevel', access.containsKey('case') ? access.get('case') : 'None');
            if (access.containsKey('contact')) {
                row.put('ContactAccessLevel', access.get('contact'));
            }
        } else {
            row.put('OpportunityId', recordId);
            row.put('OpportunityAccessLevel', access.containsKey('opportunity') ? access.get('opportunity') : 'Read');
        }
        return row;
    }

    /** The default Account team (UserAccountTeamMember) or Opportunity team (UserTeamMember) of each owner. */
    private static Map<Id, List<SObject>> defaultTeams(String lower, Set<Id> owners) {
        Map<Id, List<SObject>> out = new Map<Id, List<SObject>>();
        String api = lower == 'account' ? 'UserAccountTeamMember' : 'UserTeamMember';
        if (owners.isEmpty() || !Schema.getGlobalDescribe().containsKey(api.toLowerCase())) {
            return out;
        }
        String fields = lower == 'account'
            ? 'OwnerId, UserId, TeamMemberRole, AccountAccessLevel, OpportunityAccessLevel, CaseAccessLevel'
            : 'OwnerId, UserId, TeamMemberRole, OpportunityAccessLevel';
        for (
            SObject s : Database.queryWithBinds(
                'SELECT ' + fields + ' FROM ' + api + ' WHERE OwnerId IN :owners',
                new Map<String, Object>{ 'owners' => owners },
                AccessLevel.SYSTEM_MODE
            )
        ) {
            Id owner = (Id) s.get('OwnerId');
            if (!out.containsKey(owner)) {
                out.put(owner, new List<SObject>());
            }
            out.get(owner).add(s);
        }
        return out;
    }

    private static SObject copyDefault(Schema.SObjectType t, String lower, Id recordId, SObject def) {
        SObject row = t.newSObject();
        row.put('UserId', def.get('UserId'));
        row.put('TeamMemberRole', def.get('TeamMemberRole'));
        if (lower == 'account') {
            row.put('AccountId', recordId);
            row.put('AccountAccessLevel', def.get('AccountAccessLevel'));
            row.put('OpportunityAccessLevel', def.get('OpportunityAccessLevel'));
            row.put('CaseAccessLevel', def.get('CaseAccessLevel'));
        } else {
            row.put('OpportunityId', recordId);
            row.put('OpportunityAccessLevel', def.get('OpportunityAccessLevel'));
        }
        return row;
    }
}
