/**
 * Shift planner: dated shift changes per team member (DE_Shift_Plan_Block__c). From a block's start date the member
 * works the block's shift until their next block. Changes can be planned up to 12 weeks ahead; the grid also shows
 * the previous 4 weeks. Used when DE_Team__c.Use_Shift_Planner__c is true.
 */
public without sharing class DE_ShiftPlannerService {
    public static final Integer WEEKS_AHEAD = 12;
    public static final Integer WEEKS_BACK = 4;

    public class PlannerException extends Exception {
    }

    public class Change {
        @AuraEnabled
        public Id memberId { get; set; }
        @AuraEnabled
        public Date weekStart { get; set; }
        @AuraEnabled
        public Id shiftId { get; set; }
    }

    public class Cell {
        @AuraEnabled
        public String week;
        @AuraEnabled
        public Id shiftId;
        @AuraEnabled
        public String shiftName;
        @AuraEnabled
        public Boolean isChange = false;
        @AuraEnabled
        public Boolean editable = false;
    }

    public class Row {
        @AuraEnabled
        public Id memberId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<Cell> cells = new List<Cell>();
    }

    public class Grid {
        @AuraEnabled
        public Boolean enabled;
        @AuraEnabled
        public String currentWeek;
        @AuraEnabled
        public List<String> weeks = new List<String>();
        @AuraEnabled
        public List<Row> rows = new List<Row>();
    }

    /** First day of the week containing d (Monday, or Sunday when the org week starts on Sunday). */
    public static Date weekStart(Date d) {
        Integer idx = DE_ShiftCalendar.dayIndex(d); // 0 = Monday
        if (DE_Settings.weekStartDay() == 7) {
            idx = Math.mod(idx + 1, 7);
        }
        return d.addDays(-idx);
    }

    /** Shift of each member on a day from their latest block starting on or before it. Members without a block are absent. */
    public static Map<Id, Id> shiftsOn(Set<Id> memberIds, Date day) {
        Map<Id, Id> out = new Map<Id, Id>();
        if (memberIds == null || memberIds.isEmpty()) {
            return out;
        }
        for (DE_Shift_Plan_Block__c b : [
            SELECT Team_Member__c, Shift__c
            FROM DE_Shift_Plan_Block__c
            WHERE Team_Member__c IN :memberIds AND Start_Date__c <= :day
            ORDER BY Start_Date__c DESC
        ]) {
            if (!out.containsKey(b.Team_Member__c)) {
                out.put(b.Team_Member__c, b.Shift__c);
            }
        }
        return out;
    }

    /** Sets End_Date__c of every block of these members to the day before the member's next block (blank for the last). */
    public static void recalcEndDates(Set<Id> memberIds) {
        if (memberIds == null || memberIds.isEmpty()) {
            return;
        }
        List<DE_Shift_Plan_Block__c> updates = new List<DE_Shift_Plan_Block__c>();
        DE_Shift_Plan_Block__c previous;
        for (DE_Shift_Plan_Block__c b : [
            SELECT Id, Team_Member__c, Start_Date__c, End_Date__c
            FROM DE_Shift_Plan_Block__c
            WHERE Team_Member__c IN :memberIds
            ORDER BY Team_Member__c, Start_Date__c
        ]) {
            if (previous != null && previous.Team_Member__c == b.Team_Member__c) {
                setEnd(previous, b.Start_Date__c.addDays(-1), updates);
            } else if (previous != null) {
                setEnd(previous, null, updates);
            }
            previous = b;
        }
        if (previous != null) {
            setEnd(previous, null, updates);
        }
        Database.update(updates, true, AccessLevel.SYSTEM_MODE);
    }

    private static void setEnd(DE_Shift_Plan_Block__c b, Date endDate, List<DE_Shift_Plan_Block__c> updates) {
        if (b.End_Date__c != endDate) {
            updates.add(new DE_Shift_Plan_Block__c(Id = b.Id, End_Date__c = endDate));
        }
    }

    /** The team's planner record, created on first use. */
    public static DE_Shift_Plan__c planFor(Id teamId) {
        List<DE_Shift_Plan__c> plans = [SELECT Id FROM DE_Shift_Plan__c WHERE Team__c = :teamId ORDER BY CreatedDate LIMIT 1];
        if (!plans.isEmpty()) {
            return plans[0];
        }
        DE_Team__c t = [SELECT Name FROM DE_Team__c WHERE Id = :teamId];
        DE_Shift_Plan__c p = new DE_Shift_Plan__c(Team__c = teamId, Name = (t.Name + ' Shift Planner').left(80));
        Database.insert(p, true, AccessLevel.SYSTEM_MODE);
        return p;
    }

    /** Applies planned changes. A change with no shift removes the change at that week. */
    public static void applyChanges(Id teamId, List<Change> changes) {
        if (changes == null || changes.isEmpty()) {
            return;
        }
        Date current = weekStart(Date.today());
        Date last = current.addDays(7 * WEEKS_AHEAD);
        Map<Id, DE_Team_Member__c> members = new Map<Id, DE_Team_Member__c>([SELECT Id FROM DE_Team_Member__c WHERE Team__c = :teamId]);
        Set<Id> shiftIds = new Set<Id>();
        for (Change c : changes) {
            if (c.memberId == null || !members.containsKey(c.memberId)) {
                throw new PlannerException('A shift change refers to someone who is not a member of this team.');
            }
            if (c.weekStart == null) {
                throw new PlannerException('Each shift change needs a week.');
            }
            Date w = weekStart(c.weekStart);
            if (w < current || w > last) {
                throw new PlannerException('Shift changes can be planned from this week up to ' + WEEKS_AHEAD + ' weeks ahead.');
            }
            if (c.shiftId != null) {
                shiftIds.add(c.shiftId);
            }
        }
        Set<Id> knownShifts = new Map<Id, DE_Shift__c>([SELECT Id FROM DE_Shift__c WHERE Id IN :shiftIds]).keySet();
        if (!knownShifts.containsAll(shiftIds)) {
            throw new PlannerException('A selected shift no longer exists.');
        }
        DE_Shift_Plan__c plan = planFor(teamId);
        Map<String, DE_Shift_Plan_Block__c> existing = new Map<String, DE_Shift_Plan_Block__c>();
        for (DE_Shift_Plan_Block__c b : [
            SELECT Id, Team_Member__c, Start_Date__c, Shift__c
            FROM DE_Shift_Plan_Block__c
            WHERE Team_Member__c IN :members.keySet() AND Start_Date__c >= :current
        ]) {
            existing.put(b.Team_Member__c + '|' + b.Start_Date__c, b);
        }
        Map<String, DE_Shift_Plan_Block__c> upserts = new Map<String, DE_Shift_Plan_Block__c>();
        Map<Id, DE_Shift_Plan_Block__c> deletes = new Map<Id, DE_Shift_Plan_Block__c>();
        Set<Id> touched = new Set<Id>();
        for (Change c : changes) {
            Date w = weekStart(c.weekStart);
            String key = c.memberId + '|' + w;
            DE_Shift_Plan_Block__c b = existing.get(key);
            touched.add(c.memberId);
            if (c.shiftId == null) {
                if (b != null) {
                    deletes.put(b.Id, b);
                }
                upserts.remove(key);
                continue;
            }
            DE_Shift_Plan_Block__c row = b == null
                ? new DE_Shift_Plan_Block__c(Shift_Plan__c = plan.Id, Team_Member__c = c.memberId, Start_Date__c = w)
                : new DE_Shift_Plan_Block__c(Id = b.Id);
            row.Shift__c = c.shiftId;
            upserts.put(key, row);
            if (b != null) {
                deletes.remove(b.Id);
            }
        }
        Database.delete(deletes.values(), true, AccessLevel.SYSTEM_MODE);
        Database.upsert(upserts.values(), true, AccessLevel.SYSTEM_MODE);
        recalcEndDates(touched);
    }

    /** Turns the planner on. Each member without a plan starts this week on their current member hours (or the team hours). */
    public static void enable(Id teamId) {
        DE_Team__c team = [SELECT Id, Team_Hours__c FROM DE_Team__c WHERE Id = :teamId];
        DE_Shift_Plan__c plan = planFor(teamId);
        Map<Id, DE_Team_Member__c> members = new Map<Id, DE_Team_Member__c>([SELECT Id, Member_Hours__c FROM DE_Team_Member__c WHERE Team__c = :teamId]);
        Set<Id> planned = new Set<Id>();
        for (DE_Shift_Plan_Block__c b : [SELECT Team_Member__c FROM DE_Shift_Plan_Block__c WHERE Team_Member__c IN :members.keySet()]) {
            planned.add(b.Team_Member__c);
        }
        Date current = weekStart(Date.today());
        List<DE_Shift_Plan_Block__c> seeds = new List<DE_Shift_Plan_Block__c>();
        for (DE_Team_Member__c m : members.values()) {
            Id shift = m.Member_Hours__c != null ? m.Member_Hours__c : team.Team_Hours__c;
            if (!planned.contains(m.Id) && shift != null) {
                seeds.add(new DE_Shift_Plan_Block__c(Shift_Plan__c = plan.Id, Team_Member__c = m.Id, Start_Date__c = current, Shift__c = shift));
            }
        }
        Database.insert(seeds, true, AccessLevel.SYSTEM_MODE);
        Database.update(new DE_Team__c(Id = teamId, Use_Shift_Planner__c = true), true, AccessLevel.SYSTEM_MODE);
    }

    /** Turns the planner off: members keep their current shift as member hours and future changes are removed. */
    public static void disable(Id teamId) {
        Map<Id, DE_Team_Member__c> members = new Map<Id, DE_Team_Member__c>([SELECT Id FROM DE_Team_Member__c WHERE Team__c = :teamId]);
        Date today = Date.today();
        Map<Id, Id> current = shiftsOn(members.keySet(), today);
        List<DE_Team_Member__c> updates = new List<DE_Team_Member__c>();
        for (Id m : current.keySet()) {
            updates.add(new DE_Team_Member__c(Id = m, Member_Hours__c = current.get(m)));
        }
        Database.update(updates, true, AccessLevel.SYSTEM_MODE);
        DE_Ui.deleteAll(
            [SELECT Id FROM DE_Shift_Plan_Block__c WHERE Team_Member__c IN :members.keySet() AND Start_Date__c > :today],
            true,
            AccessLevel.SYSTEM_MODE
        );
        recalcEndDates(members.keySet());
        Database.update(new DE_Team__c(Id = teamId, Use_Shift_Planner__c = false), true, AccessLevel.SYSTEM_MODE);
    }

    /** Members x weeks (4 back to 12 ahead) with the shift in effect at the start of each week. */
    public static Grid grid(Id teamId) {
        DE_Team__c team = [SELECT Id, Use_Shift_Planner__c FROM DE_Team__c WHERE Id = :teamId];
        Grid g = new Grid();
        g.enabled = team.Use_Shift_Planner__c;
        Date current = weekStart(Date.today());
        g.currentWeek = String.valueOf(current);
        List<Date> weeks = new List<Date>();
        for (Integer i = -WEEKS_BACK; i <= WEEKS_AHEAD; i++) {
            weeks.add(current.addDays(7 * i));
            g.weeks.add(String.valueOf(current.addDays(7 * i)));
        }
        List<DE_Team_Member__c> members = [
            SELECT Id, User__c, User__r.Name, Queue_Id__c, Active__c
            FROM DE_Team_Member__c
            WHERE Team__c = :teamId
            ORDER BY User__r.Name, Queue_Id__c
        ];
        Map<Id, List<DE_Shift_Plan_Block__c>> blocks = new Map<Id, List<DE_Shift_Plan_Block__c>>();
        Date lastWeek = weeks[weeks.size() - 1];
        for (DE_Shift_Plan_Block__c b : [
            SELECT Team_Member__c, Start_Date__c, Shift__c, Shift__r.Name
            FROM DE_Shift_Plan_Block__c
            WHERE Team_Member__c IN :members AND Start_Date__c <= :lastWeek.addDays(6)
            ORDER BY Start_Date__c
        ]) {
            if (!blocks.containsKey(b.Team_Member__c)) {
                blocks.put(b.Team_Member__c, new List<DE_Shift_Plan_Block__c>());
            }
            blocks.get(b.Team_Member__c).add(b);
        }
        Set<Id> queueIds = new Set<Id>();
        for (DE_Team_Member__c m : members) {
            Id q = DE_Ids.toId(m.Queue_Id__c);
            if (q != null) {
                queueIds.add(q);
            }
        }
        Map<Id, String> queueNames = DE_Ui.ownerNames(queueIds);
        for (DE_Team_Member__c m : members) {
            Row r = new Row();
            r.memberId = m.Id;
            r.name = m.User__c != null ? m.User__r.Name : queueNames.get(DE_Ids.toId(m.Queue_Id__c));
            List<DE_Shift_Plan_Block__c> mine = blocks.containsKey(m.Id) ? blocks.get(m.Id) : new List<DE_Shift_Plan_Block__c>();
            for (Date w : weeks) {
                Cell c = new Cell();
                c.week = String.valueOf(w);
                c.editable = w >= current;
                for (DE_Shift_Plan_Block__c b : mine) {
                    if (b.Start_Date__c <= w.addDays(6) && b.Start_Date__c >= w) {
                        c.isChange = true;
                    }
                    if (b.Start_Date__c <= w || (b.Start_Date__c <= w.addDays(6) && b.Start_Date__c >= w)) {
                        c.shiftId = b.Shift__c;
                        c.shiftName = b.Shift__r.Name;
                    }
                }
                r.cells.add(c);
            }
            g.rows.add(r);
        }
        return g;
    }
}
