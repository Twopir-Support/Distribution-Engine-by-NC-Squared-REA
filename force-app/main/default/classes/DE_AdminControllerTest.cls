@IsTest
private class DE_AdminControllerTest {
    private static DE_AdminController.DistributorInput input(DE_Distributor__c d) {
        DE_AdminController.DistributorInput i = new DE_AdminController.DistributorInput();
        i.distributor = d;
        i.filters = new List<DE_Condition__c>();
        i.memberFilters = new List<DE_Condition__c>();
        i.lookupWhere = new List<DE_Condition__c>();
        i.caps = new List<DE_AdminController.CapInput>();
        return i;
    }

    private static DE_AdminController.CapInput capInput(String period, Decimal cap) {
        DE_AdminController.CapInput c = new DE_AdminController.CapInput();
        c.cap = new DE_Cap__c(Period__c = period, Default_Cap__c = cap, Active__c = true);
        c.criteria = new List<DE_Condition__c>();
        return c;
    }

    private static DE_AdminController.SlaInput slaInput(Integer checkpoint, Decimal minutes) {
        DE_AdminController.SlaInput s = new DE_AdminController.SlaInput();
        s.sla = new DE_SLA__c(Checkpoint__c = checkpoint, Alert_Type__c = 'Time Checkpoint', Minutes_After_Assignment__c = minutes, Active__c = true);
        s.conditions = new List<DE_Condition__c>();
        return s;
    }

    @IsTest
    static void deniesUsersWithoutPermission() {
        DE_TestFactory.grant(new Set<String>());
        try {
            DE_AdminController.getTeams();
            Assert.fail('Users without a Distribution Engine permission must not see teams.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('view distribution teams'), 'Message names the denied action: ' + e.getMessage());
        }
        try {
            DE_AdminController.saveTeam(DE_TestFactory.team('Blocked', 'Lead'), null, null);
            Assert.fail('Saving a team requires System Manager.');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(0, [SELECT COUNT() FROM DE_Team__c], 'No team is created when access is denied.');
        }
    }

    @IsTest
    static void teamManagerCannotEditTeamSettings() {
        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });
        try {
            DE_AdminController.setTeamActive(DE_TestFactory.insertTeam('Sales', 'Lead').Id, false);
            Assert.fail('Team managers cannot activate or deactivate teams.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isNotNull(e.getMessage(), 'An access error is raised.');
        }
    }

    @IsTest
    static void savesNewTeamInactiveWithFilters() {
        DE_TestFactory.settings();
        DE_TestFactory.grantAll();
        DE_Team__c t = new DE_Team__c(Name = 'Web Leads', Object_API_Name__c = 'lead', Active__c = true);
        List<DE_Condition__c> filters = new List<DE_Condition__c>{ new DE_Condition__c(Field_API_Name__c = 'LeadSource', Operator__c = 'equals', Value__c = 'Web') };

        Test.startTest();
        Id teamId = DE_AdminController.saveTeam(t, filters, null);
        Test.stopTest();

        DE_Team__c saved = [SELECT Active__c, Object_API_Name__c, Execution_Order__c FROM DE_Team__c WHERE Id = :teamId];
        Assert.isFalse(saved.Active__c, 'New teams start inactive.');
        Assert.areEqual('Lead', saved.Object_API_Name__c, 'Object name is normalised to its API name.');
        Assert.areEqual(10, saved.Execution_Order__c, 'First team gets execution order 10.');
        List<DE_Condition__c> conds = [SELECT Purpose__c, Sequence__c FROM DE_Condition__c WHERE Team__c = :teamId];
        Assert.areEqual(1, conds.size(), 'The team filter is saved.');
        Assert.areEqual('Team Filter', conds[0].Purpose__c, 'Purpose is set by the controller.');
        Assert.areEqual(1, conds[0].Sequence__c, 'Rows are numbered from 1.');
    }

