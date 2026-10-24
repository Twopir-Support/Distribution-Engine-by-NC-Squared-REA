/**
 * Role checks backed by custom permissions (granted through the permission sets).
 * Admin > System Manager > Team Manager (standard or custom) > User.
 * Custom team managers (DE_Custom_Team_Manager) manage the teams they are listed on, with access to each
 * page and feature set by their persona (DE_PersonaService); standard roles are not affected by personas.
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
        return isSystemManager() || has('DE_Team_Manager') || has('DE_Custom_Team_Manager');
    }

    /** A custom team manager whose access is governed by a persona (no standard manager role on top). */
    public static Boolean isCustomTeamManager() {
        return has('DE_Custom_Team_Manager') && !has('DE_Team_Manager') && !isSystemManager();
    }

    /** Persona gate: always true for standard roles, the persona level for custom team managers. */
    public static Boolean allows(String capability, String minimumLevel) {
        return !isCustomTeamManager() || DE_PersonaService.currentAtLeast(capability, minimumLevel);
    }

    /**
     * System managers always; custom team managers when they manage the team and their persona grants the level.
     * Used for actions that standard team managers cannot perform but a persona can grant.
     */
    public static Boolean systemManagerOrPersona(Id teamId, String capability, String minimumLevel) {
        if (isSystemManager()) {
            return true;
        }
        return isCustomTeamManager() && teamId != null && canManageTeam(teamId) && DE_PersonaService.currentAtLeast(capability, minimumLevel);
    }

    /** Org-level (not team-scoped) variant: system managers, or custom team managers whose persona grants the level. */
    public static Boolean systemManagerOrPersona(String capability, String minimumLevel) {
        return isSystemManager() || (isCustomTeamManager() && DE_PersonaService.currentAtLeast(capability, minimumLevel));
    }

    public static Boolean isUser() {
        return isTeamManager() || has('DE_User');
    }

    /** System managers manage every team; team managers only teams with a DE_Team_Manager__c row for them. */
    public static Boolean canManageTeam(DE_Team__c team) {
        return team != null && canManageTeam(team.Id);
    }

    public static Boolean canManageTeam(Id teamId) {
        if (isSystemManager()) {
            return true;
        }
        return isTeamManager() && DE_TeamManagerService.isManager(teamId, UserInfo.getUserId());
    }

    public static void require(Boolean allowed, String action) {
        if (!allowed) {
            throw new AccessException('You do not have permission to ' + action + '.');
        }
    }
}
