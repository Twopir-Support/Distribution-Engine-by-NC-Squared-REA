/**
 * Public Apex API for Distribution Engine by NC Squared.
 */
global without sharing class DE_Api {
    /** Runs Trigger distributors for the records (any object with a team). Returns records assigned. */
    global static Integer distributeRecords(Set<Id> recordIds) {
        DE_TriggerDistribution.Outcome o = DE_TriggerDistribution.distributeIds(recordIds, 'Flow');
        return o.assigned + o.defaulted;
    }

    /** Runs Trigger distributors on Trigger.new rows inside a before update trigger (no extra DML). */
    global static void distributeInsideTrigger(String objectName, List<SObject> records) {
        DE_TriggerDistribution.run(objectName, records, 'Trigger', true);
    }

    /** Runs Standard distributors now for these records instead of waiting for the scheduler. */
    global static Integer distributeNow(Set<Id> recordIds) {
        return DE_DistributionRunner.runStandard(recordIds, null).assigned;
    }

    /** Toggles users online or offline (source API; reason and timer optional). */
    global static void toggleUsers(Set<Id> userIds, Boolean online, String reason, Integer timerMinutes) {
        DE_AgentService.setOnline(userIds, online, reason, timerMinutes, 'API');
    }

    /** Availability right now per user across all their teams (true = available in at least one team). */
    global static Map<Id, Boolean> getAvailability(Set<Id> userIds) {
        Map<Id, Boolean> out = new Map<Id, Boolean>();
        for (Id u : userIds) {
            out.put(u, false);
        }
        Set<Id> teamIds = new Set<Id>();
        for (DE_Team_Member__c m : [SELECT Team__c FROM DE_Team_Member__c WHERE User__c IN :userIds AND Active__c = TRUE AND Team__r.Active__c = TRUE]) {
            teamIds.add(m.Team__c);
        }
        List<DE_Model.TeamConfig> teams = DE_ConfigRepository.load(teamIds, null, false);
        DE_AvailabilityService availability = new DE_AvailabilityService(teams, System.now());
        for (DE_Model.TeamConfig cfg : teams) {
            if (availability.holidayFor(cfg) != null) {
                continue;
            }
            for (DE_Model.Member m : cfg.members) {
                if (out.containsKey(m.memberId) && m.isActive() && availability.unavailableReason(m, false, false, false) == null) {
                    out.put(m.memberId, true);
                }
            }
        }
        return out;
    }

    /** Rejects records on behalf of the current user. Returns one message per record. */
    global static List<String> rejectRecords(List<Id> recordIds, String reason) {
        List<String> out = new List<String>();
        for (DE_RejectionService.RejectResult r : DE_RejectionService.reject(recordIds, reason, UserInfo.getUserId(), DE_Permissions.isTeamManager())) {
            out.add(r.message);
        }
        return out;
    }

    /** Classifies records now. Types: Territory, Stamps, Match, Conversion (null = all). */
    global static void classifyRecords(Set<Id> recordIds, Set<String> types) {
        Map<String, Set<Id>> byObject = new Map<String, Set<Id>>();
        for (Id i : recordIds) {
            String o = i.getSobjectType().getDescribe().getName();
            if (!byObject.containsKey(o)) {
                byObject.put(o, new Set<Id>());
            }
            byObject.get(o).add(i);
        }
        for (String o : byObject.keySet()) {
            DE_ClassifierService.classify(o, byObject.get(o), types);
        }
    }
}
