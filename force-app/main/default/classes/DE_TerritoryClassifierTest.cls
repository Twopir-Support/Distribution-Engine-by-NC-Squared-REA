@IsTest
private class DE_TerritoryClassifierTest {
    private static DE_Territory__c territory(String name, Integer priority, String countries, String states, String postals) {
        return new DE_Territory__c(
            Name = name,
            Object_API_Name__c = 'Lead',
            Status__c = 'Active',
            Priority__c = priority,
            Countries__c = countries,
            States__c = states,
            Postal_Codes__c = postals
        );
    }

    private static Lead lead(String name) {
        return new Lead(LastName = name, Company = name + ' Co');
    }

    /** Inserts without the engine trigger so the test controls when classification runs. */
    private static void insertQuietly(List<SObject> records) {
        DE_TriggerHandler.bypass = true;
        insert records;
        DE_TriggerHandler.bypass = false;
    }

    private static Map<Id, DE_Record_Detail__c> classify(List<Lead> leads) {
        Set<Id> ids = new Map<Id, Lead>(leads).keySet();
        DE_ClassifierService.classify('Lead', ids, new Set<String>{ 'Territory' });
        return DE_RecordDetails.load(ids, null);
    }

    private static Map<Id, Lead> reload(List<Lead> leads) {
        return new Map<Id, Lead>([SELECT Id, Title, DE_Territory__c FROM Lead WHERE Id IN :leads]);
    }

    @IsTest
    static void countryAliasesAndPriorityPickTheFirstMatchingTerritory() {
        DE_TestFactory.settings();
        insert new List<DE_Territory__c>{
            territory('EMEA', 2, 'United Kingdom;Germany;France', null, null),
            territory('UK Inbound', 1, 'United Kingdom', null, null)
        };
        Lead uk = lead('Uk');
        uk.Country = 'UK';
        Lead germany = lead('Germany');
        germany.Country = 'germany';
        Lead brazil = lead('Brazil');
        brazil.Country = 'Brazil';
        List<Lead> leads = new List<Lead>{ uk, germany, brazil };
        insertQuietly(leads);

        Test.startTest();
        Map<Id, DE_Record_Detail__c> details = classify(leads);
        Test.stopTest();

        Assert.areEqual('UK Inbound', details.get(uk.Id).Territory_Name__c, 'Lower priority number wins when several territories match');
        Assert.areEqual('EMEA', details.get(germany.Id).Territory_Name__c, 'Germany only matches EMEA');
        Assert.isNull(details.get(brazil.Id).Territory_Name__c, 'Brazil matches no territory');
        Assert.isNull(details.get(brazil.Id).Territory__c, 'No territory lookup without a match');
        Assert.areEqual('Done', details.get(uk.Id).Classifier_Status__c, 'Classification finishes');
        Map<Id, Lead> after = reload(leads);
        Assert.areEqual('UK Inbound', after.get(uk.Id).DE_Territory__c, 'Territory name stamped on the record');
        Assert.isNull(after.get(brazil.Id).DE_Territory__c, 'Unmatched record has no territory');
    }

    @IsTest
    static void countryFallsBackToPhoneThenEmailDomain() {
        DE_TestFactory.settings();
        insert new List<DE_Territory__c>{ territory('DACH', 1, 'Germany', null, null), territory('UK', 2, 'United Kingdom', null, null) };
        Lead byPhone = lead('Phone');
        byPhone.Phone = '+44 20 7946 0000';
        Lead byEmail = lead('Email');
        byEmail.Email = 'max@firma.de';
        Lead unknown = lead('Unknown');
        unknown.Email = 'someone@example.com';
        List<Lead> leads = new List<Lead>{ byPhone, byEmail, unknown };
        insertQuietly(leads);

        Map<Id, DE_Record_Detail__c> details = classify(leads);

        Assert.areEqual('UK', details.get(byPhone.Id).Territory_Name__c, 'Dial code +44 resolves to United Kingdom');
        Assert.areEqual('DACH', details.get(byEmail.Id).Territory_Name__c, '.de email domain resolves to Germany');
        Assert.isNull(details.get(unknown.Id).Territory_Name__c, 'A .com domain gives no country');
    }

    @IsTest
    static void locateInfersUnitedStatesFromState() {
        DE_TerritoryClassifier.Location l = DE_TerritoryClassifier.locate('Lead', new Lead(State = 'California'));
        Assert.areEqual('United States', l.country, 'A US state name implies the United States');
        Assert.areEqual('California', l.state, 'State kept as entered');

        DE_TerritoryClassifier.Location none = DE_TerritoryClassifier.locate('Lead', new Lead(State = 'Bavaria'));
        Assert.isNull(none.country, 'A non-US region does not imply a country');

        DE_TerritoryClassifier.Location other = DE_TerritoryClassifier.locate('DE_Team__c', new DE_Team__c());
        Assert.isNull(other.country, 'Objects without location fields have no location');
    }

    @IsTest
    static void statesAndPostalCodesNarrowTheMatch() {
        DE_TestFactory.settings();
        insert new List<DE_Territory__c>{ territory('West', 1, 'United States', 'CA;WA', null), territory('NY Metro', 2, null, null, '100*;10200..10299') };
        Lead california = lead('California');
        california.Country = 'USA';
        california.State = 'California';
        Lead manhattan = lead('Manhattan');
        manhattan.Country = 'US';
        manhattan.State = 'NY';
        manhattan.PostalCode = '10012';
        Lead jersey = lead('Jersey');
        jersey.Country = 'US';
        jersey.State = 'NJ';
        jersey.PostalCode = '10250';
        Lead nevada = lead('Nevada');
        nevada.Country = 'US';
        nevada.State = 'NV';
        nevada.PostalCode = '89101';
        List<Lead> leads = new List<Lead>{ california, manhattan, jersey, nevada };
        insertQuietly(leads);

        Map<Id, DE_Record_Detail__c> details = classify(leads);

        Assert.areEqual('West', details.get(california.Id).Territory_Name__c, 'State name matches the state code list');
        Assert.areEqual('NY Metro', details.get(manhattan.Id).Territory_Name__c, 'Postal prefix match');
        Assert.areEqual('NY Metro', details.get(jersey.Id).Territory_Name__c, 'Postal range match');
        Assert.isNull(details.get(nevada.Id).Territory_Name__c, 'Neither the state nor the postal code matches');
    }

