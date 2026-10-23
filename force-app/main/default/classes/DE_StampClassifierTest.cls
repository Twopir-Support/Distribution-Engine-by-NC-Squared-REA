@IsTest
private class DE_StampClassifierTest {
    private static void insertQuietly(List<SObject> records) {
        DE_TriggerHandler.bypass = true;
        insert records;
        DE_TriggerHandler.bypass = false;
    }

    private static DE_Stamp_Group__c stampGroup(String name, String groupType, String stampField) {
        return new DE_Stamp_Group__c(Name = name, Object_API_Name__c = 'Lead', Group_Type__c = groupType, Stamp_Field__c = stampField, Active__c = true);
    }

    private static DE_Stamp__c stamp(Id groupId, String name, Integer order) {
        return new DE_Stamp__c(Stamp_Group__c = groupId, Name = name, Order__c = order);
    }

    private static DE_Condition__c stampCondition(Id stampId, Integer seq, String field, String operator, String value) {
        DE_Condition__c c = DE_TestFactory.condition('Stamp', seq, field, operator, value);
        c.Stamp__c = stampId;
        return c;
    }

    /** Tier (Single): Gold, Silver, Standard. Interest (Multiple): Web, Enterprise. */
    private static void configure() {
        DE_Stamp_Group__c tier = stampGroup('Tier', 'Single', 'Title');
        DE_Stamp_Group__c interest = stampGroup('Interest', 'Multiple', 'Description');
        DE_Stamp_Group__c inactive = stampGroup('Retired', 'Single', null);
        inactive.Active__c = false;
        insert new List<DE_Stamp_Group__c>{ tier, interest, inactive };
        DE_Stamp__c gold = stamp(tier.Id, 'Gold', 1);
        DE_Stamp__c silver = stamp(tier.Id, 'Silver', 2);
        DE_Stamp__c standard = stamp(tier.Id, 'Standard', 3);
        DE_Stamp__c web = stamp(interest.Id, 'Web', 1);
        DE_Stamp__c enterprise = stamp(interest.Id, 'Enterprise', 2);
        DE_Stamp__c retired = stamp(inactive.Id, 'Anything', 1);
        insert new List<DE_Stamp__c>{ gold, silver, standard, web, enterprise, retired };
        insert new List<DE_Condition__c>{
            stampCondition(gold.Id, 1, 'AnnualRevenue', 'greater or equal', '1000000'),
            stampCondition(silver.Id, 1, 'AnnualRevenue', 'greater or equal', '100000'),
            stampCondition(web.Id, 1, 'LeadSource', 'equals', 'Web'),
            stampCondition(enterprise.Id, 1, 'NumberOfEmployees', 'greater than', '1000')
        };
    }

    private static Map<Id, DE_Record_Detail__c> classify(List<Lead> leads, Set<String> types) {
        Set<Id> ids = new Map<Id, Lead>(leads).keySet();
        DE_ClassifierService.classify('Lead', ids, types);
        return DE_RecordDetails.load(ids, null);
    }

    @IsTest
    static void singleGroupsTakeTheFirstStampAndMultipleGroupsTakeAll() {
        DE_TestFactory.settings();
        configure();
        Lead big = new Lead(LastName = 'Big', Company = 'Big Co', AnnualRevenue = 2000000, LeadSource = 'Web', NumberOfEmployees = 5000);
        Lead mid = new Lead(LastName = 'Mid', Company = 'Mid Co', AnnualRevenue = 250000, LeadSource = 'Phone Inquiry', NumberOfEmployees = 10);
        Lead small = new Lead(LastName = 'Small', Company = 'Small Co', AnnualRevenue = 5000, LeadSource = 'Phone Inquiry', NumberOfEmployees = 2);
        List<Lead> leads = new List<Lead>{ big, mid, small };
        insertQuietly(leads);

        Test.startTest();
        Map<Id, DE_Record_Detail__c> details = classify(leads, new Set<String>{ 'Stamps' });
        Test.stopTest();

        Assert.areEqual('Interest:Web;Interest:Enterprise;Tier:Gold', details.get(big.Id).Stamps__c, 'Groups in name order, stamps in stamp order');
        Assert.areEqual('Tier:Silver', details.get(mid.Id).Stamps__c, 'Single group stops at the first matching stamp');
        Assert.areEqual('Tier:Standard', details.get(small.Id).Stamps__c, 'A stamp without conditions always matches');

        Map<Id, Lead> after = new Map<Id, Lead>([SELECT Id, Title, Description FROM Lead WHERE Id IN :leads]);
        Assert.areEqual('Gold', after.get(big.Id).Title, 'Single group written to its stamp field');
        Assert.areEqual('Web;Enterprise', after.get(big.Id).Description, 'Multiple group written as a semicolon list');
        Assert.isNull(after.get(small.Id).Description, 'No matching stamp clears the field');
    }

