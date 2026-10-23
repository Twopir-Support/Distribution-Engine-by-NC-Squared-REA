@IsTest
private class DE_AvailabilityControllerTest {
    private static final String WEEKDAYS = '{"MON":["09:00-17:00"],"TUE":["09:00-17:00"],"WED":["09:00-17:00"],"THU":["09:00-17:00"],"FRI":["09:00-17:00"]}';

    @IsTest
    static void userManagesOwnOutOfOffice() {
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        Datetime startAt = System.now().addDays(1);
        DE_Out_Of_Office__c ooo = new DE_Out_Of_Office__c(
            User__c = UserInfo.getUserId(),
            Start__c = startAt,
            End__c = startAt.addHours(4),
            Reason__c = 'Dentist'
        );

        Id oooId = DE_AvailabilityController.saveOutOfOffice(ooo);

        DE_Out_Of_Office__c saved = [SELECT Source__c FROM DE_Out_Of_Office__c WHERE Id = :oooId];
        Assert.areEqual('Manual', saved.Source__c, 'Source defaults to Manual.');
        List<DE_Out_Of_Office__c> mine = DE_AvailabilityController.getOutOfOffice(null, null, null);
        Assert.areEqual(1, mine.size(), 'The user sees their own out of office.');
        DE_AvailabilityController.deleteOutOfOffice(oooId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Out_Of_Office__c], 'Deleted.');
    }

    @IsTest
    static void validatesOutOfOffice() {
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        Datetime startAt = System.now().addDays(1);
        try {
            DE_AvailabilityController.saveOutOfOffice(
                new DE_Out_Of_Office__c(User__c = UserInfo.getUserId(), Start__c = startAt, End__c = startAt.addHours(-1))
            );
            Assert.fail('End before start is invalid.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('End must be after Start.'), e.getMessage());
        }
        User other = DE_TestFactory.users(1)[0];
        try {
            DE_AvailabilityController.saveOutOfOffice(new DE_Out_Of_Office__c(User__c = other.Id, Start__c = startAt, End__c = startAt.addHours(1)));
            Assert.fail('Users cannot enter out of office for other users.');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(0, [SELECT COUNT() FROM DE_Out_Of_Office__c], 'Nothing saved.');
        }
    }

    @IsTest
    static void allDayOutOfOfficeCoversWholeDays() {
        DE_TestFactory.grantAll();
        User other = DE_TestFactory.users(1)[0];
        Datetime startAt = Datetime.newInstance(System.today().addDays(3), Time.newInstance(12, 0, 0, 0));
        Id oooId = DE_AvailabilityController.saveOutOfOffice(
            new DE_Out_Of_Office__c(User__c = other.Id, Start__c = startAt, End__c = startAt.addMinutes(30), All_Day__c = true)
        );
        DE_Out_Of_Office__c saved = [SELECT Start__c, End__c FROM DE_Out_Of_Office__c WHERE Id = :oooId];
        Long hours = (saved.End__c.getTime() - saved.Start__c.getTime()) / 3600000L;
        Assert.isTrue(hours >= 23 && hours <= 25, 'An all-day entry spans one full local day: ' + hours);
        Assert.isTrue(saved.Start__c <= startAt, 'Start moves to local midnight.');
        Assert.areEqual(1, DE_AvailabilityController.getOutOfOffice(other.Id, null, null).size(), 'Managers can filter by user.');
    }

    @IsTest
    static void managesHolidaysAndRegions() {
        DE_TestFactory.grantAll();
        Id regionId = DE_AvailabilityController.saveHolidayRegion(new DE_Holiday_Region__c(Name = ' UK '));
        DE_Team__c t = DE_TestFactory.team('UK Support', 'Case');
        t.Holiday_Region__c = regionId;
        insert t;
        Datetime day = Datetime.newInstanceGmt(2026, 12, 25, 0, 0, 0);

        Id holidayId = DE_AvailabilityController.saveHoliday(
            new DE_Holiday__c(Name = 'Christmas', Holiday_Region__c = regionId, All_Day__c = true, Start__c = day, End__c = day, Timezone__c = 'Europe/London')
        );

        Assert.areEqual(1, DE_AvailabilityController.getHolidays().size(), 'Holiday listed.');
        List<DE_AvailabilityController.RegionRow> regions = DE_AvailabilityController.getHolidayRegions();
        Assert.areEqual(1, regions.size(), 'One region.');
        Assert.areEqual('UK', regions[0].name, 'Region name is trimmed.');
        Assert.areEqual(new List<String>{ 'UK Support' }, regions[0].teams, 'The region lists the team that uses it.');
        Assert.areEqual(1, regions[0].holidays, 'The region counts its holidays.');
        try {
            DE_AvailabilityController.saveHolidayRegion(new DE_Holiday_Region__c(Name = 'uk'));
            Assert.fail('Region names are unique.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('already exists'), e.getMessage());
        }
        try {
            DE_AvailabilityController.deleteHolidayRegion(regionId);
            Assert.fail('A region in use cannot be deleted.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('1 team(s) and 1 holiday(s)'), e.getMessage());
        }
        try {
            DE_AvailabilityController.saveHoliday(new DE_Holiday__c(Name = 'No region', Start__c = day, End__c = day));
            Assert.fail('A holiday needs a region.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Enter a holiday name and region.'), e.getMessage());
        }
        try {
            DE_AvailabilityController.saveHoliday(new DE_Holiday__c(Name = 'Bad', Holiday_Region__c = regionId, Start__c = day, End__c = day.addDays(-1)));
            Assert.fail('Ends before starts is invalid.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Ends must be on or after Starts.'), e.getMessage());
        }
        DE_AvailabilityController.deleteHoliday(holidayId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Holiday__c], 'Holiday deleted.');
        Id unused = DE_AvailabilityController.saveHolidayRegion(new DE_Holiday_Region__c(Name = 'Unused'));
        DE_AvailabilityController.deleteHolidayRegion(unused);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Holiday_Region__c WHERE Id = :unused], 'An unused region can be deleted.');
    }

    @IsTest
    static void teamManagerCannotEditHolidaysOrShifts() {
        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });
        try {
            DE_AvailabilityController.saveShift(new DE_Shift__c(Name = 'Day', Timezone__c = 'Europe/London', Schedule__c = WEEKDAYS));
            Assert.fail('Shifts need System Manager.');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(0, [SELECT COUNT() FROM DE_Shift__c], 'No shift saved.');
        }
        Assert.areEqual(0, DE_AvailabilityController.getShifts().size(), 'Team managers can still view shifts.');
        try {
            DE_AvailabilityController.saveHolidayRegion(new DE_Holiday_Region__c(Name = 'UK'));
            Assert.fail('Holiday regions are read only for team managers.');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(0, [SELECT COUNT() FROM DE_Holiday_Region__c], 'No region saved.');
        }
        Assert.areEqual(0, DE_AvailabilityController.getHolidayRegions().size(), 'Team managers can view regions.');
    }

    @IsTest
    static void managesShifts() {
        DE_TestFactory.grantAll();
        Id shiftId = DE_AvailabilityController.saveShift(new DE_Shift__c(Name = 'Day', Timezone__c = 'Europe/London', Schedule__c = WEEKDAYS));
        Assert.areEqual(1, DE_AvailabilityController.getShifts().size(), 'Shift saved.');
        try {
            DE_AvailabilityController.saveShift(new DE_Shift__c(Name = 'Broken', Timezone__c = 'Europe/London', Schedule__c = '{not json'));
            Assert.fail('Invalid schedules are rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('not valid JSON'), e.getMessage());
        }
        DE_Team__c t = DE_TestFactory.team('Shifted', 'Lead');
        t.Team_Hours__c = shiftId;
        insert t;
        try {
            DE_AvailabilityController.deleteShift(shiftId);
            Assert.fail('Shifts in use cannot be deleted.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('used by 1'), e.getMessage());
        }
        t.Team_Hours__c = null;
        update t;
        DE_AvailabilityController.deleteShift(shiftId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Shift__c], 'Unused shift deleted.');
    }

    @IsTest
    static void rosterAndManagerToggle() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_TestFactory.grantAll();

        DE_AvailabilityController.setUsersOnline(new List<Id>{ f.users[0].Id }, false, 'Training');

        Map<Id, DE_AvailabilityController.RosterRow> rows = new Map<Id, DE_AvailabilityController.RosterRow>();
        for (DE_AvailabilityController.RosterRow r : DE_AvailabilityController.getRoster(f.team.Id)) {
            rows.put(r.userId, r);
        }
        Assert.areEqual(2, rows.size(), 'Both members are on the roster.');
        Assert.isFalse(rows.get(f.users[0].Id).online, 'The toggled user is offline.');
        Assert.areEqual('Training', rows.get(f.users[0].Id).reason, 'The reason is shown.');
        Assert.isTrue(rows.get(f.users[1].Id).online, 'The other user is still online.');
        Assert.areEqual('Available', rows.get(f.users[1].Id).availability, 'The other user is available.');

        List<DE_Availability_Event__c> history = DE_AvailabilityController.getAvailabilityHistory(f.users[0].Id);
        Assert.areEqual(1, history.size(), 'The toggle is recorded.');
        Assert.areEqual('Manager', history[0].Source__c, 'Toggling someone else is a manager change.');
    }

    @IsTest
    static void userCannotToggleOthers() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.grant(new Set<String>{ 'DE_User' });
        try {
            DE_AvailabilityController.setUsersOnline(new List<Id>{ f.users[0].Id }, false, null);
            Assert.fail('Users can only toggle themselves.');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(0, [SELECT COUNT() FROM DE_Availability_Event__c], 'No change recorded.');
        }
        DE_AvailabilityController.setUsersOnline(new List<Id>{ UserInfo.getUserId() }, false, 'Lunch');
        Assert.areEqual('User', [SELECT Source__c FROM DE_Availability_Event__c].Source__c, 'Self toggles are recorded as User.');
    }

    @IsTest
    static void calendarShowsHolidaysAndOutOfOffice() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_Holiday_Region__c region = new DE_Holiday_Region__c(Name = 'UK');
        insert region;
        f.team.Holiday_Region__c = region.Id;
        update f.team;
        insert new DE_Holiday__c(
            Name = 'Bank Holiday',
            Holiday_Region__c = region.Id,
            All_Day__c = true,
            Start__c = Datetime.newInstanceGmt(2026, 2, 10, 12, 0, 0),
            End__c = Datetime.newInstanceGmt(2026, 2, 10, 12, 0, 0),
            Timezone__c = 'Europe/London'
        );
        insert new DE_Out_Of_Office__c(
            User__c = f.users[0].Id,
            Start__c = Datetime.newInstanceGmt(2026, 2, 15, 12, 0, 0),
            End__c = Datetime.newInstanceGmt(2026, 2, 15, 13, 0, 0)
        );
        DE_TestFactory.grantAll();

        List<DE_AvailabilityController.CalendarDay> days = DE_AvailabilityController.getCalendar(f.team.Id, 2026, 2);

        Assert.areEqual(28, days.size(), 'February 2026 has 28 days.');
        Assert.isTrue(days[9].holiday, '10 February is a holiday.');
        Assert.areEqual('Bank Holiday', days[9].holidayName, 'Holiday name is shown.');
        Assert.isFalse(days[0].holiday, '1 February is not a holiday.');
        Assert.areEqual(1, days[14].outOfOffice, 'One member is out of office on 15 February.');
        Assert.areEqual(1, days[14].working, 'The other member works (no shift = always).');
        Assert.areEqual(2, days[0].working, 'Both work on 1 February.');
        try {
            DE_AvailabilityController.getCalendar(null, 2026, 2);
            Assert.fail('A team is required.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Choose a team'), e.getMessage());
        }
    }

    @IsTest
    static void savesClonesAndListsTags() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(3, 'Round Robin');
        DE_TestFactory.grantAll();

        DE_AvailabilityController.saveTags(f.users[0].Id, 'Language:French\nLanguage:German\nlanguage:french\nTier: Gold');

        DE_Agent__c a = [SELECT Tags__c FROM DE_Agent__c WHERE User__c = :f.users[0].Id];
        Assert.areEqual('Language:French;Language:German;Tier:Gold', a.Tags__c, 'Tags are trimmed and de-duplicated case-insensitively.');

        DE_AvailabilityController.cloneTags(f.users[0].Id, new List<Id>{ f.users[1].Id, f.users[2].Id });
        Integer cloned = 0;
        for (DE_Agent__c agent : [SELECT Tags__c FROM DE_Agent__c]) {
            cloned += agent.Tags__c == 'Language:French;Language:German;Tier:Gold' ? 1 : 0;
        }
        Assert.areEqual(3, cloned, 'Tags cloned to two users.');

        Map<String, List<String>> collections = DE_AvailabilityController.getTagCollections();
        Assert.areEqual(new List<String>{ 'French', 'German' }, collections.get('Language'), 'Language collection lists its tags.');
        Assert.areEqual(new List<String>{ 'Gold' }, collections.get('Tier'), 'Tier collection lists its tag.');
        Assert.areEqual(3, DE_AvailabilityController.getTagAssignments().size(), 'Every member appears on the tag screen.');

        try {
            DE_AvailabilityController.saveTags(f.users[0].Id, 'NoCollection');
            Assert.fail('Tags need a collection.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('must be Collection:Tag'), e.getMessage());
        }
        DE_AvailabilityController.saveTags(f.users[0].Id, '');
        Assert.isNull([SELECT Tags__c FROM DE_Agent__c WHERE User__c = :f.users[0].Id].Tags__c, 'Saving no tags clears them.');
    }
}
