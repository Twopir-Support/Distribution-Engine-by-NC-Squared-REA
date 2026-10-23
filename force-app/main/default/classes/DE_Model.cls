/**
 * In-memory configuration and decision types shared by the distribution engine.
 */
public inherited sharing class DE_Model {
    public class TeamConfig {
        public DE_Team__c team;
        public String objectName;
        public String assignmentField;
        public List<DistributorConfig> distributors = new List<DistributorConfig>();
        public List<DE_Condition__c> teamFilters = new List<DE_Condition__c>();
        public List<DE_Condition__c> dynamicMembership = new List<DE_Condition__c>();
        public List<DE_Cap__c> caps = new List<DE_Cap__c>();
        public Map<Id, List<DE_Condition__c>> capCriteria = new Map<Id, List<DE_Condition__c>>();
        public List<DE_SLA__c> slas = new List<DE_SLA__c>();
        public Map<Id, List<DE_Condition__c>> slaConditions = new Map<Id, List<DE_Condition__c>>();
        public List<Member> members = new List<Member>();
        public DE_ShiftCalendar teamCalendar;
        public Map<String, Decimal> tagWeights = new Map<String, Decimal>();
        public Set<String> activeStatusValues = new Set<String>();

        public String timezoneSid() {
            return teamCalendar == null ? UserInfo.getTimeZone().getID() : teamCalendar.timezoneSid;
        }

        public Boolean isQueueToQueue() {
            return team.Team_Type__c == 'Queue to Queue';
        }

        public DistributorConfig distributor(Id distributorId) {
            for (DistributorConfig d : distributors) {
                if (d.dist.Id == distributorId) {
                    return d;
                }
            }
            return null;
        }

        public Member member(Id memberId) {
            for (Member m : members) {
                if (m.memberId == memberId) {
                    return m;
                }
            }
            return null;
        }
    }

    public class DistributorConfig {
        public DE_Distributor__c dist;
        public List<DE_Condition__c> filters = new List<DE_Condition__c>();
        public List<DE_Condition__c> memberFilters = new List<DE_Condition__c>();
        public List<DE_Condition__c> lookupWhere = new List<DE_Condition__c>();
        public List<DE_Cap__c> caps = new List<DE_Cap__c>();
        public Set<Id> selectedMembers = new Set<Id>();

        public String type() {
            return dist.Type__c == null ? 'Standard' : dist.Type__c;
        }

        public String method() {
            return dist.Method__c == null ? 'Round Robin' : dist.Method__c;
        }
    }

    public class Member {
        public DE_Team_Member__c record;
        public Id memberId;
        public Boolean isQueue = false;
        public User user;
        public DE_Agent__c agent;
        public DE_ShiftCalendar calendar;
        public Set<String> tags = new Set<String>(); // lower-case "collection:tag"
        public Decimal weight = 1;

        public String name() {
            if (user != null) {
                return user.Name;
            }
            return record.Queue_Id__c;
        }

        public Boolean isActive() {
            return record.Active__c && (isQueue || (user != null && user.IsActive));
        }

        public Boolean isOnline() {
            return isQueue || agent == null || agent.Online__c;
        }

        public Set<String> tagsIn(String collection) {
            Set<String> out = new Set<String>();
            String prefix = collection.trim().toLowerCase() + ':';
            for (String t : tags) {
                if (t.startsWith(prefix)) {
                    out.add(t.substring(prefix.length()));
                }
            }
            return out;
        }
    }

    /** The outcome of distributing one record. */
    public class Decision {
        public SObject record;
        public Id recordId;
        public Id assigneeId;
        public Member member;
        public DistributorConfig distributor;
        public String method;
        public String status = 'Assigned';
        public String message;
        public Boolean sticky = false;
        public Boolean countsAsHit = true;
        public String stickyKey;
        public Decimal balanceValue;
        public Id previousOwnerId;
        public List<String> trace = new List<String>();

        public Decision(SObject record) {
            this.record = record;
            this.recordId = record.Id;
        }
    }

    /** Parses "Collection:Tag;Collection:Tag" into a lower-case set. */
    public static Set<String> parseTags(String value) {
        Set<String> out = new Set<String>();
        if (String.isBlank(value)) {
            return out;
        }
        for (String t : value.split('[;\\n]')) {
            if (String.isNotBlank(t)) {
                out.add(t.trim().toLowerCase());
            }
        }
        return out;
    }

    /** Parses "Key=Value" lines into an ordered map keyed by lower-case key. */
    public static Map<String, String> parsePairs(String value) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(value)) {
            return out;
        }
        for (String line : value.split('\\n')) {
            if (line.contains('=')) {
                out.put(line.substringBefore('=').trim().toLowerCase(), line.substringAfter('=').trim());
            }
        }
        return out;
    }
}
