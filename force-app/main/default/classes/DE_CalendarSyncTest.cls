@IsTest
private class DE_CalendarSyncTest {
    @IsTest
    static void outOfOfficeEventCreatesOutOfOffice() {
        DE_TestFactory.settings();
        User u = DE_TestFactory.users(1)[0];
        // Whole seconds: Datetime fields do not store milliseconds.
        Datetime startAt = Datetime.newInstance(System.today().addDays(1), Time.newInstance(10, 0, 0, 0));

        Test.startTest();
        insert new Event(OwnerId = u.Id, Subject = 'Conference', ShowAs = 'OutOfOffice', StartDateTime = startAt, EndDateTime = startAt.addHours(3));
        Test.stopTest();

        DE_Out_Of_Office__c ooo = [SELECT User__c, Start__c, End__c, Reason__c, Source__c, All_Day__c FROM DE_Out_Of_Office__c];
        Assert.areEqual(u.Id, ooo.User__c, 'Out of office for the event owner');
        Assert.areEqual(startAt, ooo.Start__c, 'Starts with the event');
        Assert.areEqual(startAt.addHours(3), ooo.End__c, 'Ends with the event');
        Assert.areEqual('Conference', ooo.Reason__c, 'Subject used as the reason');
        Assert.areEqual('Calendar', ooo.Source__c, 'Source is the calendar');
        Assert.isFalse(ooo.All_Day__c, 'Timed event');
    }

    @IsTest
    static void shortBusyOrIncompleteEventsAreIgnored() {
        DE_TestFactory.settings();
        User u = DE_TestFactory.users(1)[0];
        Datetime startAt = Datetime.newInstance(System.today().addDays(1), Time.newInstance(10, 0, 0, 0));

        Test.startTest();
        DE_CalendarSync.createOutOfOffice(
            new List<SObject>{
                new Event(OwnerId = u.Id, ShowAs = 'OutOfOffice', StartDateTime = startAt, EndDateTime = startAt.addMinutes(30)),
                new Event(OwnerId = u.Id, ShowAs = 'Busy', StartDateTime = startAt, EndDateTime = startAt.addHours(4)),
                new Event(OwnerId = u.Id, ShowAs = 'OutOfOffice', StartDateTime = startAt),
                new Event(OwnerId = u.Id, ShowAs = 'OutOfOffice', StartDateTime = startAt, EndDateTime = startAt.addMinutes(60))
            }
        );
        Test.stopTest();

        List<DE_Out_Of_Office__c> rows = [SELECT Reason__c FROM DE_Out_Of_Office__c];
        Assert.areEqual(1, rows.size(), 'Only the one-hour out of office event qualifies');
        Assert.areEqual('Calendar', rows[0].Reason__c, 'Blank subject falls back to Calendar');
    }

    @IsTest
    static void editingOrDeletingTheEventKeepsOutOfOfficeInStep() {
        DE_TestFactory.settings();
        User u = DE_TestFactory.users(1)[0];
        Datetime startAt = Datetime.newInstance(System.today().addDays(1), Time.newInstance(10, 0, 0, 0));
        Event e = new Event(OwnerId = u.Id, Subject = 'Offsite', ShowAs = 'OutOfOffice', StartDateTime = startAt, EndDateTime = startAt.addHours(3));
        insert e;
        DE_Out_Of_Office__c created = [SELECT Activity_Id__c, Timezone__c FROM DE_Out_Of_Office__c];
        Assert.areEqual(String.valueOf(e.Id), created.Activity_Id__c, 'The entry remembers its event');
        Assert.areEqual('Europe/London', created.Timezone__c, 'The owner timezone is stored');

        Test.startTest();
        e.EndDateTime = startAt.addHours(5);
        update e;
        Assert.areEqual(startAt.addHours(5), [SELECT End__c FROM DE_Out_Of_Office__c].End__c, 'Moving the event moves the entry');

        e.ShowAs = 'Busy';
        update e;
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Out_Of_Office__c], 'An event no longer shown as out of office removes the entry');

        e.ShowAs = 'OutOfOffice';
        update e;
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Out_Of_Office__c], 'Showing it as out of office again recreates the entry');

        delete e;
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Out_Of_Office__c], 'Deleting the event removes the entry');
    }

    @IsTest
    static void allDayEventsCoverWholeDaysInTheOwnerTimezone() {
        DE_TestFactory.settings();
        User u = DE_TestFactory.users(1)[0];
        u.TimeZoneSidKey = 'America/New_York';
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update u;
        }
        Date day = Date.newInstance(2026, 7, 1);
        Event e = new Event(
            OwnerId = u.Id,
            ShowAs = 'OutOfOffice',
            IsAllDayEvent = true,
            ActivityDate = day,
            StartDateTime = Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0)),
            EndDateTime = Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0))
        );
        DE_Out_Of_Office__c o = DE_CalendarSync.entryFor(e, new Map<Id, String>{ u.Id => 'America/New_York' });

        Assert.areEqual(Datetime.newInstanceGmt(2026, 7, 1, 4, 0, 0), o.Start__c, 'Starts at local midnight (UTC-4 in July)');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 7, 2, 4, 0, 0), o.End__c, 'Ends at the next local midnight');
        Assert.isTrue(o.All_Day__c, 'All day');
        Assert.areEqual('America/New_York', o.Timezone__c, 'Owner timezone');
    }
}
