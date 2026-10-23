@IsTest
private class DE_LeadConversionTest {
    private static void insertQuietly(List<SObject> records) {
        DE_TriggerHandler.bypass = true;
        insert records;
        DE_TriggerHandler.bypass = false;
    }

    private static DE_Matching_Rule__c accountRule() {
        return new DE_Matching_Rule__c(
            Name = 'Accounts',
            Match_Type__c = 'Lead to Account',
            Priority__c = 1,
            Active__c = true,
            Match_Email_Domain__c = true,
            Match_Company_Name__c = false
        );
    }

    private static DE_Conversion_Rule__c conversionRule(String name, Integer order, String match, String action) {
        return new DE_Conversion_Rule__c(
            Name = name,
            Order__c = order,
            Match__c = match,
            Action__c = action,
            Active__c = true,
            Create_Opportunity__c = 'Never',
            Owner_Source__c = 'Matched Record Owner'
        );
    }

    private static DE_Record_Detail__c classify(Lead l) {
        DE_ClassifierService.classify('Lead', new Set<Id>{ l.Id }, new Set<String>{ 'Match', 'Conversion' });
        return DE_RecordDetails.load(new Set<Id>{ l.Id }, null).get(l.Id);
    }

    private static Lead reload(Id leadId) {
        return [SELECT Id, IsConverted, ConvertedAccountId, ConvertedContactId, ConvertedOpportunityId, OwnerId FROM Lead WHERE Id = :leadId];
    }

    @IsTest
    static void matchApplies() {
        DE_Record_Detail__c none = new DE_Record_Detail__c();
        DE_Record_Detail__c accountOnly = new DE_Record_Detail__c(Matched_Account__c = fakeId(Account.SObjectType));
        DE_Record_Detail__c both = new DE_Record_Detail__c(Matched_Account__c = fakeId(Account.SObjectType), Matched_Contact__c = fakeId(Contact.SObjectType));
        DE_Record_Detail__c leadOnly = new DE_Record_Detail__c(Matched_Lead__c = fakeId(Lead.SObjectType));

        Assert.isTrue(DE_LeadConversion.matchApplies('No Match', none), 'No match');
        Assert.isFalse(DE_LeadConversion.matchApplies('No Match', accountOnly), 'Account matched');
        Assert.isTrue(DE_LeadConversion.matchApplies('Account Only Match', accountOnly), 'Account only');
        Assert.isFalse(DE_LeadConversion.matchApplies('Account Only Match', both), 'Contact also matched');
        Assert.isTrue(DE_LeadConversion.matchApplies('Account and Contact Match', both), 'Both matched');
        Assert.isFalse(DE_LeadConversion.matchApplies('Account and Contact Match', accountOnly), 'Contact missing');
        Assert.isTrue(DE_LeadConversion.matchApplies('Lead Only Match', leadOnly), 'Lead only');
        Assert.isFalse(DE_LeadConversion.matchApplies('Lead Only Match', none), 'No lead match');
        Assert.isTrue(DE_LeadConversion.matchApplies(null, none), 'Blank match means any');
        Assert.isTrue(DE_LeadConversion.matchApplies('Any', both), 'Any');
    }

    private static Id fakeId(Schema.SObjectType t) {
        return Id.valueOf(t.getDescribe().getKeyPrefix() + '000000000001');
    }

    @IsTest
    static void autoConvertsIntoTheMatchedAccount() {
        DE_TestFactory.settings();
        insert accountRule();
        DE_Conversion_Rule__c r = conversionRule('Known accounts', 1, 'Account Only Match', 'Auto Convert');
        r.Account_Field_Update__c = 'Description=Converted by Distribution Engine';
        insert r;
        Account a = new Account(Name = 'Acme', Website = 'acme.com');
        insert a;
        Lead l = new Lead(LastName = 'Buyer', Company = 'Acme', Email = 'buyer@acme.com');
        insertQuietly(new List<Lead>{ l });

        Test.startTest();
        DE_Record_Detail__c d = classify(l);
        Test.stopTest();

        Lead after = reload(l.Id);
        Assert.isTrue(after.IsConverted, 'Lead converted: ' + d.Conversion_Result__c);
        Assert.areEqual(a.Id, after.ConvertedAccountId, 'Converted into the matched account');
        Assert.isNull(after.ConvertedOpportunityId, 'Create Opportunity = Never');
        Assert.areEqual('Converted (rule Known accounts)', d.Conversion_Result__c, 'Result recorded on the details');
        Assert.areEqual('Converted by Distribution Engine', [SELECT Description FROM Account WHERE Id = :a.Id].Description, 'Account field update applied');
    }