    @IsTest
    static void rejectsInvalidTeam() {
        DE_TestFactory.grantAll();
        try {
            DE_AdminController.saveTeam(new DE_Team__c(Name = '', Object_API_Name__c = 'Lead'), null, null);
            Assert.fail('A team without a name is invalid.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Enter a team name.'), e.getMessage());
        }
        try {
            DE_AdminController.saveTeam(new DE_Team__c(Name = 'X', Object_API_Name__c = 'Not_An_Object__c'), null, null);
            Assert.fail('Unknown objects are rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Choose an object'), e.getMessage());
        }
        DE_Team__c existing = DE_TestFactory.insertTeam('Leads', 'Lead');
        try {
            DE_AdminController.saveTeam(new DE_Team__c(Id = existing.Id, Name = 'Leads', Object_API_Name__c = 'Case'), null, null);
            Assert.fail('The object of an existing team cannot change.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('cannot be changed'), e.getMessage());
        }
        try {
            DE_AdminController.saveTeam(new DE_Team__c(Name = 'Weights', Object_API_Name__c = 'Lead', Tag_Weights__c = 'Language:French=9'), null, null);
            Assert.fail('Tag weights outside 0.25 to 4 are rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('between 0.25 and 4'), e.getMessage());
        }
    }

    @IsTest
    static void activatesAndReordersTeams() {
        DE_TestFactory.grantAll();
        DE_Team__c a = DE_TestFactory.insertTeam('A', 'Lead');
        DE_Team__c b = DE_TestFactory.insertTeam('B', 'Lead');

        DE_AdminController.setTeamActive(a.Id, false);
        DE_AdminController.saveTeamOrder(new List<Id>{ b.Id, a.Id });

        Map<Id, DE_Team__c> teams = new Map<Id, DE_Team__c>([SELECT Active__c, Execution_Order__c FROM DE_Team__c]);
        Assert.isFalse(teams.get(a.Id).Active__c, 'Team A was deactivated.');
        Assert.areEqual(10, teams.get(b.Id).Execution_Order__c, 'B runs first.');
        Assert.areEqual(20, teams.get(a.Id).Execution_Order__c, 'A runs second.');
    }

    @IsTest
    static void returnsTeamListAndDetail() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_TestFactory.grantAll();

        Test.startTest();
        List<DE_AdminController.TeamRow> rows = DE_AdminController.getTeams();
        DE_AdminController.TeamDetail detail = DE_AdminController.getTeamDetail(f.team.Id);
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'One team exists.');
        Assert.areEqual(2, rows[0].members, 'Both members are active.');
        Assert.areEqual(1, rows[0].activeDistributors, 'The fixture distributor is active.');
        Assert.areEqual(2, detail.members.size(), 'Detail lists both members.');
        Assert.areEqual(1, detail.distributors.size(), 'Detail lists the distributor.');
        Assert.isTrue(detail.canEdit, 'System managers can edit.');
        Assert.isTrue(detail.ownerNames.containsKey(f.queue.Id), 'The source queue name is resolved.');
        Assert.areEqual(0, detail.members[0].today, 'No assignments yet today.');
    }

    @IsTest
    static void clonesAndDeletesTeam() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        insert DE_TestFactory.condition('Team Filter', 1, 'LeadSource', 'equals', 'Web');
        DE_Condition__c filter = DE_TestFactory.condition('Distributor Filter', 1, 'Company', 'is not blank', null);
        filter.Distributor__c = f.distributor.Id;
        insert filter;
        insert new DE_Cap__c(Name = 'Daily', Team__c = f.team.Id, Period__c = 'Daily', Default_Cap__c = 5, Active__c = true);
        insert new DE_SLA__c(Name = 'First', Team__c = f.team.Id, Checkpoint__c = 1, Minutes_After_Assignment__c = 30, Active__c = true);
        DE_TestFactory.grantAll();

        Test.startTest();
        Id cloneId = DE_AdminController.cloneTeam(f.team.Id);
        Test.stopTest();

        DE_Team__c clone = [SELECT Name, Active__c, Total_Assignments__c FROM DE_Team__c WHERE Id = :cloneId];
        Assert.areEqual('Inbound Sales (copy)', clone.Name, 'Clone is named after the source.');
        Assert.isFalse(clone.Active__c, 'Clones start inactive.');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :cloneId], 'Members are cloned.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Distributor__c WHERE Team__c = :cloneId AND Active__c = FALSE], 'Distributor is cloned inactive.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Cap__c WHERE Team__c = :cloneId], 'Team cap is cloned.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_SLA__c WHERE Team__c = :cloneId], 'SLA is cloned.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Condition__c WHERE Distributor__r.Team__c = :cloneId], 'Distributor filter is cloned.');

        DE_AdminController.deleteTeam(cloneId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Team__c WHERE Id = :cloneId], 'Clone deleted.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Cap__c WHERE Team__c = :cloneId], 'Team caps deleted with the team.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Team__c], 'The original team remains.');
    }

    @IsTest
    static void managesMembers() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        List<User> extra = DE_TestFactory.users(1);
        DE_TestFactory.grantAll();

        DE_AdminController.addMembers(f.team.Id, new List<Id>{ extra[0].Id });
        DE_Team_Member__c added = [SELECT Id, Active__c, Weight__c, Member_Hours__c, Unique_Key__c FROM DE_Team_Member__c WHERE User__c = :extra[0].Id];
        Assert.areEqual(f.team.Id + '|' + extra[0].Id, added.Unique_Key__c, 'Unique key prevents duplicates.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Agent__c WHERE User__c = :extra[0].Id], 'An availability row is created for the new member.');

        DE_AdminController.addMembers(f.team.Id, new List<Id>{ extra[0].Id });
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :f.team.Id], 'Adding again does not duplicate.');

        added.Weight__c = 2;
        DE_AdminController.saveMembers(new List<DE_Team_Member__c>{ added });
        Assert.areEqual(2, [SELECT Weight__c FROM DE_Team_Member__c WHERE Id = :added.Id].Weight__c, 'Weight saved.');

        DE_AdminController.removeMember(added.Id);
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :f.team.Id], 'Member removed.');

        try {
            DE_AdminController.addMembers(f.team.Id, new List<Id>{ f.queue.Id });
            Assert.fail('Queues cannot join a standard team.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Only users'), e.getMessage());
        }
    }

    @IsTest
    static void teamManagerManagesOnlyOwnTeams() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_Team__c other = DE_TestFactory.insertTeam('Other', 'Lead');
        f.team.Manager_User_Ids__c = UserInfo.getUserId();
        update f.team;
        List<User> extra = DE_TestFactory.users(1);
        DE_TestFactory.grant(new Set<String>{ 'DE_Team_Manager' });

        DE_AdminController.addMembers(f.team.Id, new List<Id>{ extra[0].Id });
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :f.team.Id], 'Managers can add members to their team.');
        try {
            DE_AdminController.addMembers(other.Id, new List<Id>{ extra[0].Id });
            Assert.fail('Managers cannot change teams they do not manage.');
        } catch (DE_Permissions.AccessException e) {
            Assert.areEqual(0, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :other.Id], 'No member added.');
        }
    }

    @IsTest
    static void savesValidatesAndManagesDistributors() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_TestFactory.grantAll();
        DE_Distributor__c d = DE_TestFactory.distributor(f.team.Id, 'Overflow', f.queue.Id, 'Load Balancing');
        d.Order__c = null;
        DE_AdminController.DistributorInput i = input(d);
        i.filters.add(new DE_Condition__c(Field_API_Name__c = 'Company', Operator__c = 'is not blank'));
        i.caps.add(capInput('Daily', 10));

        Test.startTest();
        Id distId = DE_AdminController.saveDistributor(i);
        Test.stopTest();

        DE_Distributor__c saved = [SELECT Active__c, Order__c FROM DE_Distributor__c WHERE Id = :distId];
        Assert.isFalse(saved.Active__c, 'New distributors start inactive.');
        Assert.areEqual(20, saved.Order__c, 'Order follows the existing distributor.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Condition__c WHERE Distributor__c = :distId AND Purpose__c = 'Distributor Filter'], 'Filter saved.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Cap__c WHERE Distributor__c = :distId], 'Distributor cap saved.');

        DE_AdminController.setDistributorActive(distId, true);
        DE_AdminController.saveDistributorOrder(new List<Id>{ distId, f.distributor.Id });
        Assert.areEqual(10, [SELECT Order__c FROM DE_Distributor__c WHERE Id = :distId].Order__c, 'Reordered first.');
        Assert.isTrue([SELECT Active__c FROM DE_Distributor__c WHERE Id = :distId].Active__c, 'Activated.');

        Id copyId = DE_AdminController.cloneDistributor(distId);
        Assert.areEqual('Overflow (copy)', [SELECT Name FROM DE_Distributor__c WHERE Id = :copyId].Name, 'Clone named after source.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Cap__c WHERE Distributor__c = :copyId], 'Cap cloned with the distributor.');

        DE_AdminController.deleteDistributor(copyId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Distributor__c WHERE Id = :copyId], 'Distributor deleted.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Cap__c WHERE Distributor__c = :copyId], 'Its caps are deleted.');
    }

    @IsTest
    static void rejectsInvalidDistributor() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.grantAll();
        DE_Distributor__c d = DE_TestFactory.distributor(f.team.Id, 'Bad', f.queue.Id, 'Lookup Owner');
        d.Type__c = 'Pull';
        d.Pull_Count__c = 500;
        try {
            DE_AdminController.saveDistributor(input(d));
            Assert.fail('Invalid distributors are rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Lookup Owner is not available for Pull distributors.'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('between 1 and 100'), e.getMessage());
        }
        DE_Distributor__c userSource = DE_TestFactory.distributor(f.team.Id, 'Holding', null, 'Round Robin');
        userSource.Source_Type__c = 'User';
        userSource.Source_Id__c = f.users[0].Id;
        try {
            DE_AdminController.saveDistributor(input(userSource));
            Assert.fail('A team member cannot be the holding user.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('cannot also be a member'), e.getMessage());
        }
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Distributor__c], 'Nothing new is saved.');
    }

    @IsTest
    static void savesTeamCapsAndSlas() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.grantAll();

        DE_AdminController.saveTeamCaps(f.team.Id, new List<DE_AdminController.CapInput>{ capInput('Daily', 20), capInput('Weekly', 80) });
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Cap__c WHERE Team__c = :f.team.Id], 'Two caps saved.');
        DE_AdminController.saveTeamCaps(f.team.Id, new List<DE_AdminController.CapInput>{ capInput('Monthly', 300) });
        Assert.areEqual('Monthly', [SELECT Period__c FROM DE_Cap__c WHERE Team__c = :f.team.Id].Period__c, 'Saving replaces existing caps.');

        try {
            DE_AdminController.saveTeamCaps(
                f.team.Id,
                new List<DE_AdminController.CapInput>{ capInput('Daily', 1), capInput('Weekly', 1), capInput('Monthly', 1), capInput('Hourly', 1) }
            );
            Assert.fail('At most three caps.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('at most three cap periods'), e.getMessage());
        }
        DE_AdminController.CapInput badCustom = capInput('Custom Minutes', 1);
        badCustom.cap.Custom_Length__c = 2;
        try {
            DE_AdminController.saveTeamCaps(f.team.Id, new List<DE_AdminController.CapInput>{ badCustom });
            Assert.fail('Custom minute caps need 5 to 180 minutes.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('between 5 and 180'), e.getMessage());
        }

        DE_AdminController.saveSlas(f.team.Id, new List<DE_AdminController.SlaInput>{ slaInput(1, 30), slaInput(2, 60) });
        List<DE_SLA__c> slas = [SELECT Name, Checkpoint__c FROM DE_SLA__c WHERE Team__c = :f.team.Id ORDER BY Checkpoint__c];
        Assert.areEqual(2, slas.size(), 'Two SLAs saved.');
        Assert.areEqual('SLA 1', slas[0].Name, 'Unnamed SLAs are named after the checkpoint.');
        try {
            DE_AdminController.saveSlas(f.team.Id, new List<DE_AdminController.SlaInput>{ slaInput(1, 60), slaInput(2, 30) });
            Assert.fail('SLA checkpoints must be chronological.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('chronological'), e.getMessage());
        }
        Assert.areEqual(2, [SELECT COUNT() FROM DE_SLA__c WHERE Team__c = :f.team.Id], 'Invalid save leaves SLAs unchanged.');
    }

    @IsTest
    static void describeHelpersAndViewer() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(1, 'Round Robin');
        DE_TestFactory.grantAll();

        Boolean hasLead = false;
        for (DE_Ui.Option o : DE_AdminController.getObjectOptions()) {
            hasLead = hasLead || o.value == 'Lead';
        }
        Assert.isTrue(hasLead, 'Lead is a routable object.');

        Boolean hasTerritory = false;
        for (DE_Ui.Option o : DE_AdminController.getFieldOptions('Lead', true)) {
            hasTerritory = hasTerritory || o.value == 'DE.Territory';
        }
        Assert.isTrue(hasTerritory, 'Classifier paths are offered.');
        try {
            DE_AdminController.getFieldOptions('Nope__c', false);
            Assert.fail('Unknown objects are rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('does not exist'), e.getMessage());
        }

        List<DE_Ui.Option> owners = DE_AdminController.searchOwners('DE Lead', 'Queue', 'Lead');
        Assert.areEqual(1, owners.size(), 'The Lead queue is found.');
        Assert.areEqual('Queue', owners[0].kind, 'Result kind is Queue.');
        Assert.areEqual(0, DE_AdminController.searchOwners('DE Lead', 'Queue', 'Case').size(), 'Queues that do not support Case are excluded.');
        Assert.isFalse(DE_AdminController.getTimezoneOptions().isEmpty(), 'Time zones are listed.');
        Assert.isTrue(DE_AdminController.getOwnerNames(new List<Id>{ f.users[0].Id }).containsKey(f.users[0].Id), 'Owner names resolve users.');

        List<DE_AdminController.ViewerNode> nodes = DE_AdminController.getDistributionViewer();
        Assert.areEqual(1, nodes.size(), 'One distributor in the viewer.');
        Assert.areEqual('Inbound Sales', nodes[0].teamName, 'Viewer shows the team.');
        Assert.areEqual(f.queue.Name + ' (queue)', nodes[0].source, 'Viewer shows the source queue.');
        Assert.areEqual(1, nodes[0].members, 'Viewer counts active members.');
    }
}
