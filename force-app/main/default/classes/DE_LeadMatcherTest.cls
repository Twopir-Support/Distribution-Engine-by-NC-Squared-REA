@IsTest
private class DE_LeadMatcherTest {
    private static void insertQuietly(List<SObject> records) {
        DE_TriggerHandler.bypass = true;
        insert records;
        DE_TriggerHandler.bypass = false;
    }

    private static DE_Matching_Rule__c rule(String name, String matchType, Integer priority) {
        return new DE_Matching_Rule__c(
            Name = name,
            Match_Type__c = matchType,
            Priority__c = priority,
            Active__c = true,
            Match_Email_Domain__c = true,
            Match_Company_Name__c = true,
            Match_Email__c = true,
            Fuzzy_Threshold__c = 85
        );
    }

    private static Lead lead(String company, String email) {
        return new Lead(LastName = 'Prospect', Company = company, Email = email);
    }

    /** Runs the matcher the way the classifier does and returns the in-memory details. */
    private static Map<Id, DE_Record_Detail__c> match(List<Lead> leads) {
        List<DE_Matching_Rule__c> rules = DE_LeadMatcher.rules();
        Set<Id> ids = new Map<Id, Lead>(leads).keySet();
        List<SObject> rows = DE_RecordQuery.byIds('Lead', DE_LeadMatcher.requiredPaths(rules), ids, null);
        Map<Id, DE_Record_Detail__c> details = new Map<Id, DE_Record_Detail__c>();
        DE_LeadMatcher.match(rows, details, rules);
        return details;
    }

    @IsTest
    static void contactEmailDomainBeatsWebsiteDomain() {
        DE_TestFactory.settings();
        insert rule('Accounts', 'Lead to Account', 1);
        Account byWebsite = new Account(Name = 'Acme Holdings', Website = 'https://www.acme.com/about');
        Account byContact = new Account(Name = 'Parent Group');
        insert new List<Account>{ byWebsite, byContact };
        insert new Contact(LastName = 'Jane', AccountId = byContact.Id, Email = 'jane@acme.com');
        Lead l = lead('Something Unrelated', 'bob@ACME.com');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = match(new List<Lead>{ l }).get(l.Id);

        Assert.areEqual(byContact.Id, d.Matched_Account__c, 'Contact email domain is the strongest signal');
        Assert.areEqual('Account: Exact (contact email domain)', d.Match_Confidence__c, 'Confidence explains the match');
        Assert.areEqual('acme.com', d.Domain__c, 'Domain is lower-cased');
        Assert.isFalse(d.Personal_Email__c, 'Corporate domain');
    }

    @IsTest
    static void websiteDomainMatch() {
        DE_TestFactory.settings();
        insert rule('Accounts', 'Lead to Account', 1);
        Account globex = new Account(Name = 'Globex', Website = 'globex.io');
        insert globex;
        Lead l = lead('Different Name', 'hank@globex.io');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = match(new List<Lead>{ l }).get(l.Id);

        Assert.areEqual(globex.Id, d.Matched_Account__c, 'Website domain match');
        Assert.areEqual('Account: Exact (website domain)', d.Match_Confidence__c, 'Website confidence');
    }

    @IsTest
    static void companyNameExactAndFuzzy() {
        DE_TestFactory.settings();
        insert rule('Accounts', 'Lead to Account', 1);
        Account initech = new Account(Name = 'Initech Ltd');
        Account stark = new Account(Name = 'Stark Industries');
        insert new List<Account>{ initech, stark };
        Lead exact = lead('Initech Limited', 'peter@gmail.com');
        Lead fuzzy = lead('Stark Industriess', null);
        Lead none = lead('Wayne', null);
        insertQuietly(new List<Lead>{ exact, fuzzy, none });

        Map<Id, DE_Record_Detail__c> details = match(new List<Lead>{ exact, fuzzy, none });

        Assert.areEqual(initech.Id, details.get(exact.Id).Matched_Account__c, 'Legal suffixes ignored in the exact comparison');
        Assert.areEqual('Account: Exact (company name)', details.get(exact.Id).Match_Confidence__c, 'Exact company confidence');
        Assert.areEqual(stark.Id, details.get(fuzzy.Id).Matched_Account__c, 'Fuzzy company match above the threshold');
        Assert.isTrue(details.get(fuzzy.Id).Match_Confidence__c.startsWith('Account: Fuzzy'), 'Fuzzy confidence: ' + details.get(fuzzy.Id).Match_Confidence__c);
        Assert.isNull(details.get(none.Id).Matched_Account__c, 'No candidate for an unknown company');
    }

