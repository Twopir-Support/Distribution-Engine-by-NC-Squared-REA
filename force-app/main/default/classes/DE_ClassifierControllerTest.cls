@IsTest
private class DE_ClassifierControllerTest {
    @IsTest
    static void onlyAdminsConfigureTheClassifier() {
        DE_TestFactory.grant(new Set<String>{ 'DE_System_Manager' });
        try {
            DE_ClassifierController.getTerritories('Lead');
            Assert.fail('System managers cannot configure the classifier.');
        } catch (DE_Permissions.AccessException e) {
            Assert.isTrue(e.getMessage().contains('configure the classifier'), e.getMessage());
        }
    }

    @IsTest
    static void managesTerritories() {
        DE_TestFactory.grantAll();
        Id west = DE_ClassifierController.saveTerritory(
            new DE_Territory__c(Name = 'West', Object_API_Name__c = 'lead', Priority__c = 10, Countries__c = 'US', States__c = 'CA;OR;WA'),
            new List<DE_Condition__c>{ new DE_Condition__c(Field_API_Name__c = 'Country', Operator__c = 'equals', Value__c = 'US') }
        );
        DE_Territory__c saved = [SELECT Status__c, Object_API_Name__c FROM DE_Territory__c WHERE Id = :west];
        Assert.areEqual('Draft', saved.Status__c, 'New territories are drafts.');
        Assert.areEqual('Lead', saved.Object_API_Name__c, 'Object name normalised.');

        Integer imported = DE_ClassifierController.importTerritories('Lead', null, 'East,US,NY;NJ\n\nNorth\tCA,,');
        Assert.areEqual(2, imported, 'Blank lines are skipped.');
        List<DE_ClassifierController.ConditionalRecord> rows = DE_ClassifierController.getTerritories('Lead');
        Assert.areEqual(3, rows.size(), 'Three territories.');
        Assert.areEqual(1, rows[0].conditions.size(), 'West keeps its condition.');
        DE_Territory__c east = [SELECT Priority__c, States__c FROM DE_Territory__c WHERE Name = 'East'];
        Assert.areEqual(20, east.Priority__c, 'Imported territories follow the highest order.');
        Assert.areEqual('NY;NJ', east.States__c, 'States column imported.');

        Assert.areEqual(3, DE_ClassifierController.setMapStatus('Lead', null, 'Active'), 'Default map activated.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Territory__c WHERE Status__c != 'Active'], 'All active.');

        Id north = [SELECT Id FROM DE_Territory__c WHERE Name = 'North'].Id;
        DE_ClassifierController.reorderTerritories(new List<Id>{ north, west });
        Assert.areEqual(10, [SELECT Priority__c FROM DE_Territory__c WHERE Id = :north].Priority__c, 'North first.');

        DE_ClassifierController.deleteTerritory(west);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Condition__c], 'Territory conditions deleted.');
        Assert.areEqual(2, [SELECT COUNT() FROM DE_Territory__c], 'Territory deleted.');
    }

    @IsTest
    static void rejectsInvalidTerritory() {
        DE_TestFactory.grantAll();
        try {
            DE_ClassifierController.saveTerritory(new DE_Territory__c(Name = '', Object_API_Name__c = 'Lead', Stamp_Field__c = 'NumberOfEmployees'), null);
            Assert.fail('Invalid territory.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Enter a territory name.'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('Enter the territory order.'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('updateable text field'), e.getMessage());
        }
        try {
            DE_ClassifierController.importTerritories('Lead', null, ',US');
            Assert.fail('Lines need a name.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Line 1 has no territory name.'), e.getMessage());
        }
    }

    @IsTest
    static void managesMatchingRules() {
        DE_TestFactory.grantAll();
        Id ruleId = DE_ClassifierController.saveMatchingRule(
            new DE_Matching_Rule__c(Name = 'Domain to account', Priority__c = 1, Match_Type__c = 'Lead to Account', Fuzzy_Threshold__c = 90),
            new List<DE_Condition__c>{ new DE_Condition__c(Field_API_Name__c = 'Type', Operator__c = 'not equals', Value__c = 'Partner') }
        );
        List<DE_ClassifierController.ConditionalRecord> rules = DE_ClassifierController.getMatchingRules();
        Assert.areEqual(1, rules.size(), 'Rule listed.');
        Assert.areEqual(1, rules[0].conditions.size(), 'Match filter saved.');
        try {
            DE_ClassifierController.saveMatchingRule(
                new DE_Matching_Rule__c(Name = 'Bad', Priority__c = 2, Match_Type__c = 'Lead to Contact', Fuzzy_Threshold__c = 20, Target_Field__c = 'Nope__c'),
                null
            );
            Assert.fail('Invalid rule.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('between 50 and 100'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('does not exist on Contact'), e.getMessage());
        }
        DE_ClassifierController.deleteMatchingRule(ruleId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Matching_Rule__c], 'Rule deleted.');
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Condition__c], 'Its filter deleted.');
    }

    @IsTest
    static void managesConversionRules() {
        DE_TestFactory.grantAll();
        LeadStatus converted = [SELECT ApiName FROM LeadStatus WHERE IsConverted = TRUE LIMIT 1];
        Id first = DE_ClassifierController.saveConversionRule(
            new DE_Conversion_Rule__c(
                Name = 'Default',
                Order__c = 1,
                Is_Default__c = true,
                Action__c = 'Auto Convert',
                Match__c = 'Any',
                Converted_Status__c = converted.ApiName
            ),
            null
        );
        Id second = DE_ClassifierController.saveConversionRule(
            new DE_Conversion_Rule__c(Name = 'New default', Order__c = 2, Is_Default__c = true, Action__c = 'Do Not Convert', Match__c = 'No Match'),
            new List<DE_Condition__c>{ new DE_Condition__c(Field_API_Name__c = 'LeadSource', Operator__c = 'equals', Value__c = 'Web') }
        );
        Assert.isFalse([SELECT Is_Default__c FROM DE_Conversion_Rule__c WHERE Id = :first].Is_Default__c, 'Only one default rule.');
        Assert.isTrue([SELECT Is_Default__c FROM DE_Conversion_Rule__c WHERE Id = :second].Is_Default__c, 'The newest default wins.');
        Assert.areEqual(2, DE_ClassifierController.getConversionRules().size(), 'Both listed.');

        try {
            DE_ClassifierController.saveConversionRule(
                new DE_Conversion_Rule__c(
                    Name = 'Bad',
                    Order__c = 3,
                    Action__c = 'De-Duplicate',
                    Match__c = 'Any',
                    Owner_Source__c = 'Default User',
                    Converted_Status__c = 'Not A Status',
                    Account_Field_Update__c = 'Nope__c=1'
                ),
                null
            );
            Assert.fail('Invalid conversion rule.');
        } catch (AuraHandledException e) {
            String m = e.getMessage();
            Assert.isTrue(m.contains('De-Duplicate is only available'), m);
            Assert.isTrue(m.contains('Choose the default user.'), m);
            Assert.isTrue(m.contains('is not a converted lead status'), m);
            Assert.isTrue(m.contains('Account field update'), m);
        }
        DE_ClassifierController.deleteConversionRule(second);
        Assert.areEqual(1, [SELECT COUNT() FROM DE_Conversion_Rule__c], 'Rule deleted.');
    }

    @IsTest
    static void managesStampGroups() {
        DE_TestFactory.grantAll();
        Id groupId = DE_ClassifierController.saveStampGroup(new DE_Stamp_Group__c(Name = 'Tier', Object_API_Name__c = 'Lead', Group_Type__c = 'Single'));
        Id stampId = DE_ClassifierController.saveStamp(
            new DE_Stamp__c(Name = 'Enterprise', Order__c = 1, Stamp_Group__c = groupId),
            new List<DE_Condition__c>{ new DE_Condition__c(Field_API_Name__c = 'NumberOfEmployees', Operator__c = 'greater than', Value__c = '1000') }
        );
        List<DE_ClassifierController.StampGroupDetail> groups = DE_ClassifierController.getStampGroups('Lead');
        Assert.areEqual(1, groups.size(), 'Group listed.');
        Assert.areEqual(1, groups[0].stamps.size(), 'Stamp listed.');
        Assert.areEqual(1, groups[0].stamps[0].conditions.size(), 'Stamp condition listed.');

        try {
            DE_ClassifierController.saveStamp(
                new DE_Stamp__c(Name = 'Bad', Order__c = 2, Stamp_Group__c = groupId),
                new List<DE_Condition__c>{ new DE_Condition__c(Field_API_Name__c = 'NumberOfEmployees', Operator__c = 'greater than', Value__c = 'many') }
            );
            Assert.fail('Numeric fields need numbers.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('is not a number'), e.getMessage());
        }
        try {
            DE_ClassifierController.saveStampGroup(new DE_Stamp_Group__c(Name = 'X', Object_API_Name__c = 'Lead', Stamp_Field__c = 'Nope__c'));
            Assert.fail('Stamp field must exist.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Nope__c does not exist'), e.getMessage());
        }

        DE_ClassifierController.deleteStamp(stampId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Stamp__c], 'Stamp deleted.');
        DE_ClassifierController.deleteStampGroup(groupId);
        Assert.areEqual(0, [SELECT COUNT() FROM DE_Stamp_Group__c], 'Group deleted.');
    }

    @IsTest
    static void runsBackfillAndClassifiesRecord() {
        DE_TestFactory.settings();
        Lead l = DE_TestFactory.insertLeads(1, UserInfo.getUserId())[0];
        DE_TestFactory.grantAll();
        try {
            DE_ClassifierController.runBackfill('Nope__c', null, null, false);
            Assert.fail('Unknown objects are rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Choose an object.'), e.getMessage());
        }
        Test.startTest();
        Id jobId = DE_ClassifierController.runBackfill('Lead', new List<String>{ 'Territory' }, Date.today().addDays(-1), false);
        Integer classified = DE_ClassifierController.classifyRecord(l.Id);
        Test.stopTest();
        Assert.isNotNull(jobId, 'Backfill batch started.');
        Assert.isNotNull(classified, 'Classification returns a count.');
    }
}