    @IsTest
    static void stampPathsResolvePerGroup() {
        DE_TestFactory.settings();
        configure();
        Lead big = new Lead(LastName = 'Big', Company = 'Big Co', AnnualRevenue = 2000000, LeadSource = 'Web', NumberOfEmployees = 5000);
        insertQuietly(new List<Lead>{ big });
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.details = classify(new List<Lead>{ big }, new Set<String>{ 'Stamps' });

        Assert.areEqual('Web;Enterprise', DE_Conditions.resolve(big, 'DE.Stamp.Interest', ctx), 'DE.Stamp.<Group> returns the group stamps');
        Assert.areEqual('Gold', DE_Conditions.resolve(big, 'DE.Stamp.tier', ctx), 'Group name is case-insensitive');
        Assert.isNull(DE_Conditions.resolve(big, 'DE.Stamp.Retired', ctx), 'Inactive groups are not applied');
        Assert.areEqual('Gold', DE_Conditions.stampsInGroup('Tier:Gold;Interest:Web', 'Tier'), 'stampsInGroup extracts one group');
        Assert.isNull(DE_Conditions.stampsInGroup(null, 'Tier'), 'No stamps');
    }

    @IsTest
    static void stampsCanUseTheTerritoryClassifiedInTheSameRun() {
        DE_TestFactory.settings();
        insert new DE_Territory__c(Name = 'UK', Object_API_Name__c = 'Lead', Status__c = 'Active', Priority__c = 1, Countries__c = 'United Kingdom');
        DE_Stamp_Group__c region = stampGroup('Region', 'Single', null);
        insert region;
        DE_Stamp__c domestic = stamp(region.Id, 'Domestic', 1);
        DE_Stamp__c international = stamp(region.Id, 'International', 2);
        insert new List<DE_Stamp__c>{ domestic, international };
        insert stampCondition(domestic.Id, 1, 'DE.Territory', 'equals', 'UK');

        Lead home = new Lead(LastName = 'Home', Company = 'Home Co', Country = 'UK');
        Lead away = new Lead(LastName = 'Away', Company = 'Away Co', Country = 'Japan');
        insertQuietly(new List<Lead>{ home, away });

        Map<Id, DE_Record_Detail__c> details = classify(new List<Lead>{ home, away }, null);

        Assert.areEqual('Region:Domestic', details.get(home.Id).Stamps__c, 'Territory is available to stamp conditions');
        Assert.areEqual('Region:International', details.get(away.Id).Stamps__c, 'Falls through to the next stamp');
    }

    @IsTest
    static void groupsForOtherObjectsAreIgnored() {
        DE_TestFactory.settings();
        DE_Stamp_Group__c caseGroup = new DE_Stamp_Group__c(Name = 'Case Group', Object_API_Name__c = 'Case', Group_Type__c = 'Single', Active__c = true);
        insert caseGroup;
        insert stamp(caseGroup.Id, 'Any', 1);

        Assert.isTrue(DE_StampClassifier.groups('Lead').isEmpty(), 'No Lead groups');
        Assert.areEqual(1, DE_StampClassifier.groups('Case').size(), 'One Case group');
        Assert.isTrue(DE_StampClassifier.requiredPaths(DE_StampClassifier.groups('Case')).isEmpty(), 'No conditions, no paths');

        Lead l = new Lead(LastName = 'Plain', Company = 'Plain Co');
        insertQuietly(new List<Lead>{ l });
        Assert.isNull(classify(new List<Lead>{ l }, new Set<String>{ 'Stamps' }).get(l.Id).Stamps__c, 'Lead not stamped by a Case group');
    }
}
