/**
 * User availability toggle: online/offline with optional reason and timer, full audit history,
 * timer expiry, and start/end of day automation.
 */
public without sharing class DE_AgentService {
    public class ToggleException extends Exception {
    }

    /** Returns the availability rows for the users, creating missing ones (online by default). */
    public static Map<Id, DE_Agent__c> ensure(Set<Id> userIds) {
        Map<Id, DE_Agent__c> agents = DE_ConfigRepository.agentsByUser(userIds);
        List<DE_Agent__c> created = new List<DE_Agent__c>();
        Map<Id, User> users = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :userIds]);
        for (Id u : userIds) {
            if (!agents.containsKey(u) && users.containsKey(u)) {
                DE_Agent__c a = new DE_Agent__c(
                    Name = users.get(u).Name.left(80),
                    User__c = u,
                    Unique_User__c = String.valueOf(u),
                    Online__c = true,
                    Last_Status_Change__c = System.now()
                );
                created.add(a);
                agents.put(u, a);
            }
        }
        if (!created.isEmpty()) {
            Database.upsert(created, DE_Agent__c.Unique_User__c, false, AccessLevel.SYSTEM_MODE);
        }
        return agents;
    }

    /**
     * Sets users online or offline. Validation of reasons and timers applies to self-service toggles;
     * managers and automated sources bypass the "timer toggles only" rule.
     */
    public static void setOnline(Set<Id> userIds, Boolean online, String reason, Integer timerMinutes, String source) {
        if (!online && source == 'User') {
            if (DE_Settings.requireToggleReason() && String.isBlank(reason)) {
                throw new ToggleException('Choose a reason for going offline.');
            }
            if (String.isNotBlank(reason) && DE_Settings.requireToggleReason() && !containsIgnoreCase(DE_Settings.toggleReasons(), reason)) {
                throw new ToggleException('"' + reason + '" is not one of the allowed reasons.');
            }
            if (DE_Settings.timerTogglesOnly() && timerMinutes == null) {
                throw new ToggleException('Choose how long you will be offline.');
            }
        }
        if (timerMinutes != null && timerMinutes <= 0) {
            throw new ToggleException('The timer must be at least one minute.');
        }
        Map<Id, DE_Agent__c> agents = ensure(userIds);
        Datetime now = System.now();
        List<DE_Agent__c> updates = new List<DE_Agent__c>();
        List<DE_Availability_Event__c> history = new List<DE_Availability_Event__c>();
        for (Id u : userIds) {
            DE_Agent__c a = agents.get(u);
            if (a == null) {
                continue;
            }
            a.Online__c = online;
            a.Toggle_Reason__c = online ? null : (reason == null ? null : reason.left(80));
            a.Toggle_Until__c = online || timerMinutes == null ? null : now.addMinutes(timerMinutes);
            a.Last_Status_Change__c = now;
            updates.add(a);
            history.add(
                new DE_Availability_Event__c(
                    User__c = u,
                    Online__c = online,
                    Reason__c = reason == null ? null : reason.left(80),
                    Changed_By__c = UserInfo.getUserId(),
                    Changed_At__c = now,
                    Source__c = source
                )
            );
        }
        Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        Database.insert(history, false, AccessLevel.SYSTEM_MODE);
    }

    private static Boolean containsIgnoreCase(List<String> values, String value) {
        for (String v : values) {
            if (v.equalsIgnoreCase(value.trim())) {
                return true;
            }
        }
        return false;
    }

    /** Brings users back online when their timer expires. Returns how many were changed. */
    public static Integer expireTimers(Datetime now) {
        Set<Id> due = new Set<Id>();
        for (DE_Agent__c a : [SELECT User__c FROM DE_Agent__c WHERE Online__c = FALSE AND Toggle_Until__c != NULL AND Toggle_Until__c <= :now LIMIT 500]) {
            due.add(a.User__c);
        }
        if (!due.isEmpty()) {
            setOnline(due, true, 'Timer ended', null, 'Timer');
        }
        return due.size();
    }

    /**
     * Start of day: at the first run after local midnight (user timezone) apply Always On / Always Off.
     * End of day: after the end of the user's last shift block of the day apply Always On / Always Off.
     */
    public static Integer applyDayBoundaries(Datetime now) {
        String startRule = DE_Settings.toggleAtStartOfDay();
        String endRule = DE_Settings.toggleAtEndOfDay();
        if (startRule == 'No Change' && endRule == 'No Change') {
            return 0;
        }
        List<DE_Agent__c> agents = [
            SELECT Id, User__c, Online__c, Last_Status_Change__c, User__r.TimeZoneSidKey
            FROM DE_Agent__c
            WHERE User__r.IsActive = TRUE
            LIMIT 2000
        ];
        Set<Id> userIds = new Set<Id>();
        for (DE_Agent__c a : agents) {
            userIds.add(a.User__c);
        }
        Map<Id, DE_ShiftCalendar> shiftByUser = shiftCalendars(userIds);
        Set<Id> toOn = new Set<Id>();
        Set<Id> toOff = new Set<Id>();
        for (DE_Agent__c a : agents) {
            DE_ShiftCalendar tz = DE_ShiftCalendar.always(a.User__r.TimeZoneSidKey);
            Datetime midnight = tz.localMidnight(now);
            Datetime last = a.Last_Status_Change__c == null ? Datetime.newInstance(0) : a.Last_Status_Change__c;
            if (startRule != 'No Change' && last < midnight) {
                Boolean want = startRule == 'Always On';
                if (a.Online__c != want) {
                    (want ? toOn : toOff).add(a.User__c);
                    continue;
                }
            }
            DE_ShiftCalendar shift = shiftByUser.get(a.User__c);
            if (endRule != 'No Change' && shift != null) {
                Datetime shiftEnd = shift.lastBlockEnd(now);
                if (shiftEnd != null && now >= shiftEnd && last < shiftEnd) {
                    Boolean want = endRule == 'Always On';
                    if (a.Online__c != want) {
                        (want ? toOn : toOff).add(a.User__c);
                    }
                }
            }
        }
        if (!toOn.isEmpty()) {
            setOnline(toOn, true, 'Start/end of day', null, 'Start of Day');
        }
        if (!toOff.isEmpty()) {
            setOnline(toOff, false, 'Start/end of day', null, 'End of Day');
        }
        return toOn.size() + toOff.size();
    }

    /** The first shift (member hours, else team hours) for each user across their memberships. */
    private static Map<Id, DE_ShiftCalendar> shiftCalendars(Set<Id> userIds) {
        Map<Id, DE_ShiftCalendar> out = new Map<Id, DE_ShiftCalendar>();
        for (DE_Team_Member__c m : [
            SELECT User__c, Member_Hours__r.Timezone__c, Member_Hours__r.Schedule__c, Team__r.Team_Hours__r.Timezone__c, Team__r.Team_Hours__r.Schedule__c
            FROM DE_Team_Member__c
            WHERE User__c IN :userIds AND Active__c = TRUE
            ORDER BY CreatedDate
        ]) {
            if (out.containsKey(m.User__c)) {
                continue;
            }
            if (m.Member_Hours__r != null) {
                out.put(m.User__c, new DE_ShiftCalendar(m.Member_Hours__r.Timezone__c, m.Member_Hours__r.Schedule__c));
            } else if (m.Team__r.Team_Hours__r != null) {
                out.put(m.User__c, new DE_ShiftCalendar(m.Team__r.Team_Hours__r.Timezone__c, m.Team__r.Team_Hours__r.Schedule__c));
            }
        }
        return out;
    }
}
