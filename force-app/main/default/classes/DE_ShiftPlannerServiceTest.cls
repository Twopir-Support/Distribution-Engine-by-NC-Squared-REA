@IsTest
private class DE_ShiftPlannerServiceTest {
    private static final String ALWAYS = '{"MON":["00:00-24:00"],"TUE":["00:00-24:00"],"WED":["00:00-24:00"],"THU":["00:00-24:00"],"FRI":["00:00-24:00"],"SAT":["00:00-24:00"],"SUN":["00:00-24:00"]}';

    private static DE_Shift__c shift(String name, String schedule) {
        DE_Shift__c s = new DE_Shift__c(Name = name, Timezone__c = 'GMT', Schedule__c = schedule);
        insert s;
        return s;
    }

    /** A schedule that only works on a weekday that is not today, so a member on it is outside hours now. */
    private static String notToday() {
        Integer today = DE_ShiftCalendar.dayIndex(System.now().dateGmt());
        return '{"' + DE_ShiftCalendar.DAYS[Math.mod(today + 3, 7)] + '":["09:00-10:00"]}';
    }

    private static DE_ShiftPlannerService.Change change(Id memberId, Date week, Id shiftId) {
        DE_ShiftPlannerService.Change c = new DE_ShiftPlannerService.Change();
        c.memberId = memberId;
        c.weekStart = week;
        c.shiftId = shiftId;
        return c;
    }

    @IsTest
    static void weekStartIsMonday() {
        Date d = Date.newInstance(2026, 10, 23); // a Friday
        Assert.areEqual(Date.newInstance(2026, 10, 19), DE_ShiftPlannerService.weekStart(d), 'Weeks start on Monday');
        Assert.areEqual(Date.newInstance(2026, 10, 19), DE_ShiftPlannerService.weekStart(Date.newInstance(2026, 10, 19)), 'A Monday is its own week start');
    }

    @IsTest
    static void enableSeedsCurrentShiftsAndDisableKeepsTheCurrentShift() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_Shift__c day = shift('Day', ALWAYS);
        DE_Shift__c late = shift('Late', ALWAYS);
        f.team.Team_Hours__c = day.Id;
        update f.team;
        Date current = DE_ShiftPlannerService.weekStart(Date.today());

        DE_ShiftPlannerService.enable(f.team.Id);

