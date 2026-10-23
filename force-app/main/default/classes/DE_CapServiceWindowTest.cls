@IsTest
private class DE_CapServiceWindowTest {
    // Wednesday 17 January 2024, 14:45:30 GMT
    private static final Datetime NOW = Datetime.newInstanceGmt(2024, 1, 17, 14, 45, 30);

    private static Datetime gmt(Integer month, Integer day, Integer hour, Integer minute, Integer second) {
        return Datetime.newInstanceGmt(2024, month, day, hour, minute, second);
    }

    @IsTest
    static void fixedPeriodsResetAtBoundaries() {
        DE_Settings.setForTransaction(new DE_Settings__c());
        Assert.areEqual(gmt(1, 17, 14, 0, 0), DE_CapService.windowStart('Hourly', null, NOW, 'GMT'), 'hourly');
        Assert.areEqual(gmt(1, 17, 14, 30, 0), DE_CapService.windowStart('Half-hourly', null, NOW, 'GMT'), 'half-hourly');
        Assert.areEqual(gmt(1, 17, 0, 0, 0), DE_CapService.windowStart('Daily', null, NOW, 'GMT'), 'daily');
        Assert.areEqual(gmt(1, 15, 0, 0, 0), DE_CapService.windowStart('Weekly', null, NOW, 'GMT'), 'weekly starts on Monday by default');
        Assert.areEqual(gmt(1, 1, 0, 0, 0), DE_CapService.windowStart('Monthly', null, NOW, 'GMT'), 'monthly');
    }

    @IsTest
    static void weeksCanStartOnSunday() {
        DE_Settings.setForTransaction(new DE_Settings__c(Default_Weekday_Start__c = 'Sunday'));
        Assert.areEqual(gmt(1, 14, 0, 0, 0), DE_CapService.windowStart('Weekly', null, NOW, 'GMT'), 'weekly starts on Sunday');
        Datetime sunday = gmt(1, 21, 10, 0, 0);
        Assert.areEqual(gmt(1, 21, 0, 0, 0), DE_CapService.windowStart('Weekly', null, sunday, 'GMT'), 'Sunday is the first day of its own week');
    }

    @IsTest
    static void boundariesFollowTheTeamTimezone() {
        // 03:00 GMT on the 17th is 22:00 on the 16th in New York (GMT-5)
        Datetime at = gmt(1, 17, 3, 0, 0);
        Assert.areEqual(gmt(1, 16, 5, 0, 0), DE_CapService.windowStart('Daily', null, at, 'America/New_York'), 'New York midnight');
        Assert.areEqual(gmt(1, 17, 3, 0, 0), DE_CapService.windowStart('Hourly', null, gmt(1, 17, 3, 59, 0), 'America/New_York'), 'whole-hour offset');
        // India is GMT+5:30, so local hours start at :30 GMT
        Assert.areEqual(gmt(1, 17, 2, 30, 0), DE_CapService.windowStart('Hourly', null, at, 'Asia/Kolkata'), 'half-hour offset');
    }

    @IsTest
    static void customPeriodsAreRolling() {
        Assert.areEqual(NOW.addMinutes(-15), DE_CapService.windowStart('Custom Minutes', 15, NOW, 'GMT'), 'custom minutes');
        Assert.areEqual(NOW.addMinutes(-60), DE_CapService.windowStart('Custom Minutes', null, NOW, 'GMT'), 'custom minutes default 60');
        Assert.areEqual(NOW.addHours(-2), DE_CapService.windowStart('Custom Hours', 2, NOW, 'GMT'), 'custom hours');
        Assert.areEqual(NOW.addHours(-1), DE_CapService.windowStart('Custom Hours', null, NOW, 'GMT'), 'custom hours default 1');
        Assert.areEqual(NOW.addDays(-3), DE_CapService.windowStart('Custom Days', 3, NOW, 'GMT'), 'custom days');
        Assert.isNull(DE_CapService.windowStart('Active', null, NOW, 'GMT'), 'active caps have no window');
        Assert.isNull(DE_CapService.windowStart('Criteria', null, NOW, 'GMT'), 'criteria caps have no window');
    }

    @IsTest
    static void tagCapsOverrideTheDefault() {
        DE_Cap__c cap = new DE_Cap__c(Default_Cap__c = 5, Tag_Caps__c = 'Tier:Gold=10\nTier:Silver=\nnot a cap line');
        DE_Model.Member gold = member('Tier:Gold;Language:French');
        DE_Model.Member silver = member('Tier:Silver');
        DE_Model.Member other = member('Language:German');
        Assert.isTrue(DE_CapService.capFor(cap, gold) == 10, 'gold tag cap');
        Assert.isNull(DE_CapService.capFor(cap, silver), 'blank tag cap means unlimited');
        Assert.isTrue(DE_CapService.capFor(cap, other) == 5, 'default cap');
        Assert.isNull(DE_CapService.capFor(new DE_Cap__c(), other), 'no default cap means unlimited');
    }

    private static DE_Model.Member member(String tags) {
        DE_Model.Member m = new DE_Model.Member();
        m.record = new DE_Team_Member__c(Active__c = true);
        m.tags = DE_Model.parseTags(tags);
        return m;
    }
}
