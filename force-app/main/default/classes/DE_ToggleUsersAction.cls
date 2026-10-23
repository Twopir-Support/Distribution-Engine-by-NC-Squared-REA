/**
 * Flow action: DE Toggle Users.
 */
public without sharing class DE_ToggleUsersAction {
    public class Request {
        @InvocableVariable(label='User Id' required=true)
        public Id userId;
        @InvocableVariable(label='Online' required=true)
        public Boolean online;
        @InvocableVariable(label='Reason')
        public String reason;
        @InvocableVariable(label='Timer (minutes)')
        public Integer timerMinutes;
    }

    @InvocableMethod(label='DE Toggle Users' description='Sets users online or offline in Distribution Engine.' category='Distribution Engine')
    public static void toggle(List<Request> requests) {
        Map<String, Set<Id>> groups = new Map<String, Set<Id>>();
        Map<String, Request> sample = new Map<String, Request>();
        for (Request r : requests) {
            String key = r.online + '|' + r.reason + '|' + r.timerMinutes;
            if (!groups.containsKey(key)) {
                groups.put(key, new Set<Id>());
                sample.put(key, r);
            }
            groups.get(key).add(r.userId);
        }
        for (String key : groups.keySet()) {
            Request r = sample.get(key);
            DE_AgentService.setOnline(groups.get(key), r.online == true, r.reason, r.timerMinutes, 'API');
        }
    }
}
