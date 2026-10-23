/**
 * Flow action: DE Distribute Records.
 */
public without sharing class DE_FlowActions {
    public class DistributeRequest {
        @InvocableVariable(label='Record Id' required=true)
        public Id recordId;
        @InvocableVariable(
            label='Run Standard distributors too'
            description='Also run Standard distributors for the record if no Trigger distributor assigns it.'
        )
        public Boolean includeStandard;
    }

    public class DistributeResult {
        @InvocableVariable(label='Assigned')
        public Boolean assigned;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='DE Distribute Records'
        description='Assigns records with Distribution Engine Trigger distributors (and optionally Standard distributors).'
        category='Distribution Engine'
    )
    public static List<DistributeResult> distribute(List<DistributeRequest> requests) {
        Set<Id> ids = new Set<Id>();
        Set<Id> standard = new Set<Id>();
        for (DistributeRequest r : requests) {
            ids.add(r.recordId);
            if (r.includeStandard == true) {
                standard.add(r.recordId);
            }
        }
        DE_TriggerDistribution.Outcome o = DE_TriggerDistribution.distributeIds(ids, 'Flow');
        Set<Id> assigned = new Set<Id>();
        for (DE_Assignment_Log__c l : [
            SELECT Record_Id__c
            FROM DE_Assignment_Log__c
            WHERE Record_Id__c IN :toStrings(ids) AND Current__c = TRUE AND Assigned_At__c >= :System.now().addMinutes(-1)
        ]) {
            assigned.add(Id.valueOf(l.Record_Id__c));
        }
        standard.removeAll(assigned);
        if (!standard.isEmpty()) {
            DE_DistributionRunner.runStandard(standard, null);
            for (DE_Assignment_Log__c l : [
                SELECT Record_Id__c
                FROM DE_Assignment_Log__c
                WHERE Record_Id__c IN :toStrings(standard) AND Current__c = TRUE AND Assigned_At__c >= :System.now().addMinutes(-1)
            ]) {
                assigned.add(Id.valueOf(l.Record_Id__c));
            }
        }
        List<DistributeResult> out = new List<DistributeResult>();
        for (DistributeRequest r : requests) {
            DistributeResult res = new DistributeResult();
            res.assigned = assigned.contains(r.recordId);
            res.message = res.assigned ? 'Assigned.' : (o.messageByRecord.containsKey(r.recordId) ? o.messageByRecord.get(r.recordId) : 'Not assigned.');
            out.add(res);
        }
        return out;
    }

    private static List<String> toStrings(Set<Id> ids) {
        List<String> out = new List<String>();
        for (Id i : ids) {
            out.add(String.valueOf(i));
        }
        return out;
    }
}