    @IsTest
    static void personalDomainsNeverMatchOnDomain() {
        DE_TestFactory.settings();
        DE_Matching_Rule__c r = rule('Domain only', 'Lead to Account', 1);
        r.Match_Company_Name__c = false;
        insert r;
        insert new Account(Name = 'Mail Provider', Website = 'gmail.com');
        Lead l = lead('Freelancer', 'pat@gmail.com');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = match(new List<Lead>{ l }).get(l.Id);

        Assert.isNull(d.Matched_Account__c, 'Personal email domains are excluded');
        Assert.isTrue(d.Personal_Email__c, 'Flagged as personal');
        Assert.areEqual('gmail.com', d.Domain__c, 'Domain still recorded');
    }

    @IsTest
    static void matchFiltersRestrictCandidates() {
        DE_TestFactory.settings();
        DE_Matching_Rule__c r = rule('Customers only', 'Lead to Account', 1);
        insert r;
        DE_Condition__c c = DE_TestFactory.condition('Match Filter', 1, 'Type', 'equals', 'Customer - Direct');
        c.Matching_Rule__c = r.Id;
        insert c;
        Account prospect = new Account(Name = 'Hooli Prospect', Website = 'hooli.com', Type = 'Prospect');
        Account customer = new Account(Name = 'Hooli Customer', Website = 'hooli.com', Type = 'Customer - Direct');
        insert new List<Account>{ prospect, customer };
        Lead l = lead('Hooli', 'gavin@hooli.com');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = match(new List<Lead>{ l }).get(l.Id);

        Assert.areEqual(customer.Id, d.Matched_Account__c, 'Accounts failing the match filter are not candidates');
    }

    @IsTest
    static void tieBreakerFieldAndDirection() {
        DE_TestFactory.settings();
        DE_Matching_Rule__c r = rule('Biggest', 'Lead to Account', 1);
        r.Match_Company_Name__c = false;
        r.Tie_Breaker_Field__c = 'AnnualRevenue';
        r.Tie_Breaker_Direction__c = 'Newest or Highest';
        insert r;
        Account small = new Account(Name = 'Pied Piper East', Website = 'piedpiper.com', AnnualRevenue = 1000);
        Account large = new Account(Name = 'Pied Piper West', Website = 'piedpiper.com', AnnualRevenue = 900000);
        insert new List<Account>{ small, large };
        Lead l = lead('Pied Piper', 'richard@piedpiper.com');
        insertQuietly(new List<Lead>{ l });

        Assert.areEqual(large.Id, match(new List<Lead>{ l }).get(l.Id).Matched_Account__c, 'Highest value wins the tie');

        r.Tie_Breaker_Direction__c = 'Oldest or Lowest';
        update r;
        Assert.areEqual(small.Id, match(new List<Lead>{ l }).get(l.Id).Matched_Account__c, 'Lowest value wins when reversed');
    }

    @IsTest
    static void customFieldPairMatch() {
        DE_TestFactory.settings();
        DE_Matching_Rule__c r = rule('Account number', 'Lead to Account', 1);
        r.Match_Email_Domain__c = false;
        r.Match_Company_Name__c = false;
        r.Source_Field__c = 'Title';
        r.Target_Field__c = 'AccountNumber';
        insert r;
        Account a = new Account(Name = 'Numbered', AccountNumber = 'ACC-001');
        insert a;
        Lead hit = lead('Anything', null);
        hit.Title = 'acc-001';
        Lead miss = lead('Anything Else', null);
        miss.Title = 'ACC-999';
        insertQuietly(new List<Lead>{ hit, miss });

        Map<Id, DE_Record_Detail__c> details = match(new List<Lead>{ hit, miss });

        Assert.areEqual(a.Id, details.get(hit.Id).Matched_Account__c, 'Custom field pair compared case-insensitively');
        Assert.areEqual('Account: Exact (Title)', details.get(hit.Id).Match_Confidence__c, 'Names the source field');
        Assert.isNull(details.get(miss.Id).Matched_Account__c, 'Different value does not match');
    }

    @IsTest
    static void leadToContactSetsContactAndAccount() {
        DE_TestFactory.settings();
        insert rule('Contacts', 'Lead to Contact', 1);
        Account a = new Account(Name = 'Contoso');
        insert a;
        Contact c = new Contact(LastName = 'Jo', Email = 'jo@contoso.com', AccountId = a.Id);
        insert c;
        Lead l = lead('Contoso', 'JO@contoso.com');
        insertQuietly(new List<Lead>{ l });

        DE_Record_Detail__c d = match(new List<Lead>{ l }).get(l.Id);

        Assert.areEqual(c.Id, d.Matched_Contact__c, 'Email match to a contact');
        Assert.areEqual(a.Id, d.Matched_Account__c, 'The contact account becomes the matched account');
        Assert.areEqual('Contact: Exact (email)', d.Match_Confidence__c, 'Contact confidence');
    }

