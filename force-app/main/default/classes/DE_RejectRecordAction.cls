/**
 * Flow action: DE Reject Record (max 500 records per call).
 */
public without sharing class DE_RejectRecordAction {
    public static final Integer MAX_RECORDS = 500;

    public class Request {
        @InvocableVariable(label='Record Id' required=true)
        public Id recordId;
        @InvocableVariable(label='Reason' required=true)
        public String reason;
    }

    public class Result {
        @InvocableVariable(label='Rejected')
        public Boolean rejected;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='DE Reject Record'
        description='Rejects Distribution Engine assignments on behalf of the running user.'
        category='Distribution Engine'
    )
    public static List<Result> reject(List<Request> requests) {
        if (requests.size() > MAX_RECORDS) {
            throw new DE_Permissions.AccessException('DE Reject Record accepts at most ' + MAX_RECORDS + ' records per call.');
        }
        Map<String, List<Id>> byReason = new Map<String, List<Id>>();
        for (Request r : requests) {
            if (!byReason.containsKey(r.reason)) {
                byReason.put(r.reason, new List<Id>());
            }
            byReason.get(r.reason).add(r.recordId);
        }
        Map<Id, DE_RejectionService.RejectResult> results = new Map<Id, DE_RejectionService.RejectResult>();
        Boolean manager = DE_Permissions.isTeamManager();
        for (String reason : byReason.keySet()) {
            for (DE_RejectionService.RejectResult r : DE_RejectionService.reject(byReason.get(reason), reason, UserInfo.getUserId(), manager)) {
                results.put(r.recordId, r);
            }
        }
        List<Result> out = new List<Result>();
        for (Request r : requests) {
            Result res = new Result();
            res.rejected = results.get(r.recordId).success;
            res.message = results.get(r.recordId).message;
            out.add(res);
        }
        return out;
    }
}
