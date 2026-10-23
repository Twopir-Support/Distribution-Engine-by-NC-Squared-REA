@IsTest
private class DE_ConditionsTest {
    private static final Datetime NOW = Datetime.newInstanceGmt(2024, 6, 12, 12, 0, 0);

    private static Id fakeId(Schema.SObjectType t, Integer n) {
        return Id.valueOf(t.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0'));
    }

    private static Boolean cmp(Object actual, String op, String expected) {
        return DE_Conditions.compare(actual, op, expected, NOW);
    }

    @IsTest
    static void textOperators() {
        Assert.isTrue(cmp('Web', 'equals', 'web'), 'equals ignores case');
        Assert.isTrue(cmp('Web', null, 'WEB'), 'blank operator defaults to equals');
        Assert.isTrue(cmp(null, 'equals', ''), 'equals blank matches null');
        Assert.isTrue(cmp('x', 'not equals', ''), 'not equals blank matches a value');
        Assert.isTrue(cmp('Phone', 'in', 'Web;Phone'), 'in matches one of the values');
        Assert.isTrue(cmp('Phone', 'in', 'Web\tphone'), 'tab is a list separator');
        Assert.isTrue(cmp('Email', 'not in', 'Web;Phone'), 'not in');
        Assert.isTrue(cmp('Acme Corp', 'contains', 'zzz;corp'), 'contains any value');
        Assert.isTrue(cmp('Acme Corp', 'does not contain', 'zzz'), 'does not contain');
        Assert.isTrue(cmp('Acme Corp', 'starts with', 'ACM'), 'starts with');
        Assert.isTrue(cmp('Acme Corp', 'does not start with', 'corp'), 'does not start with');
        Assert.isTrue(cmp('Acme Corp', 'ends with', 'corp'), 'ends with');
        Assert.isTrue(cmp('Acme Corp', 'does not end with', 'acme'), 'does not end with');
        Assert.isFalse(cmp(null, 'contains', 'a'), 'contains on null is false');
        Assert.isTrue(cmp(null, 'is blank', null), 'is blank on null');
        Assert.isTrue(cmp('  ', 'is blank', null), 'whitespace counts as blank');
        Assert.isTrue(cmp('a', 'is not blank', null), 'is not blank');
        Assert.isTrue(cmp('apple', 'less than', 'banana'), 'text compares alphabetically');
        Assert.isTrue(cmp('10', 'greater than', '9'), 'numeric text compares as numbers');
    }

    @IsTest
    static void multiSelectOperators() {
        Assert.isTrue(cmp('A;B;C', 'includes', 'b;z'), 'includes any');
        Assert.isFalse(cmp('A;B;C', 'includes', 'z'), 'includes none');
        Assert.isTrue(cmp('A;B;C', 'includes all', 'a;b'), 'includes all');
        Assert.isFalse(cmp('A;B;C', 'includes all', 'a;z'), 'includes all with a missing value');
        Assert.isFalse(cmp('A;B', 'includes all', ''), 'includes all needs values');
        Assert.isTrue(cmp('A;B', 'does not include', 'z'), 'does not include');
        Assert.isTrue(cmp(null, 'does not include', 'z'), 'does not include on null');
        Assert.isTrue(cmp('A;B', 'equals', 'b;a'), 'multi-select equals compares the set');
        Assert.isFalse(cmp('A;B', 'equals', 'a'), 'multi-select equals needs the same set');
    }

    @IsTest
    static void numberBooleanAndIdOperators() {
        Assert.isTrue(cmp(5, 'greater than', '3'), 'greater than');
        Assert.isTrue(cmp(5.0, 'less or equal', '5'), 'less or equal');
        Assert.isTrue(cmp(5, 'greater or equal', '5'), 'greater or equal');
        Assert.isFalse(cmp(5, 'less than', 'abc'), 'non-numeric expected value never matches');
        Assert.isFalse(cmp(null, 'greater than', '1'), 'blank never compares');
        Assert.isTrue(cmp(5, 'equals', '5.00'), 'numeric equals');
        Assert.isTrue(cmp(5, 'between', '1..10'), 'between');
        Assert.isFalse(cmp(11, 'between', '1..10'), 'outside between');
        Assert.isFalse(cmp(5, 'between', '1-10'), 'between needs ..');
        Assert.isTrue(cmp(true, 'equals', 'TRUE'), 'boolean true');
        Assert.isTrue(cmp(false, 'equals', 'no'), 'boolean false');
        Assert.isTrue(cmp(true, 'equals', '1'), 'boolean 1');
        Id u = UserInfo.getUserId();
        Assert.isTrue(cmp(u, 'equals', String.valueOf(u).left(15)), '15 and 18 character Ids are equal');
        Assert.isFalse(cmp(u, 'equals', 'not an id'), 'invalid Id never matches');
    }

    @IsTest
    static void dateAndDatetimeOperators() {
        Assert.isTrue(cmp(NOW.addDays(-3), 'less than', '2 days ago'), 'datetime relative ago');
        Assert.isTrue(cmp(NOW.addHours(1), 'greater than', 'NOW'), 'datetime NOW');
        Assert.isTrue(cmp(NOW, 'between', '1 hour ago..1 hour from now'), 'datetime between relative values');
        Assert.isTrue(cmp(NOW.date(), 'equals', 'TODAY'), 'date TODAY');
        Assert.isTrue(cmp(NOW.date().addDays(-10), 'less than', '1 week ago'), 'date relative weeks');
        Assert.isTrue(cmp(Date.newInstance(2024, 3, 5), 'between', '2024-01-01..2024-12-31'), 'date between ISO dates');
        Assert.isTrue(cmp(Date.newInstance(2024, 3, 5), 'equals', '2024-03-05'), 'date equals ISO');
        Assert.isFalse(cmp(Date.newInstance(2024, 3, 5), 'equals', 'not a date'), 'unparseable date');
        Assert.isTrue(cmp(Datetime.newInstanceGmt(2024, 1, 15, 10, 0, 0), 'equals', '2024-01-15T10:00:00Z'), 'datetime ISO');
    }

    @IsTest
    static void unknownOperatorThrows() {
        Boolean threw = false;
        try {
            cmp('a', 'sounds like', 'b');
        } catch (DE_Conditions.ConditionException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Unknown operators throw');
    }

    @IsTest
    static void parsesDateValues() {
        Assert.areEqual(NOW, DE_Conditions.parseDatetime('now', NOW), 'NOW');
        Assert.areEqual(Datetime.newInstance(NOW.date(), Time.newInstance(0, 0, 0, 0)), DE_Conditions.parseDatetime('TODAY', NOW), 'TODAY');
        Assert.areEqual(NOW.addHours(3), DE_Conditions.parseDatetime('3 hours from now', NOW), 'hours from now');
        Assert.areEqual(NOW.addMinutes(-15), DE_Conditions.parseDatetime('15 mins ago', NOW), 'minutes ago');
        Assert.areEqual(NOW.addDays(14), DE_Conditions.parseDatetime('2 weeks from now', NOW), 'weeks from now');
        Assert.areEqual(
            Datetime.newInstance(Date.newInstance(2024, 1, 15), Time.newInstance(0, 0, 0, 0)),
            DE_Conditions.parseDatetime('2024-01-15', NOW),
            'ISO date'
        );
        Assert.isNull(DE_Conditions.parseDatetime('garbage', NOW), 'garbage');
        Assert.isNull(DE_Conditions.parseDatetime(' ', NOW), 'blank');
        Assert.areEqual(NOW.date().addDays(-7), DE_Conditions.parseDate('1 week ago', NOW), 'relative date');
        Assert.areEqual(Date.newInstance(2024, 3, 5), DE_Conditions.parseDate('2024-03-05T10:00:00Z', NOW), 'date from datetime text');
        Assert.areEqual(NOW.date(), DE_Conditions.parseDate('now', NOW), 'date NOW');
        Assert.isNull(DE_Conditions.parseDate('xyz', NOW), 'bad date');
    }

    @IsTest
    static void splitsValues() {
        Assert.areEqual(new List<String>{ 'a', 'b', 'c' }, DE_Conditions.splitValues(' a ;b\t c;;'), 'semicolon and tab separated, trimmed');
        Assert.isTrue(DE_Conditions.splitValues(null).isEmpty(), 'null gives empty list');
    }

    @IsTest
    static void readsRecordPaths() {
        Contact c = new Contact(LastName = 'Smith', Account = new Account(Name = 'Acme', Industry = 'Technology'));
        Assert.areEqual('Technology', DE_Conditions.readPath(c, 'Account.Industry'), 'relationship path');
        Assert.areEqual('Smith', DE_Conditions.readPath(c, ' LastName '), 'direct field');
        Assert.isNull(DE_Conditions.readPath(new Contact(), 'Account.Industry'), 'missing parent gives null');
        Boolean threw = false;
        try {
            DE_Conditions.readPath(c, 'Not_A_Field__c');
        } catch (DE_Conditions.ConditionException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Unknown field throws a ConditionException');
        Assert.isNull(DE_Conditions.resolve(null, 'LastName', null), 'null record');
        Assert.isNull(DE_Conditions.resolve(c, '', null), 'blank path');
    }

    @IsTest
    static void resolvesClassifierDetailPaths() {
        Id leadId = fakeId(Lead.SObjectType, 1);
        Lead l = new Lead(Id = leadId, LastName = 'X');
        DE_Record_Detail__c d = new DE_Record_Detail__c(Territory_Name__c = 'EMEA', Domain__c = 'acme.com', Stamps__c = 'Tier:Gold;Region:North;Tier:Silver');
        d.putSObject('Matched_Account__r', new Account(Name = 'Acme', Industry = 'Retail'));
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.details.put(leadId, d);

        Assert.areEqual('EMEA', DE_Conditions.resolve(l, 'DE.Territory', ctx), 'territory');
        Assert.areEqual('acme.com', DE_Conditions.resolve(l, 'de.domain', ctx), 'case-insensitive key');
        Assert.areEqual('Gold;Silver', DE_Conditions.resolve(l, 'DE.Stamp.Tier', ctx), 'stamps in one group');
        Assert.areEqual('Retail', DE_Conditions.resolve(l, 'DE.MatchedAccount.Industry', ctx), 'matched account field');
        Assert.isNull(DE_Conditions.resolve(l, 'DE.MatchedContact.Email', ctx), 'no matched contact');
        Assert.isNull(DE_Conditions.resolve(l, 'DE.Unknown', ctx), 'unknown key');
        Assert.isNull(DE_Conditions.resolveDetail(d, 'DE'), 'too short');
        Assert.isNull(DE_Conditions.resolveDetail(null, 'DE.Territory'), 'no detail');
        Assert.isNull(DE_Conditions.resolve(l, 'DE.Territory', null), 'no context');
        Assert.isNull(DE_Conditions.resolve(new Lead(Id = fakeId(Lead.SObjectType, 2)), 'DE.Territory', ctx), 'no detail row');

        Assert.isNull(DE_Conditions.stampsInGroup('Tier:Gold', 'Region'), 'no stamps in group');
        Assert.isNull(DE_Conditions.stampsInGroup(null, 'Region'), 'no stamps at all');
    }

    @IsTest
    static void matchesWithLogicAndTrace() {
        Lead l = new Lead(LeadSource = 'Web', Rating = 'Hot', AnnualRevenue = 2000000);
        List<DE_Condition__c> conds = new List<DE_Condition__c>{
            DE_TestFactory.condition('Team Filter', 1, 'LeadSource', 'equals', 'web'),
            DE_TestFactory.condition('Team Filter', 2, 'Rating', 'equals', 'Cold'),
            DE_TestFactory.condition('Team Filter', 3, 'AnnualRevenue', 'greater than', '1000000')
        };
        List<String> trace = new List<String>();
        Assert.isTrue(DE_Conditions.matches(l, conds, '(1 OR 2) AND 3', new DE_Conditions.Context(), trace), 'custom logic');
        Assert.areEqual(4, trace.size(), 'one trace line per row plus the logic line');
        Assert.isTrue(trace[1].contains('FALSE'), 'row 2 is traced as false');
        Assert.isFalse(DE_Conditions.matches(l, conds, null, null, null), 'blank logic ANDs every row');
        Assert.isTrue(DE_Conditions.matches(l, new List<DE_Condition__c>(), '1', null, null), 'no conditions always match');
        Assert.isTrue(DE_Conditions.matches(l, null, null, null, null), 'null conditions always match');
    }

    @IsTest
    static void collectsPathsAndDetailFields() {
        List<DE_Condition__c> conds = new List<DE_Condition__c>{
            DE_TestFactory.condition('Team Filter', 1, 'Account.Industry', 'equals', 'x'),
            DE_TestFactory.condition('Team Filter', 2, 'DE.Territory', 'equals', 'x'),
            DE_TestFactory.condition('Member Filter', 3, 'Tag:Language', 'includes', 'French'),
            DE_TestFactory.condition('Team Filter', 4, 'DE.Stamp.Tier', 'includes', 'Gold'),
            DE_TestFactory.condition('Team Filter', 5, 'DE.MatchedAccount.Owner.Name', 'equals', 'x')
        };
        Assert.areEqual(new Set<String>{ 'Account.Industry' }, DE_Conditions.recordPaths(conds), 'record paths skip DE.* and member filters');
        Assert.areEqual(
            new Set<String>{ 'Territory_Name__c', 'Stamps__c', 'Matched_Account__r.Owner.Name' },
            DE_Conditions.detailFields(conds),
            'detail fields for DE.* paths'
        );
        Assert.areEqual('Matched_Account__c', DE_Conditions.detailFieldFor('DE.MatchedAccount'), 'matched record id');
        Assert.isNull(DE_Conditions.detailFieldFor('LeadSource'), 'record path is not a detail path');
        Assert.isNull(DE_Conditions.detailFieldFor('DE'), 'too short');
        Assert.isTrue(DE_Conditions.recordPaths(null).isEmpty(), 'null list');
        Assert.isTrue(DE_Conditions.detailFields(null).isEmpty(), 'null list');
    }

    @IsTest
    static void validatesConditions() {
        String ok = DE_Conditions.validate(
            'Lead',
            new List<DE_Condition__c>{
                DE_TestFactory.condition('Team Filter', 1, 'LeadSource', 'equals', 'Web'),
                DE_TestFactory.condition('Team Filter', 2, 'CreatedDate', 'greater than', '2 days ago'),
                DE_TestFactory.condition('Team Filter', 3, 'DE.Territory', 'equals', 'EMEA'),
                DE_TestFactory.condition('Member Filter', 4, 'Tag:Language', 'includes', 'French'),
                DE_TestFactory.condition('Member Filter', 5, 'DynamicTag:Language', 'includes', 'LeadSource'),
                DE_TestFactory.condition('Member Filter', 6, 'Territory', 'includes', ''),
                DE_TestFactory.condition('Team Filter', 7, 'AnnualRevenue', 'between', '1..10')
            },
            '1 AND (2 OR 3) AND 4 AND 5 AND 6 AND 7'
        );
        Assert.isNull(ok, 'Valid conditions: ' + ok);

        Assert.areEqual(
            'Every condition needs a row number.',
            validateOne(new DE_Condition__c(Field_API_Name__c = 'LeadSource', Operator__c = 'equals')),
            'row number'
        );
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'Nope__c', 'equals', 'x')).contains('does not exist on Lead'), 'bad field');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'LeadSource', 'resembles', 'x')).contains('not a valid operator'), 'bad operator');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, ' ', 'equals', 'x')).contains('choose a field'), 'blank field');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'AnnualRevenue', 'greater than', 'abc')).contains('is not a number'), 'number');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'AnnualRevenue', 'between', '5')).contains('low..high'), 'between');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'ConvertedDate', 'less than', 'soon')).contains('is not a date'), 'date');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'CreatedDate', 'less than', 'soon')).contains('is not a date/time'), 'datetime');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'LeadSource', 'includes', '')).contains('at least one value'), 'includes');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Team Filter', 1, 'DE.Unknown', 'equals', 'x')).contains('classifier field'), 'detail path');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Member Filter', 1, 'Tag:Language', 'equals', 'x')).contains('member filters use'), 'tag op');
        Assert.isTrue(validateOne(DE_TestFactory.condition('Member Filter', 1, 'Tag:Language', 'includes', '')).contains('at least one tag'), 'tag value');
        Assert.isTrue(
            validateOne(DE_TestFactory.condition('Member Filter', 1, 'DynamicTag:Language', 'includes', 'Nope__c')).contains('dynamic tags'),
            'dynamic tag'
        );
        Assert.isTrue(validateOne(DE_TestFactory.condition('Member Filter', 1, 'Stamp:Tier', 'equals', 'x')).contains('member filters use'), 'stamp op');
        Assert.isTrue(
            validateOne(DE_TestFactory.condition('Member Filter', 1, 'Skill', 'includes', 'x')).contains('Tag:<Collection>'),
            'unknown member filter'
        );

        List<DE_Condition__c> dup = new List<DE_Condition__c>{
            DE_TestFactory.condition('Team Filter', 1, 'LeadSource', 'equals', 'Web'),
            DE_TestFactory.condition('Team Filter', 1, 'Rating', 'equals', 'Hot')
        };
        Assert.areEqual('Row number 1 is used twice.', DE_Conditions.validate('Lead', dup, null), 'duplicate row');
        Assert.isTrue(DE_Conditions.validate('Lead', new List<DE_Condition__c>{ dup[0] }, '1 OR 2').contains('condition 2'), 'logic referencing a missing row');
    }

    private static String validateOne(DE_Condition__c c) {
        return DE_Conditions.validate('Lead', new List<DE_Condition__c>{ c }, null);
    }
}
