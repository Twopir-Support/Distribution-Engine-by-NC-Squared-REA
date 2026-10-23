/**
 * Role checks backed by custom permissions (granted through the four permission sets).
 * Admin > System Manager > Team Manager > User.
 */
public with sharing class DE_Permissions {
    public class AccessException extends Exception {
    }

    @TestVisible
    private static Set<String> overrides;

    private static Boolean has(String permission) {
        if (overrides != null) {
            return overrides.contains(permission);
        }
        return FeatureManagement.checkPermission(permission);
    }

    public static Boolean isAdmin() {
        return has('DE_Admin');
    }

    public static Boolean isSystemManager() {
        return isAdmin() || has('DE_System_Manager');
    }

    public static Boolean isTeamManager() {
        return isSystemManager() || has('DE_Team_Manager');
    }

    public static Boolean isUser() {
        return isTeamManager() || has('DE_User');
    }

    /** System managers manage every team; team managers only teams that list them as managers. */
    public static Boolean canManageTeam(DE_Team__c team) {
        if (isSystemManager()) {
            return true;
        }
        return isTeamManager() && team != null && DE_Ids.parseList(team.Manager_User_Ids__c).contains(UserInfo.getUserId());
    }

    public static void require(Boolean allowed, String action) {
        if (!allowed) {
            throw new AccessException('You do not have permission to ' + action + '.');
        }
    }
}
