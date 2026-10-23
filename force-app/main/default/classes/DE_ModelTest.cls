@IsTest
private class DE_ModelTest {
    private static Id fakeId(Schema.SObjectType t, Integer n) {
        return Id.valueOf(t.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0'));
    }

    private static User namedUser(String name, Boolean active) {
        return (User) JSON.deserialize(JSON.serialize(new Map<String, Object>{ 'Name' => name, 'IsActive' => active }), User.class);
    }

    private static void assertNum(Decimal expected, Decimal actual, String message) {
        Assert.isTrue(expected == actual, message + ': expected ' + expected + ' but was ' + actual);
    }

    @IsTest
    static void parsesTagsAndPairs() {
        Assert.areEqual(
            new Set<String>{ 'language:french', 'tier:gold', 'region:north' },
            DE_Model.parseTags('Language:French; Tier:Gold\nRegion:North;;'),
            'tags are trimmed and lower-cased'
        );
        Assert.isTrue(DE_Model.parseTags(null).isEmpty(), 'blank tags');

        Map<String, String> pairs = DE_Model.parsePairs('Tier:Gold=2\nno equals sign\n Language:French = 3 ');
        Assert.areEqual(2, pairs.size(), 'lines without = are skipped');
        Assert.areEqual('2', pairs.get('tier:gold'), 'key is lower-cased');
        Assert.areEqual('3', pairs.get('language:french'), 'key and value are trimmed');
        Assert.isTrue(DE_Model.parsePairs('').isEmpty(), 'blank pairs');
    }

    @IsTest
    static void memberHelpers() {
        DE_Model.Member m = new DE_Model.Member();
        m.record = new DE_Team_Member__c(Active__c = true);
        m.user = namedUser('Ann Agent', true);
        m.tags = DE_Model.parseTags('Language:French;Language:German;Tier:Gold');
        Assert.areEqual('Ann Agent', m.name(), 'user name');
        Assert.isTrue(m.isActive(), 'active member and user');
        Assert.isTrue(m.isOnline(), 'no agent record means online');
        Assert.areEqual(new Set<String>{ 'french', 'german' }, m.tagsIn(' Language '), 'tags in one collection');
        Assert.isTrue(m.tagsIn('Region').isEmpty(), 'no tags in another collection');

        m.agent = new DE_Agent__c(Online__c = false);
        Assert.isFalse(m.isOnline(), 'agent toggled offline');
        m.user = namedUser('Ann Agent', false);
        Assert.isFalse(m.isActive(), 'inactive user');

        DE_Model.Member q = new DE_Model.Member();
        q.isQueue = true;
        q.record = new DE_Team_Member__c(Active__c = true, Queue_Id__c = '00G000000000001');
        q.agent = new DE_Agent__c(Online__c = false);
        Assert.areEqual('00G000000000001', q.name(), 'queue members are named by queue id');
        Assert.isTrue(q.isActive(), 'queues need no user');
        Assert.isTrue(q.isOnline(), 'queues are always online');
        q.record.Active__c = false;
        Assert.isFalse(q.isActive(), 'inactive membership');
    }

    @IsTest
    static void teamAndDistributorHelpers() {
        DE_Model.TeamConfig cfg = new DE_Model.TeamConfig();
        cfg.team = new DE_Team__c(Team_Type__c = 'Queue to Queue');
        Assert.isTrue(cfg.isQueueToQueue(), 'queue to queue team');
        Assert.areEqual(UserInfo.getTimeZone().getID(), cfg.timezoneSid(), 'no team hours means user timezone');
        cfg.teamCalendar = DE_ShiftCalendar.always('Asia/Tokyo');
        Assert.areEqual('Asia/Tokyo', cfg.timezoneSid(), 'team hours timezone');

        DE_Model.DistributorConfig dc = new DE_Model.DistributorConfig();
        dc.dist = new DE_Distributor__c(Id = fakeId(DE_Distributor__c.SObjectType, 1));
        Assert.areEqual('Standard', dc.type(), 'default type');
        Assert.areEqual('Round Robin', dc.method(), 'default method');
        dc.dist.Type__c = 'Pull';
        dc.dist.Method__c = 'Load Balancing';
        Assert.areEqual('Pull', dc.type(), 'type');
        Assert.areEqual('Load Balancing', dc.method(), 'method');
        cfg.distributors.add(dc);
        Assert.areEqual(dc, cfg.distributor(dc.dist.Id), 'find distributor by id');
        Assert.isNull(cfg.distributor(fakeId(DE_Distributor__c.SObjectType, 2)), 'unknown distributor');

        DE_Model.Member m = new DE_Model.Member();
        m.memberId = fakeId(DE_Team_Member__c.SObjectType, 1);
        cfg.members.add(m);
        Assert.areEqual(m, cfg.member(m.memberId), 'find member by id');
        Assert.isNull(cfg.member(fakeId(DE_Team_Member__c.SObjectType, 2)), 'unknown member');

        Lead l = new Lead(Id = fakeId(Lead.SObjectType, 1));
        DE_Model.Decision d = new DE_Model.Decision(l);
        Assert.areEqual(l.Id, d.recordId, 'decision record id');
        Assert.areEqual('Assigned', d.status, 'default status');
        Assert.isTrue(d.countsAsHit, 'counts as a hit by default');
    }

    @IsTest
    static void idHelpers() {
        Id userId = UserInfo.getUserId();
        Id groupId = fakeId(Group.SObjectType, 1);
        Assert.areEqual(userId, DE_Ids.toId(' ' + userId + ' '), 'trimmed id');
        Assert.isNull(DE_Ids.toId('nope'), 'invalid id');
        Assert.isNull(DE_Ids.toId(''), 'blank id');
        Assert.isTrue(DE_Ids.isUser(userId), 'user id');
        Assert.isTrue(DE_Ids.isUser(String.valueOf(userId)), 'user id as text');
        Assert.isFalse(DE_Ids.isUser(groupId), 'group is not a user');
        Assert.isTrue(DE_Ids.isQueue(groupId), 'group id');
        Assert.isTrue(DE_Ids.isUserOrQueue(String.valueOf(groupId)), 'user or queue');
        Assert.isFalse(DE_Ids.isUserOrQueue('abc'), 'invalid text');
        Assert.areEqual(new Set<Id>{ userId, groupId }, DE_Ids.parseList(userId + ', bad;' + groupId + '\n'), 'list with invalid entries');
        Assert.isTrue(DE_Ids.parseList(null).isEmpty(), 'blank list');

        Assert.isNull(DE_Ids.ownerError(null, true), 'blank owner is allowed');
        Assert.isNull(DE_Ids.ownerError(userId, false), 'active user');
        Assert.isTrue(DE_Ids.ownerError('xyz', true).contains('not a valid Id'), 'invalid');
        Assert.isTrue(DE_Ids.ownerError(groupId, true).contains('does not exist'), 'missing queue');
        Assert.isTrue(DE_Ids.ownerError(groupId, false).contains('must be a User Id'), 'queue not allowed');
        Assert.isTrue(DE_Ids.ownerError(fakeId(User.SObjectType, 1), true).contains('does not exist or is inactive'), 'missing user');
        Assert.isTrue(DE_Ids.ownerError(fakeId(Account.SObjectType, 1), true).contains('must be a User or Queue Id'), 'other object');

        Group q = DE_TestFactory.queue('DE Model Queue', new List<String>{ 'Lead' });
        Assert.isNull(DE_Ids.ownerError(q.Id, true), 'existing queue');
    }

    @IsTest
    static void parsesWeightsAndClampsMemberWeights() {
        Map<String, Decimal> w = DE_ConfigRepository.parseWeights('Tier:Gold=2\nTier:Silver=abc\nTier:Bronze=0.5');
        Assert.areEqual(2, w.size(), 'non-numeric weights are skipped');
        Assert.areEqual(2, w.get('tier:gold').intValue(), 'gold weight');
        Assert.isTrue(DE_ConfigRepository.parseWeights(null).isEmpty(), 'blank weights');

        DE_Model.TeamConfig cfg = new DE_Model.TeamConfig();
        cfg.team = new DE_Team__c(Weighting_Mode__c = 'Individual');
        assertNum(4, DE_ConfigRepository.memberWeight(cfg, new DE_Team_Member__c(Weight__c = 10), new Set<String>()), 'clamped to 4');
        assertNum(0.25, DE_ConfigRepository.memberWeight(cfg, new DE_Team_Member__c(Weight__c = 0.1), new Set<String>()), 'clamped to 0.25');
        assertNum(1, DE_ConfigRepository.memberWeight(cfg, new DE_Team_Member__c(), new Set<String>()), 'null weight is 1');
        assertNum(2.5, DE_ConfigRepository.memberWeight(cfg, new DE_Team_Member__c(Weight__c = 2.5), new Set<String>()), 'individual weight');

        cfg.team = new DE_Team__c(Weighting_Mode__c = 'Tag', Default_Tag_Weight__c = 0.5);
        cfg.tagWeights = new Map<String, Decimal>{ 'tier:gold' => 3, 'tier:silver' => 2 };
        assertNum(
            3,
            DE_ConfigRepository.memberWeight(cfg, new DE_Team_Member__c(Weight__c = 1), new Set<String>{ 'tier:silver', 'tier:gold' }),
            'highest tag weight wins'
        );
        assertNum(0.5, DE_ConfigRepository.memberWeight(cfg, new DE_Team_Member__c(Weight__c = 4), new Set<String>{ 'other:tag' }), 'default tag weight');
        cfg.team.Default_Tag_Weight__c = null;
        assertNum(1, DE_ConfigRepository.memberWeight(cfg, new DE_Team_Member__c(), new Set<String>()), 'no default tag weight means 1');
    }
}