    @IsTest
    static void extraConditionsDraftTerritoriesAndCustomStampField() {
        DE_TestFactory.settings();
        DE_Territory__c web = territory('Web UK', 1, 'United Kingdom', null, null);
        web.Condition_Logic__c = '1 OR 2';
        web.Stamp_Field__c = 'Title';
        DE_Territory__c draft = territory('Draft UK', 0, 'United Kingdom', null, null);
        draft.Status__c = 'Draft';
        DE_Territory__c other = territory('Other UK', 5, 'United Kingdom', null, null);
        insert new List<DE_Territory__c>{ web, draft, other };
        DE_Condition__c c1 = DE_TestFactory.condition('Territory', 1, 'LeadSource', 'equals', 'Web');
        c1.Territory__c = web.Id;
        DE_Condition__c c2 = DE_TestFactory.condition('Territory', 2, 'LeadSource', 'equals', 'Partner Referral');
        c2.Territory__c = web.Id;
        insert new List<DE_Condition__c>{ c1, c2 };

        Lead fromWeb = lead('Web');
        fromWeb.Country = 'United Kingdom';
        fromWeb.LeadSource = 'Web';
        Lead fromPhone = lead('Phone');
        fromPhone.Country = 'United Kingdom';
        fromPhone.LeadSource = 'Phone Inquiry';
        List<Lead> leads = new List<Lead>{ fromWeb, fromPhone };
        insertQuietly(leads);

        Map<Id, DE_Record_Detail__c> details = classify(leads);

        Assert.areEqual('Web UK', details.get(fromWeb.Id).Territory_Name__c, 'Territory conditions pass');
        Assert.areEqual(web.Id, details.get(fromWeb.Id).Territory__c, 'Territory lookup set');
        Assert.areEqual('Other UK', details.get(fromPhone.Id).Territory_Name__c, 'Failing conditions fall through; drafts are ignored');
        Map<Id, Lead> after = reload(leads);
        Assert.areEqual('Web UK', after.get(fromWeb.Id).Title, 'Territory stamp field overrides the default field');
        Assert.isNull(after.get(fromWeb.Id).DE_Territory__c, 'Default field not written when a stamp field is set');
        Assert.areEqual('Other UK', after.get(fromPhone.Id).DE_Territory__c, 'Default territory field written');
    }

    @IsTest
    static void reclassificationClearsAStaleTerritory() {
        DE_TestFactory.settings();
        insert territory('UK', 1, 'United Kingdom', null, null);
        Lead l = lead('Mover');
        l.Country = 'United Kingdom';
        insertQuietly(new List<Lead>{ l });
        Assert.areEqual('UK', classify(new List<Lead>{ l }).get(l.Id).Territory_Name__c, 'Initially in the UK territory');

        l.Country = 'Japan';
        DE_TriggerHandler.bypass = true;
        update l;
        DE_TriggerHandler.bypass = false;
        Map<Id, DE_Record_Detail__c> details = classify(new List<Lead>{ l });

        Assert.isNull(details.get(l.Id).Territory_Name__c, 'Territory cleared when nothing matches any more');
        Assert.isNull(reload(new List<Lead>{ l }).get(l.Id).DE_Territory__c, 'Record field cleared too');
    }

    @IsTest
    static void territoryIsAvailableAsAConditionPath() {
        DE_TestFactory.settings();
        insert territory('UK', 1, 'United Kingdom', null, null);
        Lead l = lead('Path');
        l.Country = 'GB';
        insertQuietly(new List<Lead>{ l });
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.details = classify(new List<Lead>{ l });

        Assert.areEqual('UK', DE_Conditions.resolve(l, 'DE.Territory', ctx), 'DE.Territory resolves from the record details');
        DE_Condition__c c = DE_TestFactory.condition('Distributor Filter', 1, 'DE.Territory', 'equals', 'uk');
        Assert.isTrue(DE_Conditions.matches(l, new List<DE_Condition__c>{ c }, null, ctx, null), 'Case-insensitive comparison on the territory');
    }

    @IsTest
    static void bulkClassificationOf200Records() {
        DE_TestFactory.settings();
        insert new List<DE_Territory__c>{ territory('UK', 1, 'United Kingdom', null, null), territory('France', 2, 'France', null, null) };
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 200; i++) {
            Lead l = lead('Bulk ' + i);
            l.Country = Math.mod(i, 2) == 0 ? 'UK' : 'FR';
            leads.add(l);
        }
        insertQuietly(leads);

        Test.startTest();
        Map<Id, DE_Record_Detail__c> details = classify(leads);
        Test.stopTest();

        Integer uk = 0;
        Integer fr = 0;
        for (DE_Record_Detail__c d : details.values()) {
            if (d.Territory_Name__c == 'UK') {
                uk++;
            } else if (d.Territory_Name__c == 'France') {
                fr++;
            }
        }
        Assert.areEqual(200, details.size(), 'Every record gets details');
        Assert.areEqual(100, uk, 'Half are UK');
        Assert.areEqual(100, fr, 'Half are France');
    }
}