    @IsTest
    static void alwaysCreatesAnOpportunityWhenAsked() {
        DE_TestFactory.settings();
        insert accountRule();
        DE_Conversion_Rule__c r = conversionRule('With opportunity', 1, 'Account Only Match', 'Auto Convert');
        r.Create_Opportunity__c = 'Always';
        insert r;
        insert new Account(Name = 'Globex', Website = 'globex.com');
        Lead l = new Lead(LastName = 'Buyer', Company = 'Globex', Email = 'buyer@globex.com');
        insertQuietly(new List<Lead>{ l });

        classify(l);

        Assert.isNotNull(reload(l.Id).ConvertedOpportunityId, 'Opportunity created');
    }

    @IsTest
    static void doNotConvertRuleStopsEvaluationBeforeTheDefault() {
        DE_TestFactory.settings();
        insert accountRule();
        DE_Conversion_Rule__c hold = conversionRule('Hold unknowns', 1, 'No Match', 'Do Not Convert');
        DE_Conversion_Rule__c fallback = conversionRule('Default', 1, 'Any', 'Auto Convert');
        fallback.Is_Default__c = true;
        insert new List<DE_Conversion_Rule__c>{ fallback, hold };
        Lead l = new Lead(LastName = 'Stranger', Company = 'Nobody Inc', Email = 'x@nobody-known.com');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = classify(l);

        Assert.isFalse(reload(l.Id).IsConverted, 'Do Not Convert rule wins over the default rule');
        Assert.areEqual('Not converted (rule Hold unknowns)', d.Conversion_Result__c, 'Result names the rule');
    }

    @IsTest
    static void conversionFiltersAndRetainedQueueOwner() {
        DE_TestFactory.settings();
        Group q = DE_TestFactory.queue('Conversion Queue', new List<String>{ 'Lead' });
        DE_Conversion_Rule__c r = conversionRule('Web leads', 1, 'Any', 'Auto Convert');
        r.Owner_Source__c = 'Retain Lead Owner';
        insert r;
        DE_Condition__c c = DE_TestFactory.condition('Conversion Filter', 1, 'LeadSource', 'equals', 'Web');
        c.Conversion_Rule__c = r.Id;
        insert c;
        Lead web = new Lead(LastName = 'Web', Company = 'Web Co', LeadSource = 'Web', OwnerId = q.Id);
        Lead phone = new Lead(LastName = 'Phone', Company = 'Phone Co', LeadSource = 'Phone Inquiry');
        insertQuietly(new List<Lead>{ web, phone });

        DE_ClassifierService.classify('Lead', new Set<Id>{ web.Id, phone.Id }, new Set<String>{ 'Conversion' });
        Map<Id, DE_Record_Detail__c> details = DE_RecordDetails.load(new Set<Id>{ web.Id, phone.Id }, null);

        Lead webAfter = reload(web.Id);
        Assert.isTrue(webAfter.IsConverted, 'Lead passing the conversion filter converts: ' + details.get(web.Id).Conversion_Result__c);
        Assert.isNotNull(webAfter.ConvertedAccountId, 'New account created without a match');
        Assert.areEqual(
            UserInfo.getUserId(),
            [SELECT OwnerId FROM Account WHERE Id = :webAfter.ConvertedAccountId].OwnerId,
            'Queue-owned leads convert to the running user'
        );
        Assert.isFalse(reload(phone.Id).IsConverted, 'Lead failing the filter is not converted');
        Assert.isNull(details.get(phone.Id).Conversion_Result__c, 'No rule applied');
    }

    @IsTest
    static void conversionFailureIsRecorded() {
        DE_TestFactory.settings();
        DE_Conversion_Rule__c r = conversionRule('Bad status', 1, 'Any', 'Auto Convert');
        r.Converted_Status__c = 'Not A Real Status';
        insert r;
        Lead l = new Lead(LastName = 'Failure', Company = 'Failure Co');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = classify(l);

        Assert.isFalse(reload(l.Id).IsConverted, 'Conversion failed');
        Assert.isTrue(d.Conversion_Result__c.startsWith('Failed: '), 'Failure recorded: ' + d.Conversion_Result__c);
        Assert.areEqual('Done', d.Classifier_Status__c, 'Classification still completes');
    }

