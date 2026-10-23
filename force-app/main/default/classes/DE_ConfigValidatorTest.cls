@IsTest
private class DE_ConfigValidatorTest {
    private static DE_Team__c leadTeam() {
        return new DE_Team__c(Name = 'Leads', Object_API_Name__c = 'Lead');
    }

    private static List<String> distributorErrors(DE_Distributor__c d, Set<Id> memberIds) {
        return DE_ConfigValidator.distributor(d, leadTeam(), new List<DE_Distributor__c>(), null, null, null, null, memberIds);
    }

    private static Id fakeId() {
        return Id.valueOf(DE_Distributor__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    private static Boolean has(List<String> errors, String fragment) {
        for (String e : errors) {
            if (e.contains(fragment)) {
                return true;
            }
        }
        return false;
    }

    @IsTest
    static void validTeamHasNoErrors() {
        Assert.areEqual(new List<String>(), DE_ConfigValidator.team(leadTeam(), null, false, null, null), 'A minimal Lead team is valid.');
    }

    @IsTest
    static void teamRules() {
        DE_Team__c t = new DE_Team__c(
            Name = 'Cases',
            Object_API_Name__c = 'Case',
            Assignment_Field__c = 'Subject',
            Active_Status_Field__c = 'Status',
            Balance_By__c = 'Field Value',
            Balance_Field__c = 'Subject',
            Action_Tracking_Enabled__c = true,
            Rejection_Limit__c = 'Limited',
            Rejections_Per_Day__c = -1,
            Tag_Weights__c = 'NoColon=2',
            Dynamic_Members_Enabled__c = true
        );
        List<String> errors = DE_ConfigValidator.team(t, null, false, null, null);
        Assert.isTrue(has(errors, 'must be OwnerId or a User lookup'), 'Assignment field must be a user lookup.');
        Assert.isTrue(has(errors, 'Enter at least one Active Status value.'), 'Active status values required.');
        Assert.isTrue(has(errors, 'Balance field must be a numeric field'), 'Balance field must be numeric.');
        Assert.isTrue(has(errors, 'Choose an action field'), 'Action field required.');
        Assert.isTrue(has(errors, 'Enter at least one action to track.'), 'Tracked actions required.');
        Assert.isTrue(has(errors, 'rejections allowed per day'), 'Rejection limit required.');
        Assert.isTrue(has(errors, 'Collection:Tag=Weight'), 'Tag weight syntax.');
        Assert.isTrue(has(errors, 'dynamic membership condition'), 'Dynamic membership needs conditions.');
    }

    @IsTest
    static void existingTeamRules() {
        DE_Team__c existing = new DE_Team__c(Name = 'Leads', Object_API_Name__c = 'Lead');
        DE_Team__c changed = new DE_Team__c(Name = 'Leads', Object_API_Name__c = 'Lead', Assignment_Field__c = 'OwnerId', Team_Type__c = 'Queue to Queue');
        Assert.isTrue(DE_ConfigValidator.team(changed, existing, true, null, null).isEmpty(), 'Queue to Queue on Lead owner is valid.');
        DE_Team__c q2qCase = new DE_Team__c(Name = 'X', Object_API_Name__c = 'Opportunity', Team_Type__c = 'Queue to Queue');
        Assert.isTrue(has(DE_ConfigValidator.team(q2qCase, null, false, null, null), 'owner can be a queue'), 'Opportunities cannot be owned by queues.');
        List<DE_Condition__c> badFilter = new List<DE_Condition__c>{ DE_TestFactory.condition('Team Filter', 1, 'NotAField__c', 'equals', 'x') };
        Assert.isTrue(has(DE_ConfigValidator.team(leadTeam(), null, false, badFilter, null), 'Team filters: '), 'Filter errors are prefixed.');
    }

    @IsTest
    static void weights() {
        Assert.isNull(DE_ConfigValidator.weights('Language:French=2\nTier:Gold=0.25'), 'Valid weights.');
        Assert.isNotNull(DE_ConfigValidator.weights('Language:French=5'), 'Above 4 is invalid.');
        Assert.isNotNull(DE_ConfigValidator.weights('Language:French=abc'), 'Non-numeric is invalid.');
    }

    @IsTest
    static void distributorSourceRules() {
        Group q = DE_TestFactory.queue('DE Case Only', new List<String>{ 'Case' });
        DE_Distributor__c d = new DE_Distributor__c(Name = 'D', Type__c = 'Standard', Method__c = 'Round Robin', Source_Type__c = 'Queue', Source_Id__c = q.Id);
        Assert.isTrue(has(distributorErrors(d, new Set<Id>()), 'does not support Lead records'), 'Queue must support the object.');

        d.Source_Type__c = null;
        Assert.isTrue(has(distributorErrors(d, new Set<Id>()), 'need a Queue, User or Field Value source'), 'Source type required.');

        d.Source_Type__c = 'Field Value';
        d.Source_Field__c = 'Company';
        Assert.isTrue(has(distributorErrors(d, new Set<Id>()), 'Choose a picklist source field'), 'Field value sources need a picklist.');
        Assert.isTrue(has(distributorErrors(d, new Set<Id>()), 'Enter the ready value'), 'Ready value required.');

        d.Source_Field__c = 'Status';
        d.Source_Ready_Value__c = 'Open - Not Contacted';
        Assert.isTrue(distributorErrors(d, new Set<Id>()).isEmpty(), 'A picklist field source is valid: ' + distributorErrors(d, new Set<Id>()));
    }

    @IsTest
    static void distributorMethodRules() {
        DE_Distributor__c manual = new DE_Distributor__c(Name = 'M', Type__c = 'Manual', Method__c = 'Round Robin');
        List<String> errors = DE_ConfigValidator.distributor(
            manual,
            leadTeam(),
            new List<DE_Distributor__c>{ new DE_Distributor__c(Id = fakeId(), Type__c = 'Manual') },
            null,
            null,
            null,
            null,
            new Set<Id>()
        );
        Assert.isTrue(has(errors, 'only have one Manual distributor'), 'One manual distributor per team.');

        DE_Distributor__c trig = new DE_Distributor__c(Name = 'T', Type__c = 'Trigger', Method__c = 'Lookup Owner');
        List<DE_Condition__c> six = new List<DE_Condition__c>();
        for (Integer i = 1; i <= 6; i++) {
            six.add(DE_TestFactory.condition('Distributor Filter', i, 'Company', 'is not blank', null));
        }
        errors = DE_ConfigValidator.distributor(trig, leadTeam(), new List<DE_Distributor__c>(), six, null, null, null, new Set<Id>());
        Assert.isTrue(has(errors, 'Lookup Owner is not available for Trigger'), 'Method not allowed for type.');
        Assert.isTrue(has(errors, 'at most 5 filters'), 'Trigger filter limit.');

        DE_Distributor__c lookup = new DE_Distributor__c(
            Name = 'L',
            Type__c = 'Manual',
            Method__c = 'Lookup Owner',
            Lookup_Object__c = 'Account',
            Lookup_Record_Field__c = 'Company',
            Lookup_Target_Field__c = 'NotAField__c',
            Lookup_Assign_Field__c = 'OwnerId'
        );
        Assert.isTrue(has(distributorErrors(lookup, new Set<Id>()), 'Lookup target field does not exist on Account'), 'Lookup target validated.');

        DE_Distributor__c related = new DE_Distributor__c(Name = 'R', Type__c = 'Manual', Method__c = 'Related Owner');
        Assert.isTrue(has(distributorErrors(related, new Set<Id>()), 'Choose the related object'), 'Related field required.');

        DE_Distributor__c dynamic = new DE_Distributor__c(Name = 'Dy', Type__c = 'Manual', Method__c = 'Dynamic Owner', Dynamic_Owner_Field__c = 'Nope__c');
        Assert.isTrue(has(distributorErrors(dynamic, new Set<Id>()), 'field that holds the owner Id'), 'Dynamic owner field validated.');
    }

    @IsTest
    static void distributorOptionRules() {
        User u = DE_TestFactory.users(1)[0];
        DE_Distributor__c d = new DE_Distributor__c(
            Name = '',
            Type__c = 'Pull',
            Method__c = 'Round Robin',
            Source_Type__c = 'User',
            Source_Id__c = u.Id,
            Pull_Count__c = 0,
            Assign_To__c = 'Selected Members',
            Exclude_Members_Field__c = 'Nope__c',
            Sticky_Enabled__c = true,
            Sticky_Field__c = 'Nope__c',
            Sticky_Days__c = 0,
            Auto_Reassign__c = true,
            Rejection_Enabled__c = true,
            Reject_To_Id__c = 'garbage',
            Field_Updates__c = 'Rating',
            Default_Owner_Id__c = u.Id
        );
        List<String> errors = distributorErrors(d, new Set<Id>{ u.Id });
        Assert.isTrue(has(errors, 'Enter a distributor name.'), 'Name required.');
        Assert.isTrue(has(errors, 'cannot also be a member'), 'Holding user cannot be a member.');
        Assert.isTrue(has(errors, 'between 1 and 100'), 'Pull count range.');
        Assert.isTrue(has(errors, 'Select at least one member.'), 'Selected members required.');
        Assert.isTrue(has(errors, 'Exclude members field Nope__c'), 'Exclude field validated.');
        Assert.isTrue(has(errors, 'sticky match field'), 'Sticky field validated.');
        Assert.isTrue(has(errors, 'at least one day'), 'Sticky days validated.');
        Assert.isTrue(has(errors, 'Choose a queue or user to reassign to.'), 'Reassign target required.');
        Assert.isTrue(has(errors, 'garbage is not a valid Id.'), 'Reject target validated.');
        Assert.isTrue(has(errors, 'Update fields on assignment: '), 'Field updates validated.');
        Assert.isFalse(has(errors, 'Default'), 'An active user is a valid default owner.');
    }

    @IsTest
    static void capRules() {
        Assert.isTrue(DE_ConfigValidator.cap(new DE_Cap__c(Period__c = 'Daily', Default_Cap__c = 10)).isEmpty(), 'Valid daily cap.');
        Assert.isTrue(has(DE_ConfigValidator.cap(new DE_Cap__c()), 'Choose a cap period.'), 'Period required.');
        Assert.isTrue(has(DE_ConfigValidator.cap(new DE_Cap__c(Period__c = 'Custom Hours', Custom_Length__c = 200)), 'between 1 and 168'), 'Hours range.');
        Assert.isTrue(has(DE_ConfigValidator.cap(new DE_Cap__c(Period__c = 'Custom Days', Custom_Length__c = 40)), 'between 1 and 31'), 'Days range.');
        Assert.isTrue(has(DE_ConfigValidator.cap(new DE_Cap__c(Period__c = 'Daily', Default_Cap__c = -1)), 'cannot be negative'), 'Negative cap.');
        Assert.isTrue(
            has(DE_ConfigValidator.cap(new DE_Cap__c(Period__c = 'Daily', Tag_Caps__c = 'Language:French=x')), 'whole number'),
            'Tag cap must be numeric.'
        );
        Assert.isTrue(has(DE_ConfigValidator.cap(new DE_Cap__c(Period__c = 'Daily', Tag_Caps__c = 'French=3')), 'Collection:Tag=Cap'), 'Tag cap syntax.');
        Assert.isTrue(
            DE_ConfigValidator.cap(new DE_Cap__c(Period__c = 'Daily', Tag_Caps__c = 'Language:French=\nTier:Gold=4')).isEmpty(),
            'Blank means unlimited.'
        );
    }

    @IsTest
    static void slaRules() {
        Assert.isTrue(DE_ConfigValidator.sla(new DE_SLA__c(Checkpoint__c = 1, Minutes_After_Assignment__c = 30), 'Lead', null).isEmpty(), 'Valid SLA.');
        Assert.isTrue(
            has(DE_ConfigValidator.sla(new DE_SLA__c(Checkpoint__c = 4, Minutes_After_Assignment__c = 30), 'Lead', null), '1, 2 or 3'),
            'Checkpoint range.'
        );
        Assert.isTrue(has(DE_ConfigValidator.sla(new DE_SLA__c(Checkpoint__c = 1), 'Lead', null), 'minutes after assignment'), 'Minutes required.');
        Assert.isTrue(
            has(
                DE_ConfigValidator.sla(
                    new DE_SLA__c(Checkpoint__c = 1, Alert_Type__c = 'Continuous Field Monitoring', Minutes_After_Assignment__c = 30000),
                    'Lead',
                    null
                ),
                'two weeks'
            ),
            'Continuous monitoring limit.'
        );
        Assert.isTrue(
            has(
                DE_ConfigValidator.sla(new DE_SLA__c(Checkpoint__c = 1, Alert_Type__c = 'Custom Date/Time', Check_After_Field__c = 'Company'), 'Lead', null),
                'date or date/time'
            ),
            'Custom date field must be a date.'
        );
        Assert.isTrue(
            DE_ConfigValidator.sla(new DE_SLA__c(Checkpoint__c = 1, Alert_Type__c = 'Custom Date/Time', Check_After_Field__c = 'CreatedDate'), 'Lead', null)
                .isEmpty(),
            'CreatedDate is a valid check-after field.'
        );
        Assert.isNull(
            DE_ConfigValidator.slaOrder(
                new List<DE_SLA__c>{ new DE_SLA__c(Minutes_After_Assignment__c = 10), new DE_SLA__c(Minutes_After_Assignment__c = 20) }
            ),
            'Chronological.'
        );
        Assert.isNotNull(
            DE_ConfigValidator.slaOrder(
                new List<DE_SLA__c>{ new DE_SLA__c(Minutes_After_Assignment__c = 20), new DE_SLA__c(Minutes_After_Assignment__c = 20) }
            ),
            'Equal checkpoints are not chronological.'
        );
    }

    @IsTest
    static void shiftAndSyncRules() {
        Assert.isTrue(
            DE_ConfigValidator.shift(new DE_Shift__c(Name = 'Day', Timezone__c = 'Europe/London', Schedule__c = '{"MON":["09:00-17:00"]}')).isEmpty(),
            'Valid shift.'
        );
        List<String> errors = DE_ConfigValidator.shift(new DE_Shift__c(Name = '', Timezone__c = 'Mars/Olympus', Schedule__c = '{}'));
        Assert.isTrue(has(errors, 'Enter a shift name.'), 'Name required.');
        Assert.isTrue(has(errors, 'valid timezone'), 'Unknown time zones are rejected.');
        Assert.isTrue(has(errors, 'at least one block'), 'Blocks required.');

        Assert.isTrue(
            DE_ConfigValidator.objectSync(
                    new DE_Object_Sync__c(Parent_Object__c = 'Account', Child_Object__c = 'Opportunity', Lookup_Field__c = 'AccountId'),
                    null
                )
                .isEmpty(),
            'Valid sync.'
        );
        Assert.isTrue(
            has(
                DE_ConfigValidator.objectSync(new DE_Object_Sync__c(Parent_Object__c = 'Nope__c', Child_Object__c = 'Nope__c'), null),
                'related object that has an owner'
            ),
            'Child must have an owner.'
        );
    }
}
