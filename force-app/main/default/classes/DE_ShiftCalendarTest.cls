@IsTest
private class DE_ShiftCalendarTest {
    private static final String WEEKDAYS = '{"MON":["09:00-17:00"],"TUE":["09:00-17:00"],"WED":["09:00-17:00"],"THU":["09:00-17:00"],"FRI":["09:00-17:00"]}';

    // 2024-01-15 is a Monday
    private static Datetime gmt(Integer day, Integer hour, Integer minute) {
        return Datetime.newInstanceGmt(2024, 1, day, hour, minute, 0);
    }

    @IsTest
    static void validatesSchedules() {
        Assert.isNull(DE_ShiftCalendar.validate(WEEKDAYS), 'Valid weekday schedule');
        Assert.isNull(DE_ShiftCalendar.validate('{"Monday":["09:00-12:00","13:00-17:30"],"FRI":["22:00-06:00+1"]}'), 'Full day names and overnight blocks');
        Assert.isTrue(DE_ShiftCalendar.validate(null).contains('at least one block'), 'blank');
        Assert.isTrue(DE_ShiftCalendar.validate('{}').contains('at least one block'), 'no blocks');
        Assert.isTrue(DE_ShiftCalendar.validate('not json').contains('not valid JSON'), 'bad JSON');
        Assert.isTrue(DE_ShiftCalendar.validate('[1,2]').contains('must map days'), 'not a map');
        Assert.isTrue(DE_ShiftCalendar.validate('{"XYZ":[]}').contains('is not a day'), 'unknown day');
        Assert.isTrue(
            DE_ShiftCalendar.validate('{"MON":["01:00-02:00","03:00-04:00","05:00-06:00","07:00-08:00"]}').contains('more than three blocks'),
            'too many blocks'
        );
        Assert.isTrue(DE_ShiftCalendar.validate('{"MON":["09:00-12:00","11:00-13:00"]}').contains('overlapping'), 'overlap');
        Assert.isTrue(DE_ShiftCalendar.validate('{"MON":["17:00-09:00"]}').contains('ends before it starts'), 'reversed block');
        Assert.isTrue(DE_ShiftCalendar.validate('{"MON":["25:00-26:00"]}').contains('not a valid time range'), 'hour out of range');
        Assert.isTrue(DE_ShiftCalendar.validate('{"MON":["09:75-10:00"]}').contains('not a valid time range'), 'minute out of range');
        Assert.isTrue(DE_ShiftCalendar.validate('{"MON":["9am-5pm"]}').contains('must look like'), 'bad format');
    }

    @IsTest
    static void isWithinWorkingHours() {
        DE_ShiftCalendar cal = new DE_ShiftCalendar('GMT', WEEKDAYS);
        Assert.isFalse(cal.isAlwaysOpen(), 'A schedule is not always open');
        Assert.isTrue(cal.isWithin(gmt(15, 10, 0)), 'Monday 10:00');
        Assert.isTrue(cal.isWithin(gmt(15, 9, 0)), 'block start is inclusive');
        Assert.isFalse(cal.isWithin(gmt(15, 8, 59)), 'before the block');
        Assert.isFalse(cal.isWithin(gmt(15, 17, 0)), 'block end is exclusive');
        Assert.isFalse(cal.isWithin(gmt(20, 10, 0)), 'Saturday');
    }

    @IsTest
    static void overnightBlocksCrossMidnight() {
        DE_ShiftCalendar cal = new DE_ShiftCalendar('GMT', '{"FRI":["22:00-06:00+1"]}');
        Assert.isTrue(cal.isWithin(gmt(19, 23, 0)), 'Friday 23:00');
        Assert.isTrue(cal.isWithin(gmt(20, 5, 0)), 'Saturday 05:00 belongs to the Friday block');
        Assert.isFalse(cal.isWithin(gmt(20, 7, 0)), 'Saturday 07:00');
        Assert.isFalse(cal.isWithin(gmt(19, 21, 0)), 'Friday 21:00');
    }

    @IsTest
    static void respectsTimezoneAndDaylightSaving() {
        DE_ShiftCalendar cal = new DE_ShiftCalendar('Europe/London', WEEKDAYS);
        // 2024-07-15 is a Monday; London is GMT+1 in July
        Assert.isTrue(cal.isWithin(Datetime.newInstanceGmt(2024, 7, 15, 8, 30, 0)), '09:30 local');
        Assert.isFalse(cal.isWithin(Datetime.newInstanceGmt(2024, 7, 15, 7, 30, 0)), '08:30 local');
        Assert.isFalse(cal.isWithin(Datetime.newInstanceGmt(2024, 7, 15, 16, 30, 0)), '17:30 local');

        DE_ShiftCalendar ny = DE_ShiftCalendar.always('America/New_York');
        Assert.areEqual(Date.newInstance(2024, 1, 15), ny.localDate(gmt(16, 3, 0)), '03:00 GMT is the previous evening in New York');
        Assert.areEqual(gmt(15, 5, 0), ny.localMidnight(gmt(16, 3, 0)), 'New York midnight in GMT');
    }