    @IsTest
    static void deDuplicateMergesIntoTheExistingLead() {
        DE_TestFactory.settings();
        insert new DE_Matching_Rule__c(Name = 'Duplicates', Match_Type__c = 'Lead to Lead', Priority__c = 1, Active__c = true, Match_Email__c = true);
        DE_Conversion_Rule__c r = conversionRule('Merge duplicates', 1, 'Lead Only Match', 'De-Duplicate');
        r.Copy_Blank_Fields__c = true;
        r.Survivor_Field_Update__c = 'Rating=Hot';
        insert r;
        Lead survivor = new Lead(LastName = 'Original', Company = 'Dup Co', Email = 'dup@dupco.com');
        insertQuietly(new List<Lead>{ survivor });
        Lead incoming = new Lead(LastName = 'Copy', Company = 'Dup Co', Email = 'dup@dupco.com', Phone = '+1 555 0100');
        insertQuietly(new List<Lead>{ incoming });

        DE_Record_Detail__c d = classify(incoming);

        Lead merged = [SELECT Id, Phone, Rating FROM Lead WHERE Id = :survivor.Id];
        Assert.areEqual('+1 555 0100', merged.Phone, 'Blank survivor fields copied from the duplicate');
        Assert.areEqual('Hot', merged.Rating, 'Survivor field update applied');
        Assert.areEqual(0, [SELECT COUNT() FROM Lead WHERE Id = :incoming.Id], 'Duplicate merged away');
        Assert.areEqual(survivor.Id, d.Matched_Lead__c, 'Matched lead recorded');
        Assert.isTrue(d.Conversion_Result__c.startsWith('De-duplicated into ' + survivor.Id), 'Result: ' + d.Conversion_Result__c);
    }

    @IsTest
    static void deDuplicateWithoutALeadMatchDoesNothing() {
        DE_TestFactory.settings();
        DE_Conversion_Rule__c r = conversionRule('Merge duplicates', 1, 'Any', 'De-Duplicate');
        insert r;
        Lead l = new Lead(LastName = 'Alone', Company = 'Alone Co', Email = 'alone@alone.com');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = classify(l);

        Assert.areEqual(1, [SELECT COUNT() FROM Lead WHERE Id = :l.Id], 'Lead kept');
        Assert.areEqual('Not converted (rule Merge duplicates)', d.Conversion_Result__c, 'No merge without a matched lead');
    }

    @IsTest
    static void convertedLeadsAreSkipped() {
        Lead converted = (Lead) JSON.deserialize('{"attributes":{"type":"Lead"},"Id":"' + fakeId(Lead.SObjectType) + '","IsConverted":true}', Lead.class);
        Map<Id, DE_Record_Detail__c> details = new Map<Id, DE_Record_Detail__c>();
        DE_LeadConversion.run(new List<SObject>{ converted }, details, new List<DE_Conversion_Rule__c>{ conversionRule('Any', 1, 'Any', 'Auto Convert') });
        Assert.isTrue(details.isEmpty(), 'Already converted leads are not evaluated');

        DE_LeadConversion.run(new List<SObject>{ converted }, details, new List<DE_Conversion_Rule__c>());
        Assert.isTrue(details.isEmpty(), 'No rules, no work');
    }

    @IsTest
    static void requiredPathsIncludeFilterFields() {
        DE_TestFactory.settings();
        DE_Conversion_Rule__c r = conversionRule('Filtered', 1, 'Any', 'Auto Convert');
        insert r;
        DE_Condition__c c = DE_TestFactory.condition('Conversion Filter', 1, 'Industry', 'equals', 'Banking');
        c.Conversion_Rule__c = r.Id;
        insert c;
        Set<String> paths = DE_LeadConversion.requiredPaths(DE_LeadConversion.rules());
        Assert.isTrue(paths.contains('Industry'), 'Filter field queried');
        Assert.isTrue(paths.contains('IsConverted'), 'Conversion state queried');
    }
}