        Assert.isTrue([SELECT Use_Shift_Planner__c FROM DE_Team__c WHERE Id = :f.team.Id].Use_Shift_Planner__c, 'Planner on');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Shift_Plan__c WHERE Team__c = :f.team.Id], 'One planner per team');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM DE_Shift_Plan_Block__c WHERE Start_Date__c = :current AND Shift__c = :day.Id],
            'Each member starts on the team hours this week'
        );

        DE_ShiftPlannerService.applyChanges(
            f.team.Id,
            new List<DE_ShiftPlannerService.Change>{ change(f.members[0].Id, current, late.Id), change(f.members[1].Id, current.addDays(14), late.Id) }
        );
        Map<Id, Id> today = DE_ShiftPlannerService.shiftsOn(new Set<Id>{ f.members[0].Id, f.members[1].Id }, Date.today());
        Assert.areEqual(late.Id, today.get(f.members[0].Id), 'This week\'s change applies now');
        Assert.areEqual(day.Id, today.get(f.members[1].Id), 'A future change does not apply yet');
        DE_Shift_Plan_Block__c first = [
            SELECT End_Date__c
            FROM DE_Shift_Plan_Block__c
            WHERE Team_Member__c = :f.members[1].Id AND Start_Date__c = :current
        ];
        Assert.areEqual(current.addDays(13), first.End_Date__c, 'A block ends the day before the member\'s next block');

        DE_ShiftPlannerService.disable(f.team.Id);

        Assert.isFalse([SELECT Use_Shift_Planner__c FROM DE_Team__c WHERE Id = :f.team.Id].Use_Shift_Planner__c, 'Planner off');
        Assert.areEqual(
            late.Id,
            [SELECT Member_Hours__c FROM DE_Team_Member__c WHERE Id = :f.members[0].Id].Member_Hours__c,
            'Members keep their current shift'
        );
        Assert.areEqual(day.Id, [SELECT Member_Hours__c FROM DE_Team_Member__c WHERE Id = :f.members[1].Id].Member_Hours__c, 'Current, not future, shift kept');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Shift_Plan_Block__c WHERE Start_Date__c > :Date.today()], 'Future changes are removed');
    }

    @IsTest
    static void removingAChangeAndRejectingInvalidChanges() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.Fixture other = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Shift__c day = shift('Day', ALWAYS);
        Date current = DE_ShiftPlannerService.weekStart(Date.today());
        Id member = f.members[0].Id;

        DE_ShiftPlannerService.applyChanges(f.team.Id, new List<DE_ShiftPlannerService.Change>{ change(member, current.addDays(9), day.Id) });
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Shift_Plan_Block__c WHERE Start_Date__c = :current.addDays(7)], 'Dates snap to the week start');

        DE_ShiftPlannerService.applyChanges(f.team.Id, new List<DE_ShiftPlannerService.Change>{ change(member, current.addDays(7), null) });
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Shift_Plan_Block__c], 'A change without a shift removes the planned change');

        List<DE_ShiftPlannerService.Change> invalid = new List<DE_ShiftPlannerService.Change>{
            change(member, current.addDays(7 * 13), day.Id),
            change(member, current.addDays(-7), day.Id),
            change(other.members[0].Id, current, day.Id),
            change(member, null, day.Id)
        };
        for (DE_ShiftPlannerService.Change c : invalid) {
            try {
                DE_ShiftPlannerService.applyChanges(f.team.Id, new List<DE_ShiftPlannerService.Change>{ c });
                Assert.fail('Invalid change accepted: ' + c.weekStart);
            } catch (DE_ShiftPlannerService.PlannerException e) {
                Assert.isTrue(String.isNotBlank(e.getMessage()), 'Explains the problem');
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Shift_Plan_Block__c], 'Nothing saved for invalid changes');
    }

    @IsTest
    static void gridShowsSeventeenWeeksWithEffectiveShifts() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Shift__c day = shift('Day', ALWAYS);
        DE_Shift__c late = shift('Late', ALWAYS);
        Date current = DE_ShiftPlannerService.weekStart(Date.today());
        DE_ShiftPlannerService.applyChanges(
            f.team.Id,
            new List<DE_ShiftPlannerService.Change>{ change(f.members[0].Id, current, day.Id), change(f.members[0].Id, current.addDays(14), late.Id) }
        );

        DE_ShiftPlannerService.Grid g = DE_ShiftPlannerService.grid(f.team.Id);

        Assert.areEqual(17, g.weeks.size(), '4 weeks back, this week and 12 ahead');
        Assert.areEqual(String.valueOf(current), g.currentWeek, 'Current week');
        DE_ShiftPlannerService.Row r = g.rows[0];
        Assert.isNull(r.cells[3].shiftId, 'No shift before the first change');
        Assert.isFalse(r.cells[3].editable, 'Past weeks are read only');
        Assert.areEqual(day.Id, r.cells[4].shiftId, 'This week');
        Assert.isTrue(r.cells[4].isChange && r.cells[4].editable, 'This week is a change and editable');
        Assert.areEqual(day.Id, r.cells[5].shiftId, 'Next week continues the shift');
        Assert.isFalse(r.cells[5].isChange, 'Not a change');
        Assert.areEqual('Late', r.cells[6].shiftName, 'The planned change applies from its week');
    }

    @IsTest
    static void plannedShiftDecidesAvailability() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_Shift__c allDay = shift('Always', ALWAYS);
        DE_Shift__c never = shift('Elsewhere', notToday());
        f.team.Use_Shift_Planner__c = true;
        update f.team;
        // Member hours say "available"; the planner overrides them for member 1 only.
        f.members[0].Member_Hours__c = allDay.Id;
        f.members[1].Member_Hours__c = allDay.Id;
        update f.members;
        DE_ShiftPlannerService.applyChanges(
            f.team.Id,
            new List<DE_ShiftPlannerService.Change>{ change(f.members[0].Id, DE_ShiftPlannerService.weekStart(Date.today()), never.Id) }
        );

        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(f.team.Id, true);
        DE_AvailabilityService availability = new DE_AvailabilityService(new List<DE_Model.TeamConfig>{ cfg }, System.now());

        Assert.areEqual('Outside distribution hours', availability.unavailableReason(cfg.member(f.users[0].Id), false, false, false), 'Planned shift applies');
        Assert.isNull(availability.unavailableReason(cfg.member(f.users[1].Id), false, false, false), 'Members without a plan use member hours');

        f.team.Use_Shift_Planner__c = false;
        update f.team;
        DE_Model.TeamConfig off = DE_ConfigRepository.team(f.team.Id, true);
        Assert.isNull(
            new DE_AvailabilityService(new List<DE_Model.TeamConfig>{ off }, System.now()).unavailableReason(off.member(f.users[0].Id), false, false, false),
            'Blocks are ignored when the planner is off'
        );
    }

    @IsTest
    static void controllerPermissions() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Shift__c day = shift('Day', ALWAYS);
        Date current = DE_ShiftPlannerService.weekStart(Date.today());

        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });
        try {
            DE_AdminController.setShiftPlannerEnabled(f.team.Id, true);
            Assert.fail('Team managers cannot switch the planner on');
        } catch (DE_Permissions.AccessException e) {
            Assert.isFalse([SELECT Use_Shift_Planner__c FROM DE_Team__c WHERE Id = :f.team.Id].Use_Shift_Planner__c, 'Still off');
        }
        try {
            DE_AdminController.saveShiftPlanner(f.team.Id, new List<DE_ShiftPlannerService.Change>{ change(f.members[0].Id, current, day.Id) });
            Assert.fail('Only managers of the team can plan its shifts');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(0, [SELECT COUNT() FROM DE_Shift_Plan_Block__c], 'Nothing planned');
        }
        DE_TeamManagerService.setManagers(f.team.Id, new List<Id>{ UserInfo.getUserId() });
        DE_AdminController.saveShiftPlanner(f.team.Id, new List<DE_ShiftPlannerService.Change>{ change(f.members[0].Id, current, day.Id) });
        Assert.areEqual(1, DE_AdminController.getShiftPlanner(f.team.Id).rows.size(), 'Managers plan their team');

        DE_TestFactory.grantAll();
        DE_AdminController.setShiftPlannerEnabled(f.team.Id, true);
        Assert.isTrue(DE_AdminController.getShiftPlanner(f.team.Id).enabled, 'System managers switch it on');
        try {
            DE_AdminController.saveShiftPlanner(f.team.Id, new List<DE_ShiftPlannerService.Change>{ change(f.members[0].Id, current.addDays(7 * 20), day.Id) });
            Assert.fail('Beyond the horizon');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('12 weeks'), e.getMessage());
        }
    }

    @IsTest
    static void shiftsUsedByThePlannerCannotBeDeleted() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Shift__c day = shift('Day', ALWAYS);
        DE_ShiftPlannerService.applyChanges(
            f.team.Id,
            new List<DE_ShiftPlannerService.Change>{ change(f.members[0].Id, DE_ShiftPlannerService.weekStart(Date.today()), day.Id) }
        );
        DE_TestFactory.grantAll();
        try {
            DE_AvailabilityController.deleteShift(day.Id);
            Assert.fail('The shift is planned');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('shift planner'), e.getMessage());
        }
    }
}