    @IsTest
    static void addsWorkingMinutes() {
        DE_ShiftCalendar cal = new DE_ShiftCalendar('GMT', WEEKDAYS);
        Assert.areEqual(gmt(15, 10, 30), cal.addWorkingMinutes(gmt(15, 10, 0), 30), 'within the same block');
        Assert.areEqual(gmt(22, 9, 30), cal.addWorkingMinutes(gmt(19, 16, 30), 60), 'Friday 16:30 + 60 rolls over the weekend');
        Assert.areEqual(gmt(22, 9, 15), cal.addWorkingMinutes(gmt(20, 12, 0), 15), 'starting at the weekend');
        Assert.areEqual(gmt(15, 10, 0), cal.addWorkingMinutes(gmt(15, 10, 0), 0), 'zero minutes');

        DE_ShiftCalendar never = new DE_ShiftCalendar('GMT', '{}');
        Assert.isNull(never.addWorkingMinutes(gmt(15, 10, 0), 30), 'no working time at all');
    }

    @IsTest
    static void countsWorkingMinutesWithExclusions() {
        DE_ShiftCalendar cal = new DE_ShiftCalendar('GMT', WEEKDAYS);
        Assert.areEqual(180, cal.workingMinutesBetween(gmt(15, 8, 0), gmt(15, 12, 0)).intValue(), 'Monday 08:00-12:00');
        Assert.areEqual(480, cal.workingMinutesBetween(gmt(19, 13, 0), gmt(22, 13, 0)).intValue(), 'Friday 13:00 to Monday 13:00');
        Assert.areEqual(0, cal.workingMinutesBetween(gmt(15, 12, 0), gmt(15, 8, 0)).intValue(), 'reversed range');
        Assert.areEqual(0, cal.workingMinutesBetween(null, gmt(15, 8, 0)).intValue(), 'null start');

        DE_ShiftCalendar copy = cal.copy();
        copy.addExclusion(gmt(15, 10, 0), gmt(15, 11, 0));
        copy.addExclusion(gmt(15, 11, 0), gmt(15, 10, 0)); // ignored: ends before it starts
        Assert.areEqual(120, copy.workingMinutesBetween(gmt(15, 8, 0), gmt(15, 12, 0)).intValue(), 'exclusion removed');
        Assert.isFalse(copy.isWithin(gmt(15, 10, 30)), 'inside the exclusion');
        Assert.areEqual(180, cal.workingMinutesBetween(gmt(15, 8, 0), gmt(15, 12, 0)).intValue(), 'the copy does not change the original');
        Assert.areEqual(gmt(15, 11, 30), copy.addWorkingMinutes(gmt(15, 9, 30), 60), 'working minutes skip the exclusion');
    }

    @IsTest
    static void alwaysOpenCalendars() {
        DE_ShiftCalendar cal = DE_ShiftCalendar.always('GMT');
        Assert.isTrue(cal.isAlwaysOpen(), 'no schedule means 24x7');
        Assert.isTrue(cal.isWithin(gmt(20, 3, 0)), 'Saturday night');
        Assert.isNull(cal.lastBlockEnd(gmt(15, 10, 0)), 'no block end for 24x7');
        cal.addExclusion(gmt(15, 10, 0), gmt(15, 10, 30));
        Assert.isFalse(cal.isAlwaysOpen(), 'an exclusion makes it no longer always open');
        Assert.areEqual(90, cal.workingMinutesBetween(gmt(15, 9, 0), gmt(15, 11, 0)).intValue(), '2 hours minus 30 minutes');

        DE_ShiftCalendar userTz = new DE_ShiftCalendar(null, null);
        Assert.areEqual(UserInfo.getTimeZone().getID(), userTz.timezoneSid, 'blank timezone falls back to the user timezone');
        Assert.isNull(DE_ShiftCalendar.fromShift(null), 'no shift');
        DE_ShiftCalendar fromShift = DE_ShiftCalendar.fromShift(new DE_Shift__c(Timezone__c = 'Europe/Paris', Schedule__c = WEEKDAYS));
        Assert.areEqual('Europe/Paris', fromShift.timezoneSid, 'shift timezone');
    }

    @IsTest
    static void intervalsAreSortedAndLastBlockEnd() {
        DE_ShiftCalendar cal = new DE_ShiftCalendar('GMT', '{"MON":["13:00-17:30","09:00-12:00"]}');
        List<DE_ShiftCalendar.Interval> items = cal.intervals(gmt(15, 0, 0).getTime(), gmt(16, 0, 0).getTime());
        Assert.areEqual(2, items.size(), 'two Monday blocks');
        Assert.areEqual(gmt(15, 9, 0).getTime(), items[0].startMs, 'sorted by start');
        Assert.areEqual(gmt(15, 17, 30), cal.lastBlockEnd(gmt(15, 10, 0)), 'end of the latest Monday block');
        Assert.isNull(cal.lastBlockEnd(gmt(16, 10, 0)), 'no Tuesday blocks');
        Assert.areEqual(0, DE_ShiftCalendar.dayIndex(Date.newInstance(2024, 1, 15)), 'Monday is 0');
        Assert.areEqual(6, DE_ShiftCalendar.dayIndex(Date.newInstance(2024, 1, 21)), 'Sunday is 6');
    }
}
