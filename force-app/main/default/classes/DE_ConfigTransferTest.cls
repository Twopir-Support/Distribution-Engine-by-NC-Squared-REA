@IsTest
private class DE_ConfigTransferTest {
    @IsTest
    static void exportThenImportRoundTrip() {
        DE_TestFactory.Fixture f = DE_TestFactory.leadFixture(2, 'Round Robin');
        DE_Shift__c shift = new DE_Shift__c(Name = 'UK Day', Timezone__c = 'Europe/London', Schedule__c = '{"MON":["09:00-17:00"]}');
        insert shift;
        f.team.Team_Hours__c = shift.Id;
        f.team.Manager_User_Ids__c = f.users[0].Id;
        update f.team;
        DE_Condition__c teamFilter = DE_TestFactory.condition('Team Filter', 1, 'LeadSource', 'equals', 'Web');
        teamFilter.Team__c = f.team.Id;
        insert teamFilter;
        DE_Cap__c cap = new DE_Cap__c(Name = 'Daily', Distributor__c = f.distributor.Id, Period__c = 'Daily', Default_Cap__c = 5, Active__c = true);
        insert cap;
        insert new DE_SLA__c(Name = 'First', Team__c = f.team.Id, Checkpoint__c = 1, Minutes_After_Assignment__c = 30, Active__c = true);
        insert new DE_Territory__c(Name = 'West', Object_API_Name__c = 'Lead', Priority__c = 10, Status__c = 'Active');
        DE_Stamp_Group__c g = new DE_Stamp_Group__c(Name = 'Tier', Object_API_Name__c = 'Lead');
        insert g;
        insert new DE_Stamp__c(Name = 'Gold', Order__c = 1, Stamp_Group__c = g.Id);

        Test.startTest();
        String json = DE_ConfigTransfer.exportJson();
        Map<String, Integer> counts = DE_ConfigTransfer.importJson(json);
        Test.stopTest();

        Map<String, Object> root = (Map<String, Object>) System.JSON.deserializeUntyped(json);
        Assert.areEqual('distribution-engine-by-nc-squared', root.get('format'), 'Format marker present.');
        Assert.isFalse(json.contains(String.valueOf(f.queue.Id)), 'Queue Ids are replaced by portable names.');
        Assert.isTrue(json.contains('queue:' + f.queue.DeveloperName), 'Queues are exported by developer name.');
        Assert.isTrue(json.contains('shift:UK Day'), 'Shifts are exported by name.');

        Assert.areEqual(1, counts.get('teams'), 'One team imported.');
        Assert.areEqual(0, counts.get('shifts'), 'The existing shift is reused.');
        Assert.areEqual(1, counts.get('territories'), 'Territory imported.');
        Assert.areEqual(1, counts.get('stampGroups'), 'Stamp group imported.');
        Assert.areEqual(0, counts.get('unresolvedReferences'), 'Every reference resolves in the same org.');

        DE_Team__c imported = [SELECT Id, Active__c, Team_Hours__c, Manager_User_Ids__c FROM DE_Team__c WHERE Name = 'Inbound Sales (imported)'];
        Assert.isFalse(imported.Active__c, 'Imported teams are inactive.');
        Assert.areEqual(shift.Id, imported.Team_Hours__c, 'Shift reference resolved.');
        Assert.areEqual(String.valueOf(f.users[0].Id), imported.Manager_User_Ids__c, 'Manager resolved by username.');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :imported.Id], 'Members imported.');
        DE_Distributor__c d = [SELECT Id, Source_Id__c FROM DE_Distributor__c WHERE Team__c = :imported.Id];
        Assert.areEqual(String.valueOf(f.queue.Id), d.Source_Id__c, 'Source queue resolved.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Cap__c WHERE Distributor__c = :d.Id], 'Distributor cap imported.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_SLA__c WHERE Team__c = :imported.Id], 'SLA imported.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Condition__c WHERE Team__c = :imported.Id], 'Team filter imported.');
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Territory__c WHERE Name = 'West' AND Status__c = 'Draft'], 'Imported territories are drafts.');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Stamp__c], 'Stamp imported.');
    }

    @IsTest
    static void rejectsForeignOrInvalidFiles() {
        try {
            DE_ConfigTransfer.importJson('not json');
            Assert.fail('Invalid JSON.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('not valid'), e.getMessage());
        }
        try {
            DE_ConfigTransfer.importJson('{"format":"something-else"}');
            Assert.fail('Foreign files are rejected.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('not exported from Distribution Engine'), e.getMessage());
        }
    }

    @IsTest
    static void countsUnresolvedReferences() {
        DE_TestFactory.settings();
        String json =
            '{"format":"distribution-engine-by-nc-squared","version":1,"teams":[{"Name":"Remote","Object_API_Name__c":"Lead",' +
            '"members":[{"User__c":"user:nobody@missing.example.com","Active__c":true,"Weight__c":1}],' +
            '"distributors":[{"Name":"Inbound","Type__c":"Standard","Method__c":"Round Robin","Source_Type__c":"Queue","Source_Id__c":"queue:Missing_Queue"}]}]}';

        Map<String, Integer> counts = DE_ConfigTransfer.importJson(json);

        Assert.areEqual(1, counts.get('teams'), 'Team imported.');
        Assert.areEqual(2, counts.get('unresolvedReferences'), 'Missing user and queue are reported.');
        DE_Team__c t = [SELECT Id, Active__c FROM DE_Team__c WHERE Name = 'Remote'];
        Assert.isFalse(t.Active__c, 'Inactive.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Team_Member__c WHERE Team__c = :t.Id], 'Unresolved members are skipped.');
        Assert.isNull([SELECT Source_Id__c FROM DE_Distributor__c WHERE Team__c = :t.Id].Source_Id__c, 'Unresolved source left blank.');
    }
}
