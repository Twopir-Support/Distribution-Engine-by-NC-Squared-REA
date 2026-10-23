/**
 * Assignment simulator: runs one record through every team and distributor exactly as the engine
 * would, without saving anything or taking locks, and explains each pass/fail step.
 */
public without sharing class DE_Simulator {
    public class Options {
        @AuraEnabled
        public Datetime simulateAt { get; set; }
        @AuraEnabled
        public Boolean ignoreCaps { get; set; }
        @AuraEnabled
        public Boolean includeInactive { get; set; }
        @AuraEnabled
        public Boolean stopOnSuccess { get; set; }
    }

    public class DistributorResult {
        @AuraEnabled
        public String teamName;
        @AuraEnabled
        public String distributorName;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String method;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public Boolean sourcePassed;
        @AuraEnabled
        public Boolean filtersPassed;
        @AuraEnabled
        public Boolean assigned = false;
        @AuraEnabled
        public String assignee;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public List<String> trace = new List<String>();
    }

    public class Result {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String recordName;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String wouldAssignTo;
        @AuraEnabled
        public String classification;
        @AuraEnabled
        public List<DistributorResult> results = new List<DistributorResult>();
        @AuraEnabled
        public List<String> warnings = new List<String>();
    }

    public static Result simulate(Id recordId, Options o) {
        Options opts = o == null ? new Options() : o;
        Result result = new Result();
        result.recordId = recordId;
        result.objectName = recordId.getSobjectType().getDescribe().getName();
        List<DE_Model.TeamConfig> teams = DE_ConfigRepository.load(null, result.objectName, opts.includeInactive == true);
        if (teams.isEmpty()) {
            result.warnings.add('No ' + (opts.includeInactive == true ? '' : 'active ') + 'teams distribute ' + result.objectName + ' records.');
            return result;
        }
        Datetime at = opts.simulateAt == null ? System.now() : opts.simulateAt;
        DE_DistributionCore.RunContext ctx = new DE_DistributionCore.RunContext(teams, at);
        ctx.dryRun = true;
        ctx.ignoreCaps = opts.ignoreCaps == true;
        Set<String> paths = new Set<String>{ 'Id' };
        Set<String> detailFields = new Set<String>();
        for (DE_Model.TeamConfig cfg : teams) {
            paths.addAll(DE_RecordQuery.requiredPaths(cfg, null));
            detailFields.addAll(DE_Conditions.detailFields(cfg.teamFilters));
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                detailFields.addAll(DE_Conditions.detailFields(dc.filters));
            }
        }
        List<SObject> records = DE_RecordQuery.byIds(result.objectName, paths, new Set<Id>{ recordId }, result.warnings);
        if (records.isEmpty()) {
            result.warnings.add('Record not found.');
            return result;
        }
        SObject rec = records[0];
        result.recordName = String.valueOf(rec.get(DE_Schema.nameField(result.objectName)));
        ctx.cond.details = DE_RecordDetails.load(new Set<Id>{ recordId }, detailFields);
        DE_Record_Detail__c detail = ctx.cond.details.get(recordId);
        if (detail != null) {
            result.classification =
                'Classifier: ' +
                detail.Classifier_Status__c +
                (detail.Territory_Name__c == null ? '' : ' · Territory ' + detail.Territory_Name__c) +
                (detail.Stamps__c == null ? '' : ' · Stamps ' + detail.Stamps__c) +
                (detail.Match_Confidence__c == null ? '' : ' · ' + detail.Match_Confidence__c) +
                (DE_RecordDetails.isOnHold(detail, at) ? ' · On hold until ' + detail.On_Hold_Until__c.format() : '');
        }
        for (DE_Model.TeamConfig cfg : teams) {
            String holiday = ctx.availability.holidayFor(cfg);
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                DistributorResult dr = new DistributorResult();
                dr.teamName = cfg.team.Name + (cfg.team.Active__c ? '' : ' (inactive)');
                dr.distributorName = dc.dist.Name;
                dr.type = dc.type();
                dr.method = dc.method();
                dr.active = dc.dist.Active__c;
                result.results.add(dr);
                if (holiday != null) {
                    dr.sourcePassed = false;
                    dr.message = 'Team is on holiday: ' + holiday;
                    continue;
                }
                String type = dc.type();
                dr.sourcePassed = (type == 'Trigger' || type == 'Manual') || DE_DistributionRunner.atSource(cfg, dc, rec);
                if (!dr.sourcePassed) {
                    dr.message = 'Record is not at this distributor\'s source (' + sourceLabel(dc) + ').';
                    continue;
                }
                dr.filtersPassed = DE_DistributionCore.passesFilters(cfg, dc, rec, ctx, dr.trace);
                if (!dr.filtersPassed) {
                    dr.message = 'Record does not match the filters.';
                    continue;
                }
                if (type == 'Manual') {
                    dr.message = 'Manual distributor: a manager chooses the member.';
                    continue;
                }
                ctx.logType = type == 'Pull' ? 'Pull' : type;
                ctx.ignoreHours = type == 'Trigger' && cfg.team.Respect_Hours_For_Triggers__c != true;
                List<DE_Model.Decision> decisions = DE_DistributionCore.distribute(cfg, dc, new List<SObject>{ rec }, ctx);
                DE_Model.Decision d = decisions[0];
                dr.trace.addAll(d.trace);
                if (d.status == 'Assigned') {
                    dr.assigned = true;
                    dr.assignee = d.member != null ? d.member.name() : String.valueOf(d.assigneeId);
                    dr.message = 'Would assign to ' + dr.assignee + ' (' + d.method + ').';
                    if (result.wouldAssignTo == null && type != 'Pull') {
                        result.wouldAssignTo = dr.assignee + ' · ' + cfg.team.Name + ' / ' + dc.dist.Name;
                    }
                    if (opts.stopOnSuccess == true) {
                        return result;
                    }
                } else {
                    dr.message = d.message;
                }
            }
        }
        result.warnings.addAll(ctx.warnings);
        return result;
    }

    private static String sourceLabel(DE_Model.DistributorConfig dc) {
        if (dc.dist.Source_Type__c == 'Field Value') {
            return dc.dist.Source_Field__c + ' = ' + dc.dist.Source_Ready_Value__c;
        }
        return dc.dist.Source_Type__c + ' ' + dc.dist.Source_Id__c;
    }
}
