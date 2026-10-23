/**
 * Decides whether teams and members are available at a point in time.
 * Order of evaluation (as documented by the reference): Holidays, Out of Office,
 * Distribution Hours, availability toggle.
 */
public without sharing class DE_AvailabilityService {
    public Datetime at { get; private set; }
    private Map<String, List<DE_Holiday__c>> holidaysByRegion = new Map<String, List<DE_Holiday__c>>();
    private Map<Id, List<DE_Out_Of_Office__c>> oooByMember = new Map<Id, List<DE_Out_Of_Office__c>>();

    public DE_AvailabilityService(List<DE_Model.TeamConfig> teams, Datetime at) {
        this.at = at == null ? System.now() : at;
        Set<String> regions = new Set<String>();
        Set<Id> userIds = new Set<Id>();
        Set<String> queueIds = new Set<String>();
        for (DE_Model.TeamConfig t : teams) {
            if (String.isNotBlank(t.team.Holiday_Region__c)) {
                regions.add(t.team.Holiday_Region__c);
            }
            for (DE_Model.Member m : t.members) {
                if (m.isQueue) {
                    queueIds.add(String.valueOf(m.memberId));
                } else {
                    userIds.add(m.memberId);
                }
            }
        }
        loadHolidays(regions, this.at.addDays(-2), this.at.addDays(2));
        Datetime windowStart = this.at.addDays(-1);
        Datetime windowEnd = this.at.addDays(1);
        for (DE_Out_Of_Office__c o : [
            SELECT Id, User__c, Queue_Id__c, Start__c, End__c, All_Day__c, Reason__c
            FROM DE_Out_Of_Office__c
            WHERE (User__c IN :userIds OR Queue_Id__c IN :queueIds) AND Start__c <= :windowEnd AND End__c >= :windowStart
        ]) {
            Id key = o.User__c != null ? o.User__c : DE_Ids.toId(o.Queue_Id__c);
            if (key == null) {
                continue;
            }
            if (!oooByMember.containsKey(key)) {
                oooByMember.put(key, new List<DE_Out_Of_Office__c>());
            }
            oooByMember.get(key).add(o);
        }
    }

    private void loadHolidays(Set<String> regions, Datetime fromAt, Datetime toAt) {
        if (regions.isEmpty()) {
            return;
        }
        for (DE_Holiday__c h : [
            SELECT Id, Name, Region__c, All_Day__c, Start__c, End__c, Timezone__c
            FROM DE_Holiday__c
            WHERE Region__c IN :regions AND Start__c <= :toAt AND End__c >= :fromAt
        ]) {
            String key = h.Region__c.toLowerCase();
            if (!holidaysByRegion.containsKey(key)) {
                holidaysByRegion.put(key, new List<DE_Holiday__c>());
            }
            holidaysByRegion.get(key).add(h);
        }
    }

    /** Effective [start, end) of a holiday. All-day holidays cover whole local days. */
    public static List<Datetime> holidayWindow(DE_Holiday__c h, String fallbackTz) {
        if (!h.All_Day__c) {
            return new List<Datetime>{ h.Start__c, h.End__c };
        }
        DE_ShiftCalendar cal = DE_ShiftCalendar.always(String.isBlank(h.Timezone__c) ? fallbackTz : h.Timezone__c);
        Date first = cal.localDate(h.Start__c);
        Date last = cal.localDate(h.End__c);
        return new List<Datetime>{ Datetime.newInstance(cal.utcMs(first, 0)), Datetime.newInstance(cal.utcMs(last.addDays(1), 0)) };
    }

    /** Name of the holiday stopping the team right now, or null. */
    public String holidayFor(DE_Model.TeamConfig t) {
        if (String.isBlank(t.team.Holiday_Region__c)) {
            return null;
        }
        List<DE_Holiday__c> hs = holidaysByRegion.get(t.team.Holiday_Region__c.toLowerCase());
        if (hs == null) {
            return null;
        }
        for (DE_Holiday__c h : hs) {
            List<Datetime> w = holidayWindow(h, t.timezoneSid());
            if (at >= w[0] && at < w[1]) {
                return h.Name;
            }
        }
        return null;
    }

    public String oooReason(Id memberId) {
        List<DE_Out_Of_Office__c> items = oooByMember.get(memberId);
        if (items == null) {
            return null;
        }
        for (DE_Out_Of_Office__c o : items) {
            if (at >= o.Start__c && at < o.End__c) {
                return 'Out of office' + (String.isBlank(o.Reason__c) ? '' : ' (' + o.Reason__c + ')');
            }
        }
        return null;
    }

    public Boolean isOutOfOffice(Id memberId) {
        return oooReason(memberId) != null;
    }

    /**
     * Returns why a member is unavailable, or null when available.
     * ignoreUnavailable skips OOO, hours and toggle; ignoreOffline skips only the toggle;
     * ignoreHours skips only distribution hours (trigger distributors).
     */
    public String unavailableReason(DE_Model.Member m, Boolean ignoreUnavailable, Boolean ignoreOffline, Boolean ignoreHours) {
        if (ignoreUnavailable == true) {
            return null;
        }
        String ooo = oooReason(m.memberId);
        if (ooo != null) {
            return ooo;
        }
        if (ignoreHours != true && m.calendar != null && !m.calendar.isWithin(at)) {
            return 'Outside distribution hours';
        }
        if (ignoreOffline != true && !m.isQueue && m.agent != null && !m.agent.Online__c) {
            Boolean timerExpired = m.agent.Toggle_Until__c != null && m.agent.Toggle_Until__c <= at;
            if (!timerExpired) {
                return 'Toggled offline' + (String.isBlank(m.agent.Toggle_Reason__c) ? '' : ' (' + m.agent.Toggle_Reason__c + ')');
            }
        }
        return null;
    }

    private static Map<String, List<DE_Holiday__c>> regionHolidayCache = new Map<String, List<DE_Holiday__c>>();

    /** Holidays of a region from two days ago to 90 days ahead (cached per transaction). */
    public static List<DE_Holiday__c> regionHolidays(String region) {
        String key = region.toLowerCase();
        if (!regionHolidayCache.containsKey(key)) {
            Datetime fromAt = System.now().addDays(-2);
            Datetime toAt = System.now().addDays(90);
            regionHolidayCache.put(
                key,
                [
                    SELECT Id, Name, Region__c, All_Day__c, Start__c, End__c, Timezone__c
                    FROM DE_Holiday__c
                    WHERE Region__c = :region AND Start__c <= :toAt AND End__c >= :fromAt
                ]
            );
        }
        return regionHolidayCache.get(key);
    }

    /**
     * Calendar for SLA and action timing with the team's regional holidays excluded.
     * respectHours: "Team and Member" (member shift, else team shift), "Team Only" (team shift) or "None" (null = wall clock).
     */
    public static DE_ShiftCalendar timingCalendar(DE_Model.TeamConfig t, DE_Model.Member m, String respectHours, Datetime fromAt) {
        if (respectHours == 'None') {
            return null;
        }
        DE_ShiftCalendar base = (respectHours == 'Team Only' || m == null || m.calendar == null) ? t.teamCalendar : m.calendar;
        Boolean hasRegion = String.isNotBlank(t.team.Holiday_Region__c);
        if (base == null && !hasRegion) {
            return null;
        }
        DE_ShiftCalendar cal = base == null ? DE_ShiftCalendar.always(t.timezoneSid()) : base.copy();
        if (hasRegion) {
            for (DE_Holiday__c h : regionHolidays(t.team.Holiday_Region__c)) {
                List<Datetime> w = holidayWindow(h, cal.timezoneSid);
                cal.addExclusion(w[0], w[1]);
            }
        }
        return cal;
    }
}
