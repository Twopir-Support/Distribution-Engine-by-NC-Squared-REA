@IsTest
private class DE_CalendarSyncTest {
    @IsTest
    static void outOfOfficeEventCreatesOutOfOffice() {
        DE_TestFactory.settings();
        User u = DE_TestFactory.users(1)[0];
        Datetime startAt = System.now().addDays(1);

        Test.startTest();
        insert new Event(
            OwnerId = u.Id,
            Subject = 'Conference',
            ShowAs = 'OutOfOffice',
            StartDateTime = startAt,
            EndDateTime = startAt.addHours(3)
        );
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
        Datetime startAt = System.now().addDays(1);

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
}
