/**
 * Action tracking: measures time from assignment to the first tracked action (speed to lead).
 * An action is a change of the team's action field to a tracked value by the assignee
 * (or by anyone when "Track action from any user" is on), or an activity of a configured type
 * logged against the record (auto action).
 */
public without sharing class DE_ActionTracking {
    private static Map<String, List<DE_Team__c>> teamsByObject = new Map<String, List<DE_Team__c>>();

    private static List<DE_Team__c> trackingTeams(String objectName) {
        String key = objectName.toLowerCase();
        if (!teamsByObject.containsKey(key)) {
            teamsByObject.put(
                key,
                [
                    SELECT Id, Name, Object_API_Name__c, Action_Field__c, Tracked_Actions__c, Action_Respect_Hours__c, Track_Action_From_Any_User__c, Auto_Action_Activity_Types__c
                    FROM DE_Team__c
                    WHERE Object_API_Name__c = :objectName AND Action_Tracking_Enabled__c = TRUE AND Active__c = TRUE
                ]
            );
        }
        return teamsByObject.get(key);
    }

    private static Set<String> tracked(DE_Team__c t) {
        Set<String> out = new Set<String>();
        for (String v : DE_Conditions.splitValues(t.Tracked_Actions__c)) {
            out.add(v.toLowerCase());
        }
        return out;
    }

    public static void beforeUpdate(String objectName, List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<DE_Team__c> teams = trackingTeams(objectName);
        if (teams.isEmpty()) {
            return;
        }
        Map<Id, DE_Team__c> teamById = new Map<Id, DE_Team__c>(teams);
        Set<String> candidates = new Set<String>();
        for (SObject r : newRecords) {
            for (DE_Team__c t : teams) {
                if (String.isBlank(t.Action_Field__c) || !DE_Schema.hasField(objectName, t.Action_Field__c)) {
                    continue;
                }
                Object nv = r.get(t.Action_Field__c);
                Object ov = oldMap.get(r.Id).get(t.Action_Field__c);
                if (nv != null && nv != ov && tracked(t).contains(String.valueOf(nv).toLowerCase())) {
                    candidates.add(String.valueOf(r.Id));
                }
            }
        }
        if (candidates.isEmpty()) {
            return;
        }
        List<DE_Assignment_Log__c> logs = [
            SELECT Id, Team__c, Record_Id__c, Assignee_Id__c, Assigned_At__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c IN :candidates AND Current__c = TRUE AND Action_At__c = NULL AND Team__c IN :teamById.keySet()
        ];
        if (logs.isEmpty()) {
            return;
        }
        Map<Id, DE_Model.TeamConfig> configs = new Map<Id, DE_Model.TeamConfig>();
        for (DE_Model.TeamConfig cfg : DE_ConfigRepository.load(teamById.keySet(), null, true)) {
            configs.put(cfg.team.Id, cfg);
        }
        Map<Id, SObject> byId = new Map<Id, SObject>(newRecords);
        Datetime now = System.now();
        Boolean hasField = DE_Schema.hasField(objectName, 'DE_Time_To_Action__c');
        List<DE_Assignment_Log__c> updates = new List<DE_Assignment_Log__c>();
        for (DE_Assignment_Log__c l : logs) {
            SObject r = byId.get(Id.valueOf(l.Record_Id__c));
            DE_Team__c t = teamById.get(l.Team__c);
            Object nv = r.get(t.Action_Field__c);
            Object ov = oldMap.get(r.Id).get(t.Action_Field__c);
            if (nv == null || nv == ov || !tracked(t).contains(String.valueOf(nv).toLowerCase())) {
                continue;
            }
            if (t.Track_Action_From_Any_User__c != true && UserInfo.getUserId() != l.Assignee_Id__c) {
                continue;
            }
            Decimal minutes = minutesBetween(configs.get(t.Id), l, now);
            l.Action_At__c = now;
            l.Time_To_Action_Mins__c = minutes;
            updates.add(l);
            if (hasField) {
                r.put('DE_Time_To_Action__c', minutes);
            }
        }
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
    }

    public static Decimal minutesBetween(DE_Model.TeamConfig cfg, DE_Assignment_Log__c l, Datetime now) {
        if (l.Assigned_At__c == null) {
            return null;
        }
        DE_Model.Member m = cfg == null ? null : cfg.member(DE_Ids.toId(l.Assignee_Id__c));
        DE_ShiftCalendar cal = cfg == null ? null : DE_AvailabilityService.timingCalendar(cfg, m, cfg.team.Action_Respect_Hours__c, l.Assigned_At__c);
        if (cal == null) {
            return Decimal.valueOf(now.getTime() - l.Assigned_At__c.getTime()).divide(60000, 1);
        }
        return cal.workingMinutesBetween(l.Assigned_At__c, now);
    }

    /** Task/Event after insert: sets the action field when an activity of a configured type is logged. */
    public static void autoAction(List<SObject> activities) {
        Set<String> recordIds = new Set<String>();
        for (SObject a : activities) {
            for (String f : new List<String>{ 'WhoId', 'WhatId' }) {
                Object v = a.get(f);
                if (v != null) {
                    recordIds.add(String.valueOf(v));
                }
            }
        }
        if (recordIds.isEmpty()) {
            return;
        }
        List<DE_Assignment_Log__c> logs = [
            SELECT Id, Team__c, Record_Id__c, Object_API_Name__c, Assignee_Id__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c IN :recordIds AND Current__c = TRUE AND Action_At__c = NULL AND Team__r.Action_Tracking_Enabled__c = TRUE
        ];
        if (logs.isEmpty()) {
            return;
        }
        Map<String, DE_Assignment_Log__c> logByRecord = new Map<String, DE_Assignment_Log__c>();
        Set<Id> teamIds = new Set<Id>();
        for (DE_Assignment_Log__c l : logs) {
            logByRecord.put(l.Record_Id__c, l);
            teamIds.add(l.Team__c);
        }
        Map<Id, DE_Team__c> teams = new Map<Id, DE_Team__c>(
            [
                SELECT Id, Action_Field__c, Tracked_Actions__c, Track_Action_From_Any_User__c, Auto_Action_Activity_Types__c
                FROM DE_Team__c
                WHERE Id IN :teamIds
            ]
        );
        Map<String, List<SObject>> updatesByObject = new Map<String, List<SObject>>();
        Set<Id> touched = new Set<Id>();
        for (SObject a : activities) {
            String type = String.valueOf(a.get('Type'));
            for (String f : new List<String>{ 'WhoId', 'WhatId' }) {
                Object v = a.get(f);
                DE_Assignment_Log__c l = v == null ? null : logByRecord.get(String.valueOf(v));
                if (l == null || touched.contains(Id.valueOf(l.Record_Id__c))) {
                    continue;
                }
                DE_Team__c t = teams.get(l.Team__c);
                Set<String> types = new Set<String>();
                for (String s : DE_Conditions.splitValues(t.Auto_Action_Activity_Types__c)) {
                    types.add(s.toLowerCase());
                }
                if (type == null || !types.contains(type.toLowerCase()) || String.isBlank(t.Action_Field__c)) {
                    continue;
                }
                Id creator = (Id) a.get('CreatedById');
                if (t.Track_Action_From_Any_User__c != true && String.valueOf(creator) != l.Assignee_Id__c) {
                    continue;
                }
                List<String> actions = DE_Conditions.splitValues(t.Tracked_Actions__c);
                if (actions.isEmpty() || !DE_Schema.hasField(l.Object_API_Name__c, t.Action_Field__c)) {
                    continue;
                }
                SObject rec = DE_Schema.sobjectType(l.Object_API_Name__c).newSObject(Id.valueOf(l.Record_Id__c));
                rec.put(t.Action_Field__c, actions[0]);
                if (!updatesByObject.containsKey(l.Object_API_Name__c)) {
                    updatesByObject.put(l.Object_API_Name__c, new List<SObject>());
                }
                updatesByObject.get(l.Object_API_Name__c).add(rec);
                touched.add(rec.Id);
            }
        }
        for (List<SObject> recs : updatesByObject.values()) {
            // Not bypassed: the before-update trigger records the action time.
            Database.update(recs, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
