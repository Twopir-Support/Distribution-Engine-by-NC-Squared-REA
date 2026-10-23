/**
 * Dynamic team members: keeps membership in sync with conditions on User fields.
 * Matching active users are added (or reactivated); dynamic members who no longer match are deactivated.
 * Members added manually are never changed.
 */
public without sharing class DE_DynamicMembers {
    public static Integer syncAll() {
        Integer changes = 0;
        for (DE_Team__c t : [SELECT Id FROM DE_Team__c WHERE Dynamic_Members_Enabled__c = TRUE LIMIT 20]) {
            Map<String, Integer> r = sync(t.Id);
            changes += r.get('added') + r.get('deactivated') + r.get('reactivated');
        }
        return changes;
    }

    public static Map<String, Integer> sync(Id teamId) {
        Map<String, Integer> result = new Map<String, Integer>{ 'added' => 0, 'deactivated' => 0, 'reactivated' => 0 };
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(teamId, true);
        if (cfg == null || cfg.team.Dynamic_Members_Enabled__c != true || cfg.dynamicMembership.isEmpty() || cfg.isQueueToQueue()) {
            return result;
        }
        Set<String> paths = DE_Conditions.recordPaths(cfg.dynamicMembership);
        paths.add('Id');
        paths.add('Name');
        String soql = 'SELECT ' + DE_RecordQuery.selectList('User', paths, null) + ' FROM User WHERE IsActive = true AND UserType = \'Standard\' LIMIT 5000';
        List<User> users = Database.query(soql, AccessLevel.SYSTEM_MODE);
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        Set<Id> matching = new Set<Id>();
        for (User u : users) {
            if (DE_Conditions.matches(u, cfg.dynamicMembership, cfg.team.Dynamic_Members_Logic__c, ctx, null)) {
                matching.add(u.Id);
            }
        }
        Map<Id, DE_Team_Member__c> existing = new Map<Id, DE_Team_Member__c>();
        for (DE_Model.Member m : cfg.members) {
            if (!m.isQueue) {
                existing.put(m.memberId, m.record);
            }
        }
        List<DE_Team_Member__c> upserts = new List<DE_Team_Member__c>();
        for (Id u : matching) {
            DE_Team_Member__c m = existing.get(u);
            if (m == null) {
                upserts.add(
                    new DE_Team_Member__c(Team__c = teamId, User__c = u, Active__c = true, Dynamic__c = true, Weight__c = 1, Unique_Key__c = teamId + '|' + u)
                );
                result.put('added', result.get('added') + 1);
            } else if (m.Dynamic__c && !m.Active__c) {
                upserts.add(new DE_Team_Member__c(Id = m.Id, Active__c = true));
                result.put('reactivated', result.get('reactivated') + 1);
            }
        }
        for (Id u : existing.keySet()) {
            DE_Team_Member__c m = existing.get(u);
            if (m.Dynamic__c && m.Active__c && !matching.contains(u)) {
                upserts.add(new DE_Team_Member__c(Id = m.Id, Active__c = false));
                result.put('deactivated', result.get('deactivated') + 1);
            }
        }
        if (!upserts.isEmpty()) {
            Database.upsert(upserts, false, AccessLevel.SYSTEM_MODE);
            DE_AgentService.ensure(matching);
        }
        DE_RunLogger.log(
            'Dynamic Members',
            'Success',
            users.size(),
            0,
            0,
            cfg.team.Name + ': ' + result.get('added') + ' added, ' + result.get('reactivated') + ' reactivated, ' + result.get('deactivated') + ' deactivated.'
        );
        return result;
    }
}
