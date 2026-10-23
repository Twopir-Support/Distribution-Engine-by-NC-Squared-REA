/**
 * Distribution Availability and Distribution Tags tabs: out of office, regional holidays, regions,
 * shifts, the availability calendar, the team roster (manager toggle override) and user tags.
 */
public with sharing class DE_AvailabilityController {
    public class RosterRow {
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Boolean online;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Datetime toggledAt;
        @AuraEnabled
        public Datetime toggledUntil;
        @AuraEnabled
        public Integer minutesOffline;
        @AuraEnabled
        public String availability;
        @AuraEnabled
        public String teams;
    }

    public class CalendarDay {
        @AuraEnabled
        public Date day;
        @AuraEnabled
        public Integer working = 0;
        @AuraEnabled
        public Integer outOfOffice = 0;
        @AuraEnabled
        public Boolean holiday = false;
        @AuraEnabled
        public String holidayName;
    }

    public class TagRow {
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String tags;
    }

    // ------------------------------------------------------------------ out of office

    @AuraEnabled
    public static List<DE_Out_Of_Office__c> getOutOfOffice(Id userId, Date fromDate, Date toDate) {
        DE_Permissions.require(DE_Permissions.isUser(), 'view out of office');
        Datetime fromAt = fromDate == null ? System.now().addDays(-7) : Datetime.newInstance(fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime toAt = toDate == null ? System.now().addDays(90) : Datetime.newInstance(toDate.addDays(1), Time.newInstance(0, 0, 0, 0));
        Id only = DE_Permissions.isTeamManager() ? userId : UserInfo.getUserId();
        String soql = 'SELECT Id, Name, User__c, User__r.Name, Queue_Id__c, Start__c, End__c, All_Day__c, Reason__c, Source__c FROM DE_Out_Of_Office__c WHERE End__c >= :fromAt AND Start__c <= :toAt';
        if (only != null) {
            soql += ' AND User__c = :only';
        }
        soql += ' ORDER BY Start__c LIMIT 500';
        return Database.queryWithBinds(soql, new Map<String, Object>{ 'fromAt' => fromAt, 'toAt' => toAt, 'only' => only }, AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static Id saveOutOfOffice(DE_Out_Of_Office__c ooo) {
        Boolean self = ooo.User__c == UserInfo.getUserId() && ooo.Queue_Id__c == null;
        DE_Permissions.require(self ? DE_Permissions.isUser() : DE_Permissions.isTeamManager(), 'enter out of office for other users');
        List<String> errors = new List<String>();
        if (ooo.User__c == null && !DE_Ids.isQueue(ooo.Queue_Id__c)) {
            errors.add('Choose a user or queue.');
        }
        if (ooo.Start__c == null || ooo.End__c == null || ooo.End__c <= ooo.Start__c) {
            errors.add('End must be after Start.');
        }
        if (ooo.Reason__c != null && ooo.Reason__c.length() > 80) {
            errors.add('Reason is limited to 80 characters.');
        }
        DE_Ui.throwIfErrors(errors);
        if (ooo.All_Day__c == true) {
            DE_ShiftCalendar cal = DE_ShiftCalendar.always(UserInfo.getTimeZone().getID());
            ooo.Start__c = Datetime.newInstance(cal.utcMs(cal.localDate(ooo.Start__c), 0));
            ooo.End__c = Datetime.newInstance(cal.utcMs(cal.localDate(ooo.End__c).addDays(1), 0));
        }
        try {
            if (ooo.Source__c == null) {
                ooo.Source__c = 'Manual';
            }
            Database.upsert(ooo, true, AccessLevel.USER_MODE);
            return ooo.Id;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteOutOfOffice(Id oooId) {
        DE_Out_Of_Office__c o = [SELECT Id, User__c FROM DE_Out_Of_Office__c WHERE Id = :oooId WITH USER_MODE];
        DE_Permissions.require(o.User__c == UserInfo.getUserId() || DE_Permissions.isTeamManager(), 'delete out of office for other users');
        try {
            Database.delete(o, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ holidays and regions

    @AuraEnabled
    public static List<DE_Holiday__c> getHolidays() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view holidays');
        return [SELECT Id, Name, Region__c, All_Day__c, Start__c, End__c, Timezone__c FROM DE_Holiday__c WITH USER_MODE ORDER BY Start__c DESC LIMIT 1000];
    }

    @AuraEnabled
    public static Id saveHoliday(DE_Holiday__c holiday) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'edit holidays');
        List<String> errors = new List<String>();
        if (String.isBlank(holiday.Name) || String.isBlank(holiday.Region__c)) {
            errors.add('Enter a holiday name and region.');
        }
        if (holiday.Start__c == null || holiday.End__c == null || holiday.End__c < holiday.Start__c) {
            errors.add('Ends must be on or after Starts.');
        }
        DE_Ui.throwIfErrors(errors);
        try {
            Database.upsert(holiday, true, AccessLevel.USER_MODE);
            return holiday.Id;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteHoliday(Id holidayId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'delete holidays');
        try {
            Database.delete(new DE_Holiday__c(Id = holidayId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    /** Region -> teams using it. */
    @AuraEnabled
    public static Map<String, List<String>> getRegions() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view regions');
        Map<String, List<String>> out = new Map<String, List<String>>();
        for (DE_Holiday__c h : [SELECT Region__c FROM DE_Holiday__c WITH USER_MODE]) {
            out.put(h.Region__c, new List<String>());
        }
        for (DE_Team__c t : [SELECT Name, Holiday_Region__c FROM DE_Team__c WHERE Holiday_Region__c != NULL WITH USER_MODE]) {
            if (!out.containsKey(t.Holiday_Region__c)) {
                out.put(t.Holiday_Region__c, new List<String>());
            }
            out.get(t.Holiday_Region__c).add(t.Name);
        }
        return out;
    }

    // ------------------------------------------------------------------ shifts

    @AuraEnabled
    public static List<DE_Shift__c> getShifts() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view shifts');
        return [SELECT Id, Name, Timezone__c, Schedule__c, Description__c FROM DE_Shift__c WITH USER_MODE ORDER BY Name];
    }

    @AuraEnabled
    public static Id saveShift(DE_Shift__c shift) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'edit shifts');
        DE_Ui.throwIfErrors(DE_ConfigValidator.shift(shift));
        try {
            Database.upsert(shift, true, AccessLevel.USER_MODE);
            return shift.Id;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteShift(Id shiftId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'delete shifts');
        Integer used =
            [SELECT COUNT() FROM DE_Team__c WHERE Team_Hours__c = :shiftId] + [SELECT COUNT() FROM DE_Team_Member__c WHERE Member_Hours__c = :shiftId];
        if (used > 0) {
            throw DE_Ui.error('This shift is used by ' + used + ' teams or members. Assign other hours first.');
        }
        try {
            Database.delete(new DE_Shift__c(Id = shiftId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ roster and toggles

    @AuraEnabled
    public static List<RosterRow> getRoster(Id teamId) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view the team roster');
        List<DE_Model.TeamConfig> teams = teamId == null
            ? DE_ConfigRepository.load(null, null, false)
            : DE_ConfigRepository.load(new Set<Id>{ teamId }, null, true);
        DE_AvailabilityService availability = new DE_AvailabilityService(teams, System.now());
        Map<Id, RosterRow> rows = new Map<Id, RosterRow>();
        for (DE_Model.TeamConfig cfg : teams) {
            String holiday = availability.holidayFor(cfg);
            for (DE_Model.Member m : cfg.members) {
                if (m.isQueue || !m.isActive()) {
                    continue;
                }
                RosterRow r = rows.get(m.memberId);
                if (r == null) {
                    r = new RosterRow();
                    r.userId = m.memberId;
                    r.name = m.user.Name;
                    r.online = m.isOnline();
                    r.reason = m.agent == null ? null : m.agent.Toggle_Reason__c;
                    r.toggledAt = m.agent == null ? null : m.agent.Last_Status_Change__c;
                    r.toggledUntil = m.agent == null ? null : m.agent.Toggle_Until__c;
                    r.minutesOffline = !r.online && r.toggledAt != null ? (Integer) ((System.now().getTime() - r.toggledAt.getTime()) / 60000) : null;
                    String reason = holiday != null ? 'Holiday: ' + holiday : availability.unavailableReason(m, false, false, false);
                    r.availability = reason == null ? 'Available' : reason;
                    r.teams = cfg.team.Name;
                    rows.put(m.memberId, r);
                } else {
                    r.teams += ', ' + cfg.team.Name;
                }
            }
        }
        List<RosterRow> out = rows.values();
        return out;
    }

    @AuraEnabled
    public static void setUsersOnline(List<Id> userIds, Boolean online, String reason) {
        Set<Id> ids = new Set<Id>(userIds);
        Boolean selfOnly = ids.size() == 1 && ids.contains(UserInfo.getUserId());
        DE_Permissions.require(selfOnly ? DE_Permissions.isUser() : DE_Permissions.isTeamManager(), 'change other users\' availability');
        try {
            DE_AgentService.setOnline(ids, online, reason, null, selfOnly ? 'User' : 'Manager');
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static List<DE_Availability_Event__c> getAvailabilityHistory(Id userId) {
        DE_Permissions.require(userId == UserInfo.getUserId() || DE_Permissions.isTeamManager(), 'view availability history');
        return [
            SELECT Id, User__r.Name, Online__c, Reason__c, Changed_By__r.Name, Changed_At__c, Source__c
            FROM DE_Availability_Event__c
            WHERE User__c = :userId
            WITH USER_MODE
            ORDER BY Changed_At__c DESC
            LIMIT 200
        ];
    }

    // ------------------------------------------------------------------ calendar

    /** Month view: per day, members working (by shift), out of office and holiday. */
    @AuraEnabled
    public static List<CalendarDay> getCalendar(Id teamId, Integer year, Integer month) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view the availability calendar');
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(teamId, true);
        if (cfg == null) {
            throw DE_Ui.error('Choose a team.');
        }
        Date first = Date.newInstance(year, month, 1);
        Integer days = Date.daysInMonth(year, month);
        Datetime fromAt = Datetime.newInstance(first, Time.newInstance(0, 0, 0, 0)).addDays(-1);
        Datetime toAt = Datetime.newInstance(first.addDays(days), Time.newInstance(0, 0, 0, 0)).addDays(1);
        Set<Id> userIds = new Set<Id>();
        for (DE_Model.Member m : cfg.members) {
            if (!m.isQueue && m.isActive()) {
                userIds.add(m.memberId);
            }
        }
        List<DE_Out_Of_Office__c> ooo = [
            SELECT User__c, Start__c, End__c
            FROM DE_Out_Of_Office__c
            WHERE User__c IN :userIds AND Start__c <= :toAt AND End__c >= :fromAt
            WITH USER_MODE
        ];
        List<DE_Holiday__c> holidays = String.isBlank(cfg.team.Holiday_Region__c)
            ? new List<DE_Holiday__c>()
            : [
                  SELECT Name, All_Day__c, Start__c, End__c, Timezone__c, Region__c
                  FROM DE_Holiday__c
                  WHERE Region__c = :cfg.team.Holiday_Region__c AND Start__c <= :toAt AND End__c >= :fromAt
                  WITH USER_MODE
              ];
        DE_ShiftCalendar tzCal = DE_ShiftCalendar.always(cfg.timezoneSid());
        List<CalendarDay> out = new List<CalendarDay>();
        for (Integer i = 0; i < days; i++) {
            Date d = first.addDays(i);
            CalendarDay cd = new CalendarDay();
            cd.day = d;
            Datetime dayStart = Datetime.newInstance(tzCal.utcMs(d, 0));
            Datetime dayEnd = Datetime.newInstance(tzCal.utcMs(d.addDays(1), 0));
            for (DE_Holiday__c h : holidays) {
                List<Datetime> w = DE_AvailabilityService.holidayWindow(h, cfg.timezoneSid());
                if (w[0] < dayEnd && w[1] > dayStart) {
                    cd.holiday = true;
                    cd.holidayName = h.Name;
                }
            }
            for (DE_Model.Member m : cfg.members) {
                if (m.isQueue || !m.isActive()) {
                    continue;
                }
                Boolean away = false;
                for (DE_Out_Of_Office__c o : ooo) {
                    if (o.User__c == m.memberId && o.Start__c < dayEnd && o.End__c > dayStart) {
                        away = true;
                        break;
                    }
                }
                if (away) {
                    cd.outOfOffice++;
                } else if (m.calendar == null || !m.calendar.intervals(dayStart.getTime(), dayEnd.getTime()).isEmpty()) {
                    cd.working++;
                }
            }
            out.add(cd);
        }
        return out;
    }

    // ------------------------------------------------------------------ tags

    @AuraEnabled
    public static List<TagRow> getTagAssignments() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view tags');
        Set<Id> userIds = new Set<Id>();
        for (DE_Team_Member__c m : [SELECT User__c FROM DE_Team_Member__c WHERE User__c != NULL WITH USER_MODE]) {
            userIds.add(m.User__c);
        }
        Map<Id, DE_Agent__c> agents = DE_AgentService.ensure(userIds);
        Map<Id, User> users = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :userIds]);
        List<TagRow> out = new List<TagRow>();
        for (Id u : userIds) {
            TagRow r = new TagRow();
            r.userId = u;
            r.name = users.containsKey(u) ? users.get(u).Name : String.valueOf(u);
            r.tags = agents.containsKey(u) ? agents.get(u).Tags__c : null;
            out.add(r);
        }
        return out;
    }

    /** Distinct tag collections and tags in use. */
    @AuraEnabled
    public static Map<String, List<String>> getTagCollections() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view tags');
        Map<String, Set<String>> sets = new Map<String, Set<String>>();
        for (DE_Agent__c a : [SELECT Tags__c FROM DE_Agent__c WHERE Tags__c != NULL WITH USER_MODE LIMIT 5000]) {
            for (String t : a.Tags__c.split(';')) {
                if (!t.contains(':')) {
                    continue;
                }
                String c = t.substringBefore(':').trim();
                if (!sets.containsKey(c)) {
                    sets.put(c, new Set<String>());
                }
                sets.get(c).add(t.substringAfter(':').trim());
            }
        }
        Map<String, List<String>> out = new Map<String, List<String>>();
        for (String c : sets.keySet()) {
            List<String> vals = new List<String>(sets.get(c));
            vals.sort();
            out.put(c, vals);
        }
        return out;
    }

    @AuraEnabled
    public static void saveTags(Id userId, String tags) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'assign tags');
        List<String> clean = new List<String>();
        Set<String> seen = new Set<String>();
        for (String t : (tags == null ? '' : tags).split('[;\\n]')) {
            if (String.isBlank(t)) {
                continue;
            }
            if (!t.contains(':') || t.substringBefore(':').trim().length() > 30 || t.substringAfter(':').trim().length() > 50) {
                throw DE_Ui.error('Tag "' + t.trim() + '" must be Collection:Tag (collection up to 30 characters, tag up to 50).');
            }
            String norm = t.substringBefore(':').trim() + ':' + t.substringAfter(':').trim();
            if (!seen.contains(norm.toLowerCase())) {
                seen.add(norm.toLowerCase());
                clean.add(norm);
            }
        }
        DE_Agent__c a = DE_AgentService.ensure(new Set<Id>{ userId }).get(userId);
        a.Tags__c = clean.isEmpty() ? null : String.join(clean, ';');
        try {
            Database.update(a, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void cloneTags(Id fromUserId, List<Id> toUserIds) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'assign tags');
        Set<Id> all = new Set<Id>(toUserIds);
        all.add(fromUserId);
        Map<Id, DE_Agent__c> agents = DE_AgentService.ensure(all);
        List<DE_Agent__c> updates = new List<DE_Agent__c>();
        for (Id u : toUserIds) {
            DE_Agent__c a = agents.get(u);
            if (a != null) {
                a.Tags__c = agents.get(fromUserId).Tags__c;
                updates.add(a);
            }
        }
        try {
            Database.update(updates, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }
}
