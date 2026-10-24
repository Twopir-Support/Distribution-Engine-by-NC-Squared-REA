/**
 * Personas: capability sets for users with the Distribution Engine Custom Team Manager permission set.
 * Each custom team manager has exactly one persona (DE_User_Persona__c); users without one get the
 * Default persona, which always exists, cannot be renamed and cannot be deleted. Capabilities are stored
 * as JSON (capability key -> level) in DE_Persona__c.Capabilities__c. Anything not granted is not accessible.
 */
public with sharing class DE_PersonaService {
    public class PersonaException extends Exception {
    }

    public static final String DEFAULT_KEY = 'default persona';
    public static final String DEFAULT_NAME = 'Default Persona';
    public static final String PERMISSION_SET = 'DE_Custom_Team_Manager';

    // Capability keys (documented persona permissions).
    public static final String TEST_TOOL = 'testTool';
    public static final String TEAM_LIST = 'teamList';
    public static final String TEAM_SUMMARY = 'teamSummary';
    public static final String TEAM_MEMBERS = 'teamMembers';
    public static final String TEAM_MEMBERS_TOGGLE = 'teamMembersToggle';
    public static final String TEAM_AVAILABILITY = 'teamAvailability';
    public static final String TEAM_PERFORMANCE = 'teamPerformance';
    public static final String DISTRIBUTORS = 'distributors';
    public static final String DISTRIBUTOR_NAME = 'distributorName';
    public static final String DISTRIBUTOR_METHOD = 'distributorMethod';
    public static final String DISTRIBUTOR_SOURCE = 'distributorSource';
    public static final String DISTRIBUTOR_FILTERS = 'distributorFilters';
    public static final String DISTRIBUTOR_MEMBER_FILTERS = 'distributorMemberFilters';
    public static final String DISTRIBUTOR_ACTIVATE = 'distributorActivate';
    public static final String WEIGHTING = 'weighting';
    public static final String CAPS = 'caps';
    public static final String HOLIDAY_REGION = 'holidayRegion';
    public static final String DISTRIBUTION_HOURS = 'distributionHours';
    public static final String SHIFT_PLANNER_SWITCH = 'shiftPlannerSwitch';
    public static final String TRACKING_SLAS = 'trackingSlas';
    public static final String ASSIGNMENT_REJECTION = 'assignmentRejection';
    public static final String POST_ASSIGNMENT = 'postAssignment';
    public static final String TEAM_SETTINGS = 'teamSettings';
    public static final String TEAM_SETTINGS_FILTER = 'teamSettingsFilter';
    public static final String TEAM_SETTINGS_ADVANCED = 'teamSettingsAdvanced';
    public static final String TAG_COLLECTIONS = 'tagCollections';
    public static final String TAG_ASSIGNMENT = 'tagAssignment';
    public static final String OUT_OF_OFFICE = 'outOfOffice';
    public static final String REGIONAL_HOLIDAY = 'regionalHoliday';
    public static final String SHIFTS = 'shifts';
    public static final String DISTRIBUTION_LOGS = 'distributionLogs';
    public static final String ANALYTICS = 'analytics';

    // Levels, lowest first.
    public static final String NO_ACCESS = 'No Access';
    public static final String ACCESS = 'Access';
    public static final String VIEW = 'View';
    public static final String EDIT = 'Edit';
    public static final String CREATE = 'Create';
    public static final String DELETE_LEVEL = 'Delete';
    public static final String CREATE_AND_DELETE = 'Create and Delete';
    public static final String EDIT_CREATE_DELETE = 'Edit, Create and Delete';
    public static final String CREATE_OWN = 'Create Own';
    public static final String VIEW_TEAM = 'View Team';
    public static final String VIEW_OWN = 'View Own';

    public class Capability {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String area;
        @AuraEnabled
        public String parentKey;
        @AuraEnabled
        public List<String> levels;
        @AuraEnabled
        public String defaultLevel;
        Capability(String key, String label, String area, String parentKey, List<String> levels, String defaultLevel) {
            this.key = key;
            this.label = label;
            this.area = area;
            this.parentKey = parentKey;
            this.levels = levels;
            this.defaultLevel = defaultLevel;
        }
    }

    private static List<Capability> model;
    private static Map<String, Capability> byKey;

    /** The capability model in display order. Default levels match the standard Team Manager permission set. */
    public static List<Capability> capabilities() {
        if (model == null) {
            List<String> noAccessAccess = new List<String>{ NO_ACCESS, ACCESS };
            List<String> noViewEdit = new List<String>{ NO_ACCESS, VIEW, EDIT };
            List<String> sub = new List<String>{ NO_ACCESS, EDIT };
            model = new List<Capability>{
                new Capability(TEST_TOOL, 'Test Tool', 'General', null, noAccessAccess, ACCESS),
                new Capability(TEAM_LIST, 'Team List', 'Teams', null, noAccessAccess, ACCESS),
                new Capability(TEAM_SUMMARY, 'Team Summary', 'Teams', null, noAccessAccess, ACCESS),
                new Capability(TEAM_MEMBERS, 'Team Members', 'Teams', null, new List<String>{ NO_ACCESS, VIEW, EDIT_CREATE_DELETE }, EDIT_CREATE_DELETE),
                new Capability(TEAM_MEMBERS_TOGGLE, 'Team Members Toggle', 'Teams', null, new List<String>{ VIEW, EDIT }, EDIT),
                new Capability(TEAM_AVAILABILITY, 'Team Availability', 'Teams', null, new List<String>{ NO_ACCESS, VIEW }, VIEW),
                new Capability(TEAM_PERFORMANCE, 'Team Performance', 'Teams', null, new List<String>{ NO_ACCESS, VIEW }, VIEW),
                new Capability(DISTRIBUTORS, 'Distributors', 'Teams', null, new List<String>{ NO_ACCESS, VIEW, EDIT, CREATE_AND_DELETE }, VIEW),
                new Capability(DISTRIBUTOR_NAME, 'Edit Distributors: Name', 'Teams', DISTRIBUTORS, sub, NO_ACCESS),
                new Capability(DISTRIBUTOR_METHOD, 'Edit Distributors: Method', 'Teams', DISTRIBUTORS, sub, NO_ACCESS),
                new Capability(DISTRIBUTOR_SOURCE, 'Edit Distributors: Source', 'Teams', DISTRIBUTORS, sub, NO_ACCESS),
                new Capability(DISTRIBUTOR_FILTERS, 'Edit Distributors: Distributor Filters', 'Teams', DISTRIBUTORS, sub, NO_ACCESS),
                new Capability(DISTRIBUTOR_MEMBER_FILTERS, 'Edit Distributors: Team Member Filters', 'Teams', DISTRIBUTORS, sub, NO_ACCESS),
                new Capability(DISTRIBUTOR_ACTIVATE, 'Edit Distributors: Activate/Deactivate', 'Teams', DISTRIBUTORS, sub, NO_ACCESS),
                new Capability(WEIGHTING, 'Weighting', 'Teams', null, noViewEdit, EDIT),
                new Capability(CAPS, 'Caps', 'Teams', null, noViewEdit, EDIT),
                new Capability(HOLIDAY_REGION, 'Holiday Region', 'Teams', null, noViewEdit, VIEW),
                new Capability(DISTRIBUTION_HOURS, 'Distribution Hours', 'Teams', null, noViewEdit, EDIT),
                new Capability(SHIFT_PLANNER_SWITCH, 'Switch to Shift Planner', 'Teams', null, sub, NO_ACCESS),
                new Capability(TRACKING_SLAS, 'Tracking and SLAs', 'Teams', null, noViewEdit, VIEW),
                new Capability(ASSIGNMENT_REJECTION, 'Assignment Rejection', 'Teams', null, noViewEdit, VIEW),
                new Capability(POST_ASSIGNMENT, 'Post Assignment', 'Teams', null, noViewEdit, VIEW),
                new Capability(TEAM_SETTINGS, 'Team Settings', 'Teams', null, noViewEdit, VIEW),
                new Capability(TEAM_SETTINGS_FILTER, 'Team Settings: Filter', 'Teams', TEAM_SETTINGS, new List<String>{ VIEW, EDIT }, VIEW),
                new Capability(TEAM_SETTINGS_ADVANCED, 'Team Settings: Advanced Settings', 'Teams', TEAM_SETTINGS, new List<String>{ VIEW, EDIT }, VIEW),
                new Capability(TAG_COLLECTIONS, 'Tag Collections', 'Tags', null, new List<String>{ NO_ACCESS, VIEW, EDIT, CREATE, DELETE_LEVEL }, VIEW),
                new Capability(TAG_ASSIGNMENT, 'Tag Assignment', 'Tags', null, new List<String>{ NO_ACCESS, VIEW, EDIT_CREATE_DELETE }, EDIT_CREATE_DELETE),
                new Capability(OUT_OF_OFFICE, 'Out of Office', 'Availability', null, new List<String>{ CREATE_OWN, VIEW_TEAM, CREATE_AND_DELETE }, CREATE_AND_DELETE),
                new Capability(REGIONAL_HOLIDAY, 'Regional Holiday', 'Availability', null, new List<String>{ NO_ACCESS, VIEW, EDIT_CREATE_DELETE }, VIEW),
                new Capability(SHIFTS, 'Shifts', 'Availability', null, new List<String>{ NO_ACCESS, VIEW, EDIT, CREATE_AND_DELETE }, VIEW),
                new Capability(DISTRIBUTION_LOGS, 'Distribution Logs', 'Logs', null, new List<String>{ VIEW_OWN, VIEW_TEAM, DELETE_LEVEL }, VIEW_TEAM),
                new Capability(ANALYTICS, 'Analytics', 'Analytics', null, noAccessAccess, ACCESS)
            };
            byKey = new Map<String, Capability>();
            for (Capability c : model) {
                byKey.put(c.key, c);
            }
        }
        return model;
    }

    public static Capability capability(String key) {
        capabilities();
        Capability c = byKey.get(key);
        if (c == null) {
            throw new PersonaException('Unknown capability: ' + key);
        }
        return c;
    }

    /** Default capability levels (the standard Team Manager's access). */
    public static Map<String, String> defaultLevels() {
        Map<String, String> out = new Map<String, String>();
        for (Capability c : capabilities()) {
            out.put(c.key, c.defaultLevel);
        }
        return out;
    }

    /** Parses stored JSON, ignoring unknown keys and invalid levels; missing keys fall back to the lowest level. */
    public static Map<String, String> parse(String json) {
        Map<String, String> out = new Map<String, String>();
        Map<String, Object> raw = new Map<String, Object>();
        if (String.isNotBlank(json)) {
            try {
                raw = (Map<String, Object>) System.JSON.deserializeUntyped(json);
            } catch (Exception e) {
                raw = new Map<String, Object>();
            }
        }
        for (Capability c : capabilities()) {
            Object v = raw.get(c.key);
            String level = v == null ? null : String.valueOf(v);
            out.put(c.key, level != null && c.levels.contains(level) ? level : c.levels[0]);
        }
        return out;
    }

    /** Validates and serialises capability levels. */
    public static String serialize(Map<String, String> levels) {
        Map<String, String> clean = new Map<String, String>();
        for (Capability c : capabilities()) {
            String level = levels == null ? null : levels.get(c.key);
            if (level == null) {
                level = c.levels[0];
            }
            if (!c.levels.contains(level)) {
                throw new PersonaException('"' + level + '" is not a valid level for ' + c.label + '.');
            }
            clean.put(c.key, level);
        }
        return System.JSON.serialize(clean);
    }

    /** True when the stored level is at or above the minimum level for the capability. */
    public static Boolean atLeast(Map<String, String> levels, String key, String minimum) {
        Capability c = capability(key);
        Integer need = c.levels.indexOf(minimum);
        if (need < 0) {
            throw new PersonaException('"' + minimum + '" is not a level of ' + c.label + '.');
        }
        String have = levels.get(key);
        Integer got = have == null ? 0 : c.levels.indexOf(have);
        return got >= need;
    }

    // ---------------------------------------------------------------- personas

    /** The Default persona, created on first use. */
    public static DE_Persona__c ensureDefault() {
        List<DE_Persona__c> found = [
            SELECT Id, Name, Is_Default__c, Capabilities__c, Unique_Name__c
            FROM DE_Persona__c
            WHERE Is_Default__c = TRUE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        if (!found.isEmpty()) {
            return found[0];
        }
        DE_Persona__c p = new DE_Persona__c(
            Name = DEFAULT_NAME,
            Unique_Name__c = DEFAULT_KEY,
            Is_Default__c = true,
            Base_Permission_Set__c = PERMISSION_SET,
            Capabilities__c = serialize(defaultLevels())
        );
        Database.insert(p, true, AccessLevel.SYSTEM_MODE);
        return p;
    }

    private static String uniqueKey(String name) {
        return name.trim().toLowerCase().left(80);
    }

    private static void requireUniqueName(String name, Id exceptId) {
        if (String.isBlank(name)) {
            throw new PersonaException('Enter a persona name.');
        }
        String key = uniqueKey(name);
        for (DE_Persona__c p : [SELECT Id FROM DE_Persona__c WHERE Unique_Name__c = :key OR Name = :name.trim()]) {
            if (p.Id != exceptId) {
                throw new PersonaException('Each persona must have a unique name. "' + name.trim() + '" is already used.');
            }
        }
    }

    /** Creates or updates a persona. The Default persona's name cannot change. */
    public static Id save(Id personaId, String name, Map<String, String> levels) {
        DE_Persona__c p;
        if (personaId != null) {
            p = [SELECT Id, Name, Is_Default__c FROM DE_Persona__c WHERE Id = :personaId];
            if (p.Is_Default__c && String.isNotBlank(name) && name.trim() != p.Name) {
                throw new PersonaException('The default persona cannot be renamed.');
            }
        } else {
            p = new DE_Persona__c(Base_Permission_Set__c = PERMISSION_SET, Is_Default__c = false);
        }
        if (!p.Is_Default__c) {
            requireUniqueName(name, personaId);
            p.Name = name.trim();
            p.Unique_Name__c = uniqueKey(name);
        }
        if (levels != null) {
            p.Capabilities__c = serialize(levels);
        }
        Database.upsert(p, true, AccessLevel.USER_MODE);
        return p.Id;
    }

    public static Id rename(Id personaId, String name) {
        return save(personaId, name, null);
    }

    public static Id clonePersona(Id personaId, String newName) {
        DE_Persona__c src = [SELECT Capabilities__c FROM DE_Persona__c WHERE Id = :personaId];
        return save(null, newName, parse(src.Capabilities__c));
    }

    /** Deletes a persona after moving its users to another persona. The Default persona cannot be deleted. */
    public static Integer remove(Id personaId, Id reassignToId) {
        DE_Persona__c p = [SELECT Id, Is_Default__c FROM DE_Persona__c WHERE Id = :personaId];
        if (p.Is_Default__c) {
            throw new PersonaException('The default persona cannot be deleted.');
        }
        if (reassignToId == null || reassignToId == personaId) {
            throw new PersonaException('Choose another persona to reassign this persona\'s users to.');
        }
        List<DE_User_Persona__c> moving = [SELECT Id FROM DE_User_Persona__c WHERE Persona__c = :personaId];
        for (DE_User_Persona__c up : moving) {
            up.Persona__c = reassignToId;
        }
        Database.update(moving, true, AccessLevel.USER_MODE);
        Database.delete(p, true, AccessLevel.USER_MODE);
        return moving.size();
    }

    /** Assigns one persona to each user (bulk). One DE_User_Persona__c per user, keyed by Unique_User__c. */
    public static Integer assign(List<Id> userIds, Id personaId) {
        if (userIds == null || userIds.isEmpty()) {
            return 0;
        }
        if (personaId == null) {
            throw new PersonaException('Choose a persona.');
        }
        Map<String, DE_User_Persona__c> existing = new Map<String, DE_User_Persona__c>();
        Set<String> keys = new Set<String>();
        for (Id u : userIds) {
            keys.add(String.valueOf(u));
        }
        for (DE_User_Persona__c up : [SELECT Id, User__c, Unique_User__c, Persona__c FROM DE_User_Persona__c WHERE Unique_User__c IN :keys]) {
            existing.put(up.Unique_User__c, up);
        }
        List<DE_User_Persona__c> rows = new List<DE_User_Persona__c>();
        for (String k : keys) {
            DE_User_Persona__c up = existing.containsKey(k) ? existing.get(k) : new DE_User_Persona__c(User__c = Id.valueOf(k), Unique_User__c = k);
            up.Persona__c = personaId;
            rows.add(up);
        }
        Database.upsert(rows, true, AccessLevel.USER_MODE);
        cache = null;
        return rows.size();
    }

    // ---------------------------------------------------------------- current user

    private static Map<String, String> cache;

    @TestVisible
    private static void resetCache() {
        cache = null;
    }

    /** Capability levels of the running user (their persona, or the Default persona). */
    public static Map<String, String> currentLevels() {
        if (cache == null) {
            List<DE_User_Persona__c> mine = [
                SELECT Persona__r.Capabilities__c
                FROM DE_User_Persona__c
                WHERE User__c = :UserInfo.getUserId()
                LIMIT 1
            ];
            if (!mine.isEmpty() && mine[0].Persona__r != null) {
                cache = parse(mine[0].Persona__r.Capabilities__c);
            } else {
                // Read only: this can run inside cacheable Aura methods, so the Default persona is not created here.
                List<DE_Persona__c> def = [SELECT Capabilities__c FROM DE_Persona__c WHERE Is_Default__c = TRUE ORDER BY CreatedDate LIMIT 1];
                cache = def.isEmpty() ? defaultLevels() : parse(def[0].Capabilities__c);
            }
        }
        return cache;
    }

    /** The running user's level for a capability. */
    public static String level(String key) {
        capability(key);
        return currentLevels().get(key);
    }

    public static Boolean currentAtLeast(String key, String minimum) {
        return atLeast(currentLevels(), key, minimum);
    }
}