    @IsTest
    static void leadToLeadFindsDuplicatesButNotItself() {
        DE_TestFactory.settings();
        insert rule('Duplicates', 'Lead to Lead', 1);
        Lead existing = lead('Dup Co', 'dup@dupco.com');
        insertQuietly(new List<Lead>{ existing });
        Lead incoming = lead('Dup Co', 'Dup@DupCo.com');
        Lead unique = lead('Unique Co', 'only@unique.com');
        insertQuietly(new List<Lead>{ incoming, unique });

        Map<Id, DE_Record_Detail__c> details = match(new List<Lead>{ incoming, unique });

        Assert.areEqual(existing.Id, details.get(incoming.Id).Matched_Lead__c, 'Existing lead with the same email');
        Assert.areEqual('Lead: Exact (email)', details.get(incoming.Id).Match_Confidence__c, 'Lead confidence');
        Assert.isNull(details.get(unique.Id).Matched_Lead__c, 'A lead never matches itself');
    }

    @IsTest
    static void firstRuleMatchIsKept() {
        DE_TestFactory.settings();
        DE_Matching_Rule__c first = rule('By website', 'Lead to Account', 1);
        first.Match_Company_Name__c = false;
        DE_Matching_Rule__c second = rule('By name', 'Lead to Account', 2);
        second.Match_Email_Domain__c = false;
        insert new List<DE_Matching_Rule__c>{ first, second };
        Account byWeb = new Account(Name = 'Vandelay', Website = 'vandelay.com');
        Account byName = new Account(Name = 'Kramerica');
        insert new List<Account>{ byWeb, byName };
        Lead l = lead('Kramerica', 'art@vandelay.com');
        insertQuietly(new List<Lead>{ l });

        Assert.areEqual(byWeb.Id, match(new List<Lead>{ l }).get(l.Id).Matched_Account__c, 'Later rules do not override an earlier match');
    }

    @IsTest
    static void matchedAccountFieldsAreAvailableAsConditionPaths() {
        DE_TestFactory.settings();
        insert rule('Accounts', 'Lead to Account', 1);
        Account a = new Account(Name = 'Soylent', Website = 'soylent.com', Type = 'Customer - Direct', Industry = 'Banking');
        insert a;
        Lead l = lead('Soylent', 'sol@soylent.com');
        insertQuietly(new List<Lead>{ l });

        DE_ClassifierService.classify('Lead', new Set<Id>{ l.Id }, new Set<String>{ 'Match' });
        Map<Id, DE_Record_Detail__c> details = DE_RecordDetails.load(
            new Set<Id>{ l.Id },
            new Set<String>{ 'Matched_Account__r.Type', 'Matched_Account__r.Industry' }
        );
        DE_Record_Detail__c d = details.get(l.Id);

        Assert.areEqual(a.Id, d.Matched_Account__c, 'Classifier persisted the match');
        Assert.areEqual('Customer - Direct', DE_Conditions.resolveDetail(d, 'DE.MatchedAccount.Type'), 'Matched account field path');
        Assert.areEqual('Banking', DE_Conditions.resolveDetail(d, 'DE.MatchedAccount.Industry'), 'Second matched account field');
        Assert.areEqual(a.Id, DE_Conditions.resolveDetail(d, 'DE.MatchedAccount'), 'Bare path returns the id');
        Assert.areEqual('soylent.com', DE_Conditions.resolveDetail(d, 'DE.Domain'), 'Domain path');
        Assert.areEqual(false, DE_Conditions.resolveDetail(d, 'DE.PersonalEmail'), 'Personal email path');
        Assert.areEqual('Account: Exact (website domain)', DE_Conditions.resolveDetail(d, 'DE.MatchConfidence'), 'Confidence path');
        Assert.areEqual('Matched_Account__r.Type', DE_Conditions.detailFieldFor('DE.MatchedAccount.Type'), 'Detail field for a matched path');
    }

    @IsTest
    static void requiredPathsIncludeTheSourceField() {
        DE_Matching_Rule__c r = rule('Custom', 'Lead to Account', 1);
        r.Source_Field__c = 'Title';
        Set<String> paths = DE_LeadMatcher.requiredPaths(new List<DE_Matching_Rule__c>{ r });
        Assert.isTrue(paths.contains('Title'), 'Source field queried');
        Assert.isTrue(paths.containsAll(DE_LeadMatcher.LEAD_FIELDS), 'Standard lead fields queried');
    }
}
