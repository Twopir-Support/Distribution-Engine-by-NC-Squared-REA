/**
 * Working-hours calendar built from a DE_Shift__c schedule (up to three blocks per weekday,
 * overnight blocks marked +1) in an IANA timezone, minus holiday/exclusion intervals.
 *
 * Schedule JSON: {"MON":["09:00-12:00","13:00-17:30"],"FRI":["22:00-06:00+1"]}
 * A calendar without a schedule is "always open" (24x7) apart from exclusions.
 */
public inherited sharing class DE_ShiftCalendar {
    public static final List<String> DAYS = new List<String>{ 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN' };
    private static final Date MONDAY_REF = Date.newInstance(1900, 1, 1); // a Monday
    private static final Long MINUTE_MS = 60000L;
    private static final Long DAY_MS = 86400000L;
    private static final Integer MAX_SCAN_DAYS = 400;

    public class ShiftException extends Exception {
    }

    public class Interval {
        public Long startMs;
        public Long endMs;
        public Interval(Long s, Long e) {
            startMs = s;
            endMs = e;
        }
    }

    private class Block {
        Integer startMin;
        Integer endMin; // may exceed 1440 for overnight blocks
        Block(Integer s, Integer e) {
            startMin = s;
            endMin = e;
        }
    }

    public String timezoneSid { get; private set; }
    private TimeZone tz;
    private Boolean alwaysOpen;
    private Map<Integer, List<Block>> blocksByDay = new Map<Integer, List<Block>>();
    private List<Interval> exclusions = new List<Interval>();

    public DE_ShiftCalendar(String timezoneSid, String scheduleJson) {
        this.timezoneSid = String.isBlank(timezoneSid) ? UserInfo.getTimeZone().getID() : timezoneSid.trim();
        this.tz = TimeZone.getTimeZone(this.timezoneSid);
        this.alwaysOpen = String.isBlank(scheduleJson);
        if (!alwaysOpen) {
            parse(scheduleJson);
        }
    }

    /** A copy sharing the schedule but with its own exclusion list. */
    public DE_ShiftCalendar copy() {
        DE_ShiftCalendar c = new DE_ShiftCalendar(timezoneSid, null);
        c.alwaysOpen = alwaysOpen;
        c.blocksByDay = blocksByDay;
        c.exclusions = new List<Interval>(exclusions);
        return c;
    }

    public static DE_ShiftCalendar fromShift(DE_Shift__c shift) {
        return shift == null ? null : new DE_ShiftCalendar(shift.Timezone__c, shift.Schedule__c);
    }

    public static DE_ShiftCalendar always(String timezoneSid) {
        return new DE_ShiftCalendar(timezoneSid, null);
    }

    public Boolean isAlwaysOpen() {
        return alwaysOpen && exclusions.isEmpty();
    }

    public void addExclusion(Datetime startAt, Datetime endAt) {
        if (startAt != null && endAt != null && endAt > startAt) {
            exclusions.add(new Interval(startAt.getTime(), endAt.getTime()));
        }
    }

    // ------------------------------------------------------------------ parsing / validation

    /** Returns an error message for an invalid schedule, or null. */
    public static String validate(String scheduleJson) {
        if (String.isBlank(scheduleJson)) {
            return 'Add at least one block of working hours.';
        }
        try {
            DE_ShiftCalendar c = new DE_ShiftCalendar('GMT', scheduleJson);
            Boolean hasBlocks = false;
            for (List<Block> b : c.blocksByDay.values()) {
                hasBlocks = hasBlocks || !b.isEmpty();
            }
            return hasBlocks ? null : 'Add at least one block of working hours.';
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    private void parse(String scheduleJson) {
        Object raw;
        try {
            raw = JSON.deserializeUntyped(scheduleJson);
        } catch (Exception e) {
            throw new ShiftException('The shift schedule is not valid JSON.');
        }
        if (!(raw instanceof Map<String, Object>)) {
            throw new ShiftException('The shift schedule must map days to blocks.');
        }
        Map<String, Object> m = (Map<String, Object>) raw;
        for (String key : m.keySet()) {
            String day = key.trim().toUpperCase().left(3);
            Integer idx = DAYS.indexOf(day);
            if (idx < 0) {
                throw new ShiftException('"' + key + '" is not a day. Use MON, TUE, WED, THU, FRI, SAT or SUN.');
            }
            List<Block> blocks = new List<Block>();
            Object v = m.get(key);
            List<Object> items = v instanceof List<Object> ? (List<Object>) v : new List<Object>();
            if (items.size() > 3) {
                throw new ShiftException(label(idx) + ' has more than three blocks.');
            }
            for (Object item : items) {
                blocks.add(parseBlock(String.valueOf(item), idx));
            }
            for (Integer i = 0; i < blocks.size(); i++) {
                for (Integer j = i + 1; j < blocks.size(); j++) {
                    if (blocks[i].startMin < blocks[j].endMin && blocks[j].startMin < blocks[i].endMin) {
                        throw new ShiftException(label(idx) + ' has overlapping blocks.');
                    }
                }
            }
            blocksByDay.put(idx, blocks);
        }
    }

    private static String label(Integer idx) {
        return new List<String>{ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' }[idx];
    }

    private static Block parseBlock(String text, Integer dayIdx) {
        Matcher mt = Pattern.compile('^\\s*(\\d{1,2}):(\\d{2})\\s*-\\s*(\\d{1,2}):(\\d{2})\\s*(\\+1)?\\s*$').matcher(text == null ? '' : text);
        if (!mt.matches()) {
            throw new ShiftException(label(dayIdx) + ': "' + text + '" must look like 09:00-17:30 (add +1 for overnight).');
        }
        Integer s = Integer.valueOf(mt.group(1)) * 60 + Integer.valueOf(mt.group(2));
        Integer e = Integer.valueOf(mt.group(3)) * 60 + Integer.valueOf(mt.group(4));
        if (s > 1440 || e > 1440 || Integer.valueOf(mt.group(2)) > 59 || Integer.valueOf(mt.group(4)) > 59) {
            throw new ShiftException(label(dayIdx) + ': "' + text + '" is not a valid time range.');
        }
        if (mt.group(5) != null) {
            e += 1440;
        } else if (e <= s) {
            throw new ShiftException(label(dayIdx) + ': "' + text + '" ends before it starts. Add +1 for blocks that end the next day.');
        }
        return new Block(s, e);
    }

    // ------------------------------------------------------------------ time helpers

    public static Integer dayIndex(Date d) {
        return Math.mod(MONDAY_REF.daysBetween(d), 7);
    }

    /** Local calendar date of an instant in this calendar's timezone. */
    public Date localDate(Datetime dt) {
        Long localMs = dt.getTime() + tz.getOffset(dt);
        return Datetime.newInstance(localMs).dateGmt();
    }

    /** UTC instant for a local wall-clock time on a local date. */
    public Long utcMs(Date localDay, Integer minuteOfDay) {
        Long localMs = Datetime.newInstanceGmt(localDay, Time.newInstance(0, 0, 0, 0)).getTime() + minuteOfDay * MINUTE_MS;
        Long guess = localMs - tz.getOffset(Datetime.newInstance(localMs));
        return localMs - tz.getOffset(Datetime.newInstance(guess));
    }

    public Datetime localMidnight(Datetime dt) {
        return Datetime.newInstance(utcMs(localDate(dt), 0));
    }

    // ------------------------------------------------------------------ queries

    /** Working intervals intersecting [fromMs, toMs), sorted and with exclusions removed. */
    public List<Interval> intervals(Long fromMs, Long toMs) {
        List<Interval> raw = new List<Interval>();
        if (alwaysOpen) {
            raw.add(new Interval(fromMs, toMs));
        } else {
            Date first = localDate(Datetime.newInstance(fromMs)).addDays(-1);
            Date last = localDate(Datetime.newInstance(toMs));
            for (Date d = first; d <= last; d = d.addDays(1)) {
                List<Block> blocks = blocksByDay.get(dayIndex(d));
                if (blocks == null) {
                    continue;
                }
                for (Block b : blocks) {
                    Long s = Math.max(utcMs(d, b.startMin), fromMs);
                    Long e = Math.min(utcMs(d, b.endMin), toMs);
                    if (e > s) {
                        raw.add(new Interval(s, e));
                    }
                }
            }
        }
        return subtract(sortIntervals(raw), exclusions);
    }

    private static List<Interval> sortIntervals(List<Interval> items) {
        // insertion sort: lists here are small (a few blocks per day)
        for (Integer i = 1; i < items.size(); i++) {
            Interval cur = items[i];
            Integer j = i - 1;
            while (j >= 0 && items[j].startMs > cur.startMs) {
                items[j + 1] = items[j];
                j--;
            }
            items[j + 1] = cur;
        }
        return items;
    }

    private static List<Interval> subtract(List<Interval> base, List<Interval> cuts) {
        if (cuts.isEmpty()) {
            return base;
        }
        List<Interval> current = base;
        for (Interval c : cuts) {
            List<Interval> next = new List<Interval>();
            for (Interval i : current) {
                if (c.endMs <= i.startMs || c.startMs >= i.endMs) {
                    next.add(i);
                    continue;
                }
                if (c.startMs > i.startMs) {
                    next.add(new Interval(i.startMs, c.startMs));
                }
                if (c.endMs < i.endMs) {
                    next.add(new Interval(c.endMs, i.endMs));
                }
            }
            current = next;
        }
        return current;
    }

    public Boolean isWithin(Datetime dt) {
        Long t = dt.getTime();
        return !intervals(t, t + 1).isEmpty();
    }

    /** Adds working minutes to a start instant. Returns null if the calendar has no working time within the scan window. */
    public Datetime addWorkingMinutes(Datetime start, Decimal minutes) {
        Long remaining = (minutes * MINUTE_MS).longValue();
        if (remaining <= 0) {
            return start;
        }
        Long cursor = start.getTime();
        for (Integer chunk = 0; chunk < MAX_SCAN_DAYS / 14; chunk++) {
            Long windowEnd = cursor + 14 * DAY_MS;
            for (Interval i : intervals(cursor, windowEnd)) {
                Long len = i.endMs - i.startMs;
                if (len >= remaining) {
                    return Datetime.newInstance(i.startMs + remaining);
                }
                remaining -= len;
            }
            cursor = windowEnd;
        }
        return null;
    }

    /** Working minutes between two instants (0 when b <= a). */
    public Decimal workingMinutesBetween(Datetime a, Datetime b) {
        if (a == null || b == null || b <= a) {
            return 0;
        }
        Long total = 0;
        for (Interval i : intervals(a.getTime(), b.getTime())) {
            total += i.endMs - i.startMs;
        }
        return Decimal.valueOf(total).divide(MINUTE_MS, 1);
    }

    /** End of the last working block that starts on the local date of dt, or null when none. */
    public Datetime lastBlockEnd(Datetime dt) {
        if (alwaysOpen) {
            return null;
        }
        Date d = localDate(dt);
        List<Block> blocks = blocksByDay.get(dayIndex(d));
        if (blocks == null || blocks.isEmpty()) {
            return null;
        }
        Integer latest = 0;
        for (Block b : blocks) {
            latest = Math.max(latest, b.endMin);
        }
        return Datetime.newInstance(utcMs(d, latest));
    }
}
