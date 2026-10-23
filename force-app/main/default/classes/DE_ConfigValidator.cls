/**
 * Validates configuration before it is saved from the admin screens. Every method returns a list of
 * user-facing error messages (empty = valid) so the UI can show them all at once.
 */
public without sharing class DE_ConfigValidator {
    public static final Map<String, Set<String>> METHODS_BY_TYPE = new Map<String, Set<String>>{
        'Standard' => new Set<String>{ 'Round Robin', 'Load Balancing', 'Lookup Owner', 'Related Owner' },
        'Pull' => new Set<String>{ 'Round Robin' },
        'Manual' => new Set<String>{ 'Round Robin', 'Load Balancing', 'Lookup Owner', 'Related Owner', 'Dynamic Owner', 'Current Owner' },
        'Trigger' => new Set<String>{ 'Round Robin', 'Load Balancing', 'Dynamic Owner', 'Current Owner' }
    };
    public static final Integer MAX_TRIGGER_FILTERS = 5;

    private static void add(List<String> errors, String message) {
        if (message != null) {
            errors.add(message);
        }
    }

    // ------------------------------------------------------------------ teams

    public static List<String> team(DE_Team__c t, DE_Team__c existing, Boolean hasDistributors, List<DE_Condition__c> filters, List<DE_Condition__c> dynamicConditions) {
        List<String> errors = new List<String>();
        if (String.isBlank(t.Name)) {
            errors.add('Enter a team name.');
        }
        String obj = t.Object_API_Name__c;
        if (String.isBlank(obj) || !DE_Schema.objectExists(obj)) {
            errors.add('Choose an object that exists in this org.');
            return errors;
        }
        if (existing != null && !DE_Schema.objectName(existing.Object_API_Name__c).equalsIgnoreCase(DE_Schema.objectName(obj))) {
            errors.add('The distribution object cannot be changed after the team is created.');
        }
        String field = String.isBlank(t.Assignment_Field__c) ? 'OwnerId' : t.Assignment_Field__c;
        if (!DE_Schema.hasField(obj, field) || !(DE_Schema.isUserReference(obj, field) || field.equalsIgnoreCase('OwnerId'))) {
            errors.add('Assignment field ' + field + ' must be OwnerId or a User lookup on ' + obj + '.');
        } else if (!DE_Schema.field(obj, field).isUpdateable()) {
            errors.add('Assignment field ' + field + ' is not updateable.');
        }
        String oldField = existing == null || String.isBlank(existing.Assignment_Field__c) ? 'OwnerId' : existing.Assignment_Field__c;
        if (existing != null && hasDistributors && !oldField.equalsIgnoreCase(field)) {
            errors.add('Remove the team\'s distributors before changing the assignment field.');
        }
        if (t.Team_Type__c == 'Queue to Queue' && (!field.equalsIgnoreCase('OwnerId') || !DE_Schema.supportsQueues(obj))) {
            errors.add('Queue to Queue teams need an object whose owner can be a queue.');
        }
        if (String.isNotBlank(t.Active_Status_Field__c)) {
            if (!DE_Schema.hasField(obj, t.Active_Status_Field__c)) {
                errors.add('Active Status field ' + t.Active_Status_Field__c + ' does not exist on ' + obj + '.');
            } else if (DE_Conditions.splitValues(t.Active_Status_Values__c).isEmpty()) {
                errors.add('Enter at least one Active Status value.');
            }
        }
        if (t.Balance_By__c == 'Field Value') {
            Schema.DescribeFieldResult bf = DE_Schema.field(obj, t.Balance_Field__c);
            if (bf == null || !DE_Schema.isNumeric(bf.getType())) {
                errors.add('Balance field must be a numeric field on ' + obj + '.');
            }
        }
        if (t.Action_Tracking_Enabled__c == true) {
            if (!DE_Schema.hasField(obj, t.Action_Field__c)) {
                errors.add('Choose an action field that exists on ' + obj + '.');
            }
            if (DE_Conditions.splitValues(t.Tracked_Actions__c).isEmpty()) {
                errors.add('Enter at least one action to track.');
            }
        }
        if (t.Rejection_Limit__c == 'Limited' && (t.Rejections_Per_Day__c == null || t.Rejections_Per_Day__c < 0)) {
            errors.add('Enter the number of rejections allowed per day.');
        }
        add(errors, weights(t.Tag_Weights__c));
        for (Id m : DE_Ids.parseList(t.Manager_User_Ids__c)) {
            add(errors, DE_Ids.ownerError(m, false));
        }
        if (filters != null && !filters.isEmpty()) {
            add(errors, prefixed('Team filters: ', DE_Conditions.validate(obj, filters, t.Filter_Logic__c)));
        }
        if (t.Dynamic_Members_Enabled__c == true) {
            if (dynamicConditions == null || dynamicConditions.isEmpty()) {
                errors.add('Add at least one dynamic membership condition on User fields.');
            } else {
                add(errors, prefixed('Dynamic members: ', DE_Conditions.validate('User', dynamicConditions, t.Dynamic_Members_Logic__c)));
            }
        }
        return errors;
    }

    private static String prefixed(String prefix, String message) {
        return message == null ? null : prefix + message;
    }

    public static String weights(String spec) {
        Map<String, String> pairs = DE_Model.parsePairs(spec);
        for (String k : pairs.keySet()) {
            if (!k.contains(':')) {
                return 'Tag weight "' + k + '" must be written as Collection:Tag=Weight.';
            }
            Decimal w;
            try {
                w = Decimal.valueOf(pairs.get(k));
            } catch (Exception e) {
                w = null;
            }
            if (w == null || w < 0.25 || w > 4) {
                return 'Tag weight for ' + k + ' must be between 0.25 and 4.';
            }
        }
        return null;
    }

    // ------------------------------------------------------------------ distributors

    public static List<String> distributor(
        DE_Distributor__c d,
        DE_Team__c team,
        List<DE_Distributor__c> siblings,
        List<DE_Condition__c> filters,
        List<DE_Condition__c> memberFilters,
        List<DE_Condition__c> lookupWhere,
        List<DE_Cap__c> caps,
        Set<Id> memberIds
    ) {
        List<String> errors = new List<String>();
        String obj = DE_Schema.objectName(team.Object_API_Name__c);
        String type = d.Type__c == null ? 'Standard' : d.Type__c;
        String method = d.Method__c == null ? 'Round Robin' : d.Method__c;
        if (String.isBlank(d.Name)) {
            errors.add('Enter a distributor name.');
        }
        if (!METHODS_BY_TYPE.containsKey(type)) {
            errors.add('Choose a distributor type.');
            return errors;
        }
        if (!METHODS_BY_TYPE.get(type).contains(method)) {
            errors.add(method + ' is not available for ' + type + ' distributors.');
        }
        if (type == 'Manual') {
            for (DE_Distributor__c s : siblings) {
                if (s.Type__c == 'Manual' && s.Id != d.Id) {
                    errors.add('A team can only have one Manual distributor.');
                    break;
                }
            }
        }
        if (type == 'Standard' || type == 'Pull') {
            String src = d.Source_Type__c;
            if (src == 'Queue') {
                if (!DE_Ids.isQueue(d.Source_Id__c)) {
                    errors.add('Choose a source queue.');
                } else if ([SELECT COUNT() FROM QueueSobject WHERE QueueId = :DE_Ids.toId(d.Source_Id__c) AND SobjectType = :obj] == 0) {
                    errors.add('The source queue does not support ' + obj + ' records.');
                }
            } else if (src == 'User') {
                if (!DE_Ids.isUser(d.Source_Id__c)) {
                    errors.add('Choose a source (holding) user.');
                } else if (memberIds.contains(DE_Ids.toId(d.Source_Id__c))) {
                    errors.add('The source user cannot also be a member of this team.');
                }
            } else if (src == 'Field Value') {
                Schema.DescribeFieldResult sf = DE_Schema.field(obj, d.Source_Field__c);
                if (sf == null || sf.getType() != Schema.DisplayType.PICKLIST) {
                    errors.add('Choose a picklist source field on ' + obj + '.');
                }
                if (String.isBlank(d.Source_Ready_Value__c)) {
                    errors.add('Enter the ready value of the source field.');
                }
            } else {
                errors.add(type + ' distributors need a Queue, User or Field Value source.');
            }
        }
        if (type == 'Trigger' && filters != null && filters.size() > MAX_TRIGGER_FILTERS) {
            errors.add('Trigger distributors support at most ' + MAX_TRIGGER_FILTERS + ' filters.');
        }
        if (filters != null && !filters.isEmpty()) {
            add(errors, prefixed('Filters: ', DE_Conditions.validate(obj, filters, d.Filter_Logic__c)));
        }
        if (memberFilters != null && !memberFilters.isEmpty()) {
            add(errors, prefixed('Team member filter: ', DE_Conditions.validate(obj, memberFilters, null)));
        }
        if (String.isNotBlank(d.Sort_Order__c)) {
            List<String> warnings = new List<String>();
            DE_RecordQuery.orderBy(obj, d.Sort_Order__c, warnings);
            if (!warnings.isEmpty()) {
                errors.add(warnings[0]);
            }
        }
        if (d.Assign_To__c == 'Selected Members' && DE_Ids.parseList(d.Selected_Member_Ids__c).isEmpty()) {
            errors.add('Select at least one member.');
        }
        if (String.isNotBlank(d.Exclude_Members_Field__c) && !DE_Schema.hasField(obj, d.Exclude_Members_Field__c)) {
            errors.add('Exclude members field ' + d.Exclude_Members_Field__c + ' does not exist on ' + obj + '.');
        }
        if (d.Sticky_Enabled__c == true) {
            if (DE_Schema.resolvePath(obj, d.Sticky_Field__c) == null) {
                errors.add('Choose a sticky match field that exists on ' + obj + '.');
            }
            if (d.Sticky_Days__c == null || d.Sticky_Days__c < 1) {
                errors.add('Sticky period must be at least one day.');
            }
        }
        if (method == 'Lookup Owner') {
            String target = d.Lookup_Object__c;
            if (!DE_Schema.objectExists(target)) {
                errors.add('Choose the object to look up.');
            } else {
                if (DE_Schema.resolvePath(obj, d.Lookup_Record_Field__c) == null) {
                    errors.add('Lookup record field does not exist on ' + obj + '.');
                }
                if (DE_Schema.resolvePath(target, d.Lookup_Target_Field__c) == null) {
                    errors.add('Lookup target field does not exist on ' + target + '.');
                }
                String assign = String.isBlank(d.Lookup_Assign_Field__c) ? 'OwnerId' : d.Lookup_Assign_Field__c;
                if (DE_Schema.resolvePath(target, assign) == null) {
                    errors.add('Assign-to field ' + assign + ' does not exist on ' + target + '.');
                }
                if (lookupWhere != null && !lookupWhere.isEmpty()) {
                    add(errors, prefixed('Lookup where: ', DE_Conditions.validate(target, lookupWhere, d.Lookup_Where_Logic__c)));
                }
            }
        }
        if (method == 'Related Owner') {
            if (String.isBlank(d.Related_Field__c)) {
                errors.add('Choose the related object to assign from.');
            }
            for (String p : new List<String>{ d.Related_Field__c, d.Related_Secondary_Field__c }) {
                if (String.isNotBlank(p) && !DE_Conditions.isDetailPath(p) && DE_Schema.resolvePath(obj, p) == null) {
                    errors.add('Related field ' + p + ' does not exist on ' + obj + '.');
                }
            }
        }
        if (method == 'Dynamic Owner' && DE_Schema.resolvePath(obj, d.Dynamic_Owner_Field__c) == null) {
            errors.add('Choose the field that holds the owner Id.');
        }
        add(errors, DE_Ids.ownerError(d.Default_Owner_Id__c, true));
        if (d.Auto_Reassign__c == true) {
            add(errors, DE_Ids.ownerError(d.Reassign_To_Id__c, true));
            if (String.isBlank(d.Reassign_To_Id__c)) {
                errors.add('Choose a queue or user to reassign to.');
            }
        }
        if (d.Rejection_Enabled__c == true) {
            add(errors, DE_Ids.ownerError(d.Reject_To_Id__c, true));
            if (String.isBlank(d.Reject_To_Id__c)) {
                errors.add('Choose a queue or user to reject to.');
            }
        }
        add(errors, prefixed('Update fields on assignment: ', DE_FieldUpdates.validate(obj, d.Field_Updates__c)));
        add(errors, prefixed('Update fields on reassignment: ', DE_FieldUpdates.validate(obj, d.Reassign_Field_Updates__c)));
        add(errors, prefixed('Update fields on rejection: ', DE_FieldUpdates.validate(obj, d.Reject_Field_Updates__c)));
        if (type == 'Pull' && (d.Pull_Count__c == null || d.Pull_Count__c < 1 || d.Pull_Count__c > 100)) {
            errors.add('Number of records to pull must be between 1 and 100.');
        }
        if (caps != null) {
            for (DE_Cap__c c : caps) {
                errors.addAll(cap(c));
            }
        }
        return errors;
    }

    // ------------------------------------------------------------------ caps, SLAs, shifts

    public static List<String> cap(DE_Cap__c c) {
        List<String> errors = new List<String>();
        String p = c.Period__c;
        if (String.isBlank(p)) {
            errors.add('Choose a cap period.');
            return errors;
        }
        Decimal len = c.Custom_Length__c;
        if (p == 'Custom Minutes' && (len == null || len < 5 || len > 180)) {
            errors.add('Custom minute caps must be between 5 and 180 minutes.');
        }
        if (p == 'Custom Hours' && (len == null || len < 1 || len > 168)) {
            errors.add('Custom hour caps must be between 1 and 168 hours.');
        }
        if (p == 'Custom Days' && (len == null || len < 1 || len > 31)) {
            errors.add('Custom day caps must be between 1 and 31 days.');
        }
        if (c.Default_Cap__c != null && c.Default_Cap__c < 0) {
            errors.add('Caps cannot be negative.');
        }
        if (String.isNotBlank(c.Tag_Caps__c)) {
            for (String line : c.Tag_Caps__c.split('\\n')) {
                if (String.isBlank(line)) {
                    continue;
                }
                if (!line.contains('=') || !line.substringBefore('=').contains(':')) {
                    errors.add('Tag cap "' + line.trim() + '" must be written as Collection:Tag=Cap.');
                    continue;
                }
                String v = line.substringAfter('=').trim();
                if (String.isNotBlank(v) && !v.isNumeric()) {
                    errors.add('Tag cap "' + line.trim() + '" must be a whole number or blank for unlimited.');
                }
            }
        }
        return errors;
    }

    public static List<String> sla(DE_SLA__c s, String objectName, List<DE_Condition__c> conditions) {
        List<String> errors = new List<String>();
        if (s.Checkpoint__c == null || s.Checkpoint__c < 1 || s.Checkpoint__c > 3) {
            errors.add('Checkpoint must be 1, 2 or 3.');
        }
        String type = s.Alert_Type__c == null ? 'Time Checkpoint' : s.Alert_Type__c;
        if (type != 'Custom Date/Time' && (s.Minutes_After_Assignment__c == null || s.Minutes_After_Assignment__c <= 0)) {
            errors.add('Enter the minutes after assignment.');
        }
        if (type == 'Continuous Field Monitoring' && s.Minutes_After_Assignment__c > 20160) {
            errors.add('Continuous monitoring is limited to two weeks (20160 minutes).');
        }
        if (type == 'Custom Date/Time') {
            Schema.DescribeFieldResult f = DE_Schema.resolvePath(objectName, s.Check_After_Field__c);
            if (f == null || (f.getType() != Schema.DisplayType.DATETIME && f.getType() != Schema.DisplayType.DATE)) {
                errors.add('Choose a date or date/time field for SLA Check After.');
            }
        }
        if (conditions != null && !conditions.isEmpty()) {
            add(errors, prefixed('SLA missed if: ', DE_Conditions.validate(objectName, conditions, s.Condition_Logic__c)));
        }
        return errors;
    }

    /** Checkpoints must be in chronological order (Time Checkpoints). */
    public static String slaOrder(List<DE_SLA__c> slas) {
        Decimal last = 0;
        for (DE_SLA__c s : slas) {
            if ((s.Alert_Type__c == null || s.Alert_Type__c == 'Time Checkpoint') && s.Minutes_After_Assignment__c != null) {
                if (s.Minutes_After_Assignment__c <= last) {
                    return 'SLA checkpoints must be in chronological order.';
                }
                last = s.Minutes_After_Assignment__c;
            }
        }
        return null;
    }

    public static List<String> shift(DE_Shift__c s) {
        List<String> errors = new List<String>();
        if (String.isBlank(s.Name)) {
            errors.add('Enter a shift name.');
        }
        if (String.isBlank(s.Timezone__c) || TimeZone.getTimeZone(s.Timezone__c).getID() == 'GMT' && s.Timezone__c != 'GMT') {
            errors.add('Choose a valid timezone.');
        }
        add(errors, DE_ShiftCalendar.validate(s.Schedule__c));
        return errors;
    }

    public static List<String> objectSync(DE_Object_Sync__c a, List<DE_Condition__c> conditions) {
        List<String> errors = new List<String>();
        if (!DE_Schema.objectExists(a.Parent_Object__c)) {
            errors.add('Choose the distribution object.');
        }
        if (!DE_Schema.objectExists(a.Child_Object__c) || !DE_Schema.hasField(a.Child_Object__c, 'OwnerId')) {
            errors.add('Choose a related object that has an owner.');
            return errors;
        }
        Schema.DescribeFieldResult f = DE_Schema.field(a.Child_Object__c, a.Lookup_Field__c);
        if (f == null || f.getType() != Schema.DisplayType.REFERENCE) {
            errors.add('Choose the lookup field on ' + a.Child_Object__c + ' that points to ' + a.Parent_Object__c + '.');
        }
        if (conditions != null && !conditions.isEmpty()) {
            add(errors, prefixed('Filters: ', DE_Conditions.validate(a.Child_Object__c, conditions, a.Filter_Logic__c)));
        }
        return errors;
    }
}
