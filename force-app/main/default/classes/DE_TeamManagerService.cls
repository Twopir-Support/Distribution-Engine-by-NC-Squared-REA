/**
 * Team managers (DE_Team_Manager__c): users who may manage a team with the Team Manager or Custom Team Manager
 * permission sets. Runs in system context because permission checks must see every manager row.
 */
public without sharing class DE_TeamManagerService {
    private static Map<Id, Set<Id>> teamsByUser = new Map<Id, Set<Id>>();

    public static String uniqueKey(Id teamId, Id userId) {
        return String.valueOf(teamId) + '|' + String.valueOf(userId);
    }

    /** Teams the user manages (cached per transaction). */
    public static Set<Id> teamIdsManagedBy(Id userId) {
        if (userId == null) {
            return new Set<Id>();
        }
        if (!teamsByUser.containsKey(userId)) {
            Set<Id> ids = new Set<Id>();
            for (DE_Team_Manager__c m : [SELECT Team__c FROM DE_Team_Manager__c WHERE User__c = :userId]) {
                ids.add(m.Team__c);
            }
            teamsByUser.put(userId, ids);
        }
        return teamsByUser.get(userId);
    }

    public static Boolean isManager(Id teamId, Id userId) {
        return teamId != null && teamIdsManagedBy(userId).contains(teamId);
    }

    /** Manager user ids per team. Every requested team is a key, with an empty set when it has no managers. */
    public static Map<Id, Set<Id>> managersOf(Set<Id> teamIds) {
        Map<Id, Set<Id>> out = new Map<Id, Set<Id>>();
        if (teamIds == null) {
            return out;
        }
        for (Id t : teamIds) {
            out.put(t, new Set<Id>());
        }
        for (DE_Team_Manager__c m : [SELECT Team__c, User__c FROM DE_Team_Manager__c WHERE Team__c IN :teamIds ORDER BY CreatedDate]) {
            out.get(m.Team__c).add(m.User__c);
        }
        return out;
    }

    public static void setManagers(Id teamId, List<Id> userIds) {
        setManagers(teamId, userIds == null ? new Set<Id>() : new Set<Id>(userIds));
    }

    /** Replaces the managers of a team with exactly these users. */
    public static void setManagers(Id teamId, Set<Id> userIds) {
        Set<Id> wanted = userIds == null ? new Set<Id>() : new Set<Id>(userIds);
        wanted.remove(null);
        List<DE_Team_Manager__c> remove = new List<DE_Team_Manager__c>();
        Set<Id> existing = new Set<Id>();
        for (DE_Team_Manager__c m : [SELECT Id, User__c FROM DE_Team_Manager__c WHERE Team__c = :teamId]) {
            if (wanted.contains(m.User__c)) {
                existing.add(m.User__c);
            } else {
                remove.add(m);
            }
        }
        List<DE_Team_Manager__c> add = new List<DE_Team_Manager__c>();
        for (Id u : wanted) {
            if (!existing.contains(u)) {
                add.add(new DE_Team_Manager__c(Team__c = teamId, User__c = u, Unique_Key__c = uniqueKey(teamId, u)));
            }
        }
        Database.delete(remove, true, AccessLevel.SYSTEM_MODE);
        Database.insert(add, true, AccessLevel.SYSTEM_MODE);
        teamsByUser.clear();
    }

    /** Copies the managers of one team to another (team clone). */
    public static void copyManagers(Id fromTeamId, Id toTeamId) {
        setManagers(toTeamId, managersOf(new Set<Id>{ fromTeamId }).get(fromTeamId));
    }
}
