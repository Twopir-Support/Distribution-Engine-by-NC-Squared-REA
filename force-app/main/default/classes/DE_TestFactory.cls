/**
 * Test data builders shared by the Distribution Engine test classes.
 */
@IsTest
public class DE_TestFactory {
    private static Integer userCounter = 0;

    /** Org-default settings that keep tests deterministic: no async distribution after classification. */
    public static DE_Settings__c settings() {
        DE_Settings__c s = DE_Settings__c.getOrgDefaults();
        if (s == null || s.Id == null) {
            s = new DE_Settings__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        s.Engine_Enabled__c = true;
        s.Distribute_After_Classify__c = false;
        s.Publish_Platform_Events__c = false;
        upsert s;
        DE_Settings.setForTransaction(null);
        return s;
    }

    /** Active users with the running user's profile, inserted. */
    public static List<User> users(Integer count) {
        List<User> out = new List<User>();
        Id profileId = UserInfo.getProfileId();
        for (Integer i = 0; i < count; i++) {
            userCounter++;
            String key = 'de' + userCounter + '_' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
            out.add(
                new User(
                    FirstName = 'Agent',
                    LastName = 'Number ' + userCounter,
                    Alias = ('de' + userCounter).left(8),
                    Email = key + '@example.com',
                    Username = key + '@de-test.example.com',
                    ProfileId = profileId,
                    TimeZoneSidKey = 'Europe/London',
                    LocaleSidKey = 'en_GB',
                    EmailEncodingKey = 'UTF-8',
                    LanguageLocaleKey = 'en_US'
                )
            );
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert out;
        }
        return out;
    }

    /** A queue that supports the given objects. Inserted as setup DML in its own context. */
    public static Group queue(String name, List<String> objectNames) {
        Group g = new Group(Name = name, DeveloperName = name.replaceAll('[^A-Za-z0-9]', '_') + '_' + userCounter++, Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert g;
            List<QueueSobject> qs = new List<QueueSobject>();
            for (String o : objectNames) {
                qs.add(new QueueSobject(QueueId = g.Id, SobjectType = o));
            }
            insert qs;
        }
        return g;
    }

    public static DE_Team__c team(String name, String objectName) {
        return new DE_Team__c(Name = name, Object_API_Name__c = objectName, Active__c = true, Execution_Order__c = 10);
    }

    public static DE_Team__c insertTeam(String name, String objectName) {
        DE_Team__c t = team(name, objectName);
        insert t;
        return t;
    }

    public static List<DE_Team_Member__c> members(Id teamId, List<User> users) {
        List<DE_Team_Member__c> out = new List<DE_Team_Member__c>();
        for (User u : users) {
            out.add(new DE_Team_Member__c(Team__c = teamId, User__c = u.Id, Active__c = true, Weight__c = 1));
        }
        insert out;
        return out;
    }

    /** An active Standard distributor pulling from a queue with the given method. */
    public static DE_Distributor__c distributor(Id teamId, String name, Id sourceQueueId, String method) {
        return new DE_Distributor__c(
            Team__c = teamId,
            Name = name,
            Active__c = true,
            Type__c = 'Standard',
            Method__c = method,
            Source_Type__c = 'Queue',
            Source_Id__c = sourceQueueId,
            Order__c = 10,
            Assign_To__c = 'All Team Members',
            Send_Notification__c = false
        );
    }

    public static DE_Distributor__c insertDistributor(Id teamId, String name, Id sourceQueueId, String method) {
        DE_Distributor__c d = distributor(teamId, name, sourceQueueId, method);
        insert d;
        return d;
    }

    public static DE_Condition__c condition(String purpose, Integer seq, String field, String operator, String value) {
        return new DE_Condition__c(Purpose__c = purpose, Sequence__c = seq, Field_API_Name__c = field, Operator__c = operator, Value__c = value);
    }

    public static List<Lead> leads(Integer count, Id ownerId) {
        List<Lead> out = new List<Lead>();
        for (Integer i = 0; i < count; i++) {
            out.add(new Lead(LastName = 'Lead ' + i, Company = 'Company ' + i, Email = 'lead' + i + '@acme' + i + '.example.com', OwnerId = ownerId));
        }
        return out;
    }

    public static List<Lead> insertLeads(Integer count, Id ownerId) {
        List<Lead> out = leads(count, ownerId);
        insert out;
        return out;
    }

    public static List<Case> insertCases(Integer count, Id ownerId) {
        List<Case> out = new List<Case>();
        for (Integer i = 0; i < count; i++) {
            out.add(new Case(Subject = 'Case ' + i, Origin = 'Web', Status = 'New', OwnerId = ownerId));
        }
        insert out;
        return out;
    }

    /** Owner id of each record, keyed by record id. */
    public static Map<Id, Id> owners(String objectName, Set<Id> ids) {
        Map<Id, Id> out = new Map<Id, Id>();
        for (SObject r : Database.query('SELECT Id, OwnerId FROM ' + objectName + ' WHERE Id IN :ids')) {
            out.put(r.Id, (Id) r.get('OwnerId'));
        }
        return out;
    }

    /** Count of values in a map, grouped by value. */
    public static Map<Id, Integer> countByValue(Map<Id, Id> values) {
        Map<Id, Integer> out = new Map<Id, Integer>();
        for (Id v : values.values()) {
            out.put(v, (out.containsKey(v) ? out.get(v) : 0) + 1);
        }
        return out;
    }

    /** Grants every Distribution Engine role to the running transaction (controllers check custom permissions). */
    public static void grantAll() {
        DE_Permissions.overrides = new Set<String>{ 'DE_Admin', 'DE_System_Manager', 'DE_Team_Manager', 'DE_User' };
    }

    public static void grant(Set<String> permissions) {
        DE_Permissions.overrides = permissions;
    }

    /** Standard routing fixture: Lead team, queue, users and a round-robin distributor. */
    public class Fixture {
        public Group queue;
        public List<User> users;
        public DE_Team__c team;
        public List<DE_Team_Member__c> members;
        public DE_Distributor__c distributor;
    }

    public static Fixture leadFixture(Integer userCount, String method) {
        settings();
        Fixture f = new Fixture();
        f.queue = queue('DE Lead Inbox', new List<String>{ 'Lead' });
        f.users = users(userCount);
        f.team = insertTeam('Inbound Sales', 'Lead');
        f.members = members(f.team.Id, f.users);
        f.distributor = insertDistributor(f.team.Id, 'Inbound', f.queue.Id, method);
        return f;
    }
}
