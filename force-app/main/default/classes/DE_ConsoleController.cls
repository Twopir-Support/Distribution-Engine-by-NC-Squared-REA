/**
 * Distribution Console, Logs, Analytics and Sync tabs: application monitoring, today's distributions,
 * sources, logs with retry, run logs, analytics, team performance, simulator, object sync and archive.
 */
public with sharing class DE_ConsoleController {
    public class Monitoring {
        @AuraEnabled
        public Boolean engineEnabled;
        @AuraEnabled
        public String schedulerStatus;
        @AuraEnabled
        public Datetime lastRunAt;
        @AuraEnabled
        public String lastRunMessage;
        @AuraEnabled
        public Boolean healthCheckerScheduled;
        @AuraEnabled
        public Integer errorsLastDay;
        @AuraEnabled
        public Integer restartsLastDay;
        @AuraEnabled
        public Integer intervalMinutes;
        @AuraEnabled
        public Boolean classifierEnabled;
        @AuraEnabled
        public Datetime lastClassifierRun;
        @AuraEnabled
        public Integer pendingSlas;
        @AuraEnabled
        public Integer onHold;
        @AuraEnabled
        public String version = '1.0.0';
    }

    public class TeamToday {
        @AuraEnabled
        public Id teamId;
        @AuraEnabled
        public String teamName;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public Integer distributions = 0;
        @AuraEnabled
        public Integer slaAlerts = 0;
        @AuraEnabled
        public Integer reassignments = 0;
        @AuraEnabled
        public Integer rejections = 0;
        @AuraEnabled
        public Integer errors = 0;
        @AuraEnabled
        public Integer available = 0;
        @AuraEnabled
        public Integer members = 0;
    }

    public class SourceRow {
        @AuraEnabled
        public Id distributorId;
        @AuraEnabled
        public String teamName;
        @AuraEnabled
        public Decimal teamOrder;
        @AuraEnabled
        public String distributorName;
        @AuraEnabled
        public Decimal distributorOrder;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String source;
        @AuraEnabled
        public Integer waiting;
        @AuraEnabled
        public Boolean active;
    }

    public class LogFilter {
        @AuraEnabled
        public Date fromDate { get; set; }
        @AuraEnabled
        public Date toDate { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public String objectName { get; set; }
        @AuraEnabled
        public Id teamId { get; set; }
        @AuraEnabled
        public Id distributorId { get; set; }
        @AuraEnabled
        public Id assigneeId { get; set; }
        @AuraEnabled
        public String search { get; set; }
    }

    public class SeriesPoint {
        @AuraEnabled
        public String x;
        @AuraEnabled
        public String series;
        @AuraEnabled
        public Decimal y;
        public SeriesPoint(String x, String series, Decimal y) {
            this.x = x;
            this.series = series;
            this.y = y;
        }
    }

    public class Analytics {
        @AuraEnabled
        public List<SeriesPoint> overTime = new List<SeriesPoint>();
        @AuraEnabled
        public List<SeriesPoint> hourly = new List<SeriesPoint>();
        @AuraEnabled
        public List<SeriesPoint> timeToAction = new List<SeriesPoint>();
        @AuraEnabled
        public List<SeriesPoint> userActivity = new List<SeriesPoint>();
    }

    public class PerformanceRow {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer assigned = 0;
        @AuraEnabled
        public Decimal avgTimeToAction;
        @AuraEnabled
        public Integer actioned = 0;
        @AuraEnabled
        public Decimal actionedPercent;
        @AuraEnabled
        public Integer reassignments = 0;
        @AuraEnabled
        public Integer slasMissed = 0;
        @AuraEnabled
        public Integer rejected = 0;
        @AuraEnabled
        public Decimal avgSpeedToAssignSeconds;
        @AuraEnabled
        public Decimal conversionPercent;
    }

    private static void requireView() {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'view the Distribution Console');
    }

    private static Datetime startOfToday() {
        return DE_ShiftCalendar.always(UserInfo.getTimeZone().getID()).localMidnight(System.now());
    }

    // ------------------------------------------------------------------ monitoring

    @AuraEnabled
    public static Monitoring getMonitoring() {
        requireView();
        Monitoring m = new Monitoring();
        m.engineEnabled = DE_Settings.engineEnabled();
        m.intervalMinutes = DE_Settings.schedulerIntervalMinutes();
        m.classifierEnabled = DE_Settings.classifierEnabled();
        Datetime dayAgo = System.now().addDays(-1);
        List<DE_Run_Log__c> last = [
            SELECT Started_At__c, Status__c, Message__c
            FROM DE_Run_Log__c
            WHERE Process__c = 'Scheduler'
            WITH USER_MODE
            ORDER BY Started_At__c DESC
            LIMIT 1
        ];
        Boolean running = DE_SchedulerJob.isRunning();
        m.schedulerStatus = !m.engineEnabled ? 'Not Configured' : (running ? 'Running' : 'Not Running');
        if (!last.isEmpty()) {
            m.lastRunAt = last[0].Started_At__c;
            m.lastRunMessage = last[0].Message__c == null ? null : last[0].Message__c.left(500);
            if (last[0].Status__c == 'Error') {
                m.schedulerStatus = 'Errored';
            } else if (running && last[0].Status__c == 'Warning') {
                m.schedulerStatus = 'Running with Warnings';
            }
        }
        m.healthCheckerScheduled = DE_HealthChecker.isScheduled();
        m.errorsLastDay = [SELECT COUNT() FROM DE_Run_Log__c WHERE Status__c = 'Error' AND Started_At__c >= :dayAgo WITH USER_MODE];
        m.restartsLastDay = [
            SELECT COUNT()
            FROM DE_Run_Log__c
            WHERE Process__c = 'Health Checker' AND Status__c = 'Warning' AND Started_At__c >= :dayAgo
            WITH USER_MODE
        ];
        List<DE_Run_Log__c> classifier = [
            SELECT Started_At__c
            FROM DE_Run_Log__c
            WHERE Process__c = 'Classifier'
            WITH USER_MODE
            ORDER BY Started_At__c DESC
            LIMIT 1
        ];
        m.lastClassifierRun = classifier.isEmpty() ? null : classifier[0].Started_At__c;
        m.pendingSlas = [SELECT COUNT() FROM DE_Assignment_Log__c WHERE Current__c = TRUE AND SLA_Status__c = 'Pending' WITH USER_MODE];
        Datetime now = System.now();
        m.onHold = [SELECT COUNT() FROM DE_Record_Detail__c WHERE On_Hold_Until__c > :now WITH USER_MODE];
        return m;
    }

    @AuraEnabled
    public static Boolean startScheduler() {
        DE_Permissions.require(DE_Permissions.isAdmin(), 'start the scheduler');
        try {
            if (!DE_HealthChecker.isScheduled()) {
                DE_HealthChecker.schedule(60);
            }
            return DE_SchedulerJob.start();
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static Integer stopScheduler() {
        DE_Permissions.require(DE_Permissions.isAdmin(), 'stop the scheduler');
        try {
            DE_HealthChecker.unschedule();
            return DE_SchedulerJob.stop();
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static String runHealthCheck() {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'run the health checker');
        try {
            return DE_HealthChecker.check();
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void scheduleHealthChecker(Integer everyMinutes) {
        DE_Permissions.require(DE_Permissions.isAdmin(), 'schedule the health checker');
        if (everyMinutes != 15 && everyMinutes != 30 && everyMinutes != 60) {
            throw DE_Ui.error('Choose every 15, 30 or 60 minutes.');
        }
        try {
            DE_HealthChecker.schedule(everyMinutes);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ today and sources

    @AuraEnabled
    public static List<TeamToday> getTodaysDistributions() {
        requireView();
        List<DE_Model.TeamConfig> teams = DE_ConfigRepository.load(null, null, false);
        DE_AvailabilityService availability = new DE_AvailabilityService(teams, System.now());
        Map<Id, TeamToday> byTeam = new Map<Id, TeamToday>();
        for (DE_Model.TeamConfig cfg : teams) {
            TeamToday t = new TeamToday();
            t.teamId = cfg.team.Id;
            t.teamName = cfg.team.Name;
            t.objectName = cfg.objectName;
            Boolean holiday = availability.holidayFor(cfg) != null;
            for (DE_Model.Member m : cfg.members) {
                if (m.isActive()) {
                    t.members++;
                    if (!holiday && availability.unavailableReason(m, false, false, false) == null) {
                        t.available++;
                    }
                }
            }
            byTeam.put(cfg.team.Id, t);
        }
        Datetime since = startOfToday();
        for (AggregateResult ar : [
            SELECT Team__c t, Status__c s, COUNT(Id) c, SUM(SLA_Missed__c) m
            FROM DE_Assignment_Log__c
            WHERE Assigned_At__c >= :since AND Team__c != NULL
            WITH USER_MODE
            GROUP BY Team__c, Status__c
        ]) {
            TeamToday t = byTeam.get((Id) ar.get('t'));
            if (t == null) {
                continue;
            }
            String s = (String) ar.get('s');
            Integer c = (Integer) ar.get('c');
            Decimal missed = (Decimal) ar.get('m');
            if (s == 'Assigned' || s == 'SLA Alert' || s == 'Reassigned' || s == 'Rejected') {
                t.distributions += c;
            }
            t.slaAlerts += missed == null ? 0 : missed.intValue();
            if (s == 'Reassigned') {
                t.reassignments += c;
            }
            if (s == 'Rejected') {
                t.rejections += c;
            }
            if (s == 'Error' || s == 'On Hold') {
                t.errors += c;
            }
        }
        return byTeam.values();
    }

    @AuraEnabled
    public static List<SourceRow> getSources() {
        requireView();
        List<SourceRow> out = new List<SourceRow>();
        List<DE_Model.TeamConfig> teams = DE_ConfigRepository.load(null, null, true);
        Set<Id> ids = new Set<Id>();
        for (DE_Model.TeamConfig cfg : teams) {
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                Id s = DE_Ids.toId(dc.dist.Source_Id__c);
                if (s != null) {
                    ids.add(s);
                }
            }
        }
        Map<Id, String> names = DE_Ui.ownerNames(ids);
        for (DE_Model.TeamConfig cfg : teams) {
            for (DE_Model.DistributorConfig dc : cfg.distributors) {
                if (dc.type() != 'Standard' && dc.type() != 'Pull') {
                    continue;
                }
                SourceRow r = new SourceRow();
                r.distributorId = dc.dist.Id;
                r.teamName = cfg.team.Name;
                r.teamOrder = cfg.team.Execution_Order__c;
                r.distributorName = dc.dist.Name;
                r.distributorOrder = dc.dist.Order__c;
                r.type = dc.type();
                r.objectName = cfg.objectName;
                r.active = cfg.team.Active__c && dc.dist.Active__c;
                Id s = DE_Ids.toId(dc.dist.Source_Id__c);
                r.source = dc.dist.Source_Type__c == 'Field Value' ? dc.dist.Source_Field__c + ' = ' + dc.dist.Source_Ready_Value__c : names.get(s);
                try {
                    r.waiting = DE_RecordQuery.countAtSource(cfg, dc);
                } catch (Exception e) {
                    r.waiting = null;
                }
                out.add(r);
            }
        }
        return out;
    }

    @AuraEnabled
    public static List<Map<String, Object>> getSourcePreview(Id distributorId) {
        requireView();
        DE_Distributor__c d = [SELECT Team__c FROM DE_Distributor__c WHERE Id = :distributorId WITH USER_MODE];
        DE_Model.TeamConfig cfg = DE_ConfigRepository.team(d.Team__c, true);
        DE_Model.DistributorConfig dc = cfg.distributor(distributorId);
        List<String> warnings = new List<String>();
        String nameField = DE_Schema.nameField(cfg.objectName);
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (SObject r : DE_RecordQuery.sourceCandidates(cfg, dc, 20, warnings)) {
            out.add(new Map<String, Object>{ 'id' => r.Id, 'name' => r.get(nameField), 'created' => r.get('CreatedDate') });
        }
        return out;
    }

    // ------------------------------------------------------------------ logs

    @AuraEnabled
    public static List<DE_Assignment_Log__c> getLogs(LogFilter filter) {
        DE_Permissions.require(DE_Permissions.isUser(), 'view distribution logs');
        LogFilter f = filter == null ? new LogFilter() : filter;
        Datetime fromAt = Datetime.newInstance(f.fromDate == null ? Date.today().addDays(-7) : f.fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime toAt = Datetime.newInstance((f.toDate == null ? Date.today() : f.toDate).addDays(1), Time.newInstance(0, 0, 0, 0));
        Map<String, Object> binds = new Map<String, Object>{ 'fromAt' => fromAt, 'toAt' => toAt };
        String soql =
            'SELECT Id, Name, Record_Id__c, Record_Name__c, Object_API_Name__c, Team__c, Team__r.Name, Distributor__c, Distributor__r.Name, ' +
            'Assignee_Id__c, Assigned_User__r.Name, Method__c, Type__c, Status__c, Is_Sticky__c, Assigned_At__c, Speed_To_Assign_Seconds__c, ' +
            'SLA_Status__c, SLA_Missed__c, Next_SLA_Check__c, Time_To_Action_Mins__c, Reject_Reason__c, Message__c, Current__c ' +
            'FROM DE_Assignment_Log__c WHERE Assigned_At__c >= :fromAt AND Assigned_At__c < :toAt';
        if (!DE_Permissions.isTeamManager()) {
            binds.put('me', String.valueOf(UserInfo.getUserId()));
            soql += ' AND Assignee_Id__c = :me';
        }
        if (String.isNotBlank(f.status)) {
            soql += ' AND Status__c = :status';
            binds.put('status', f.status);
        }
        if (String.isNotBlank(f.objectName)) {
            soql += ' AND Object_API_Name__c = :obj';
            binds.put('obj', f.objectName);
        }
        if (f.teamId != null) {
            soql += ' AND Team__c = :teamId';
            binds.put('teamId', f.teamId);
        }
        if (f.distributorId != null) {
            soql += ' AND Distributor__c = :distId';
            binds.put('distId', f.distributorId);
        }
        if (f.assigneeId != null) {
            soql += ' AND Assignee_Id__c = :assignee';
            binds.put('assignee', String.valueOf(f.assigneeId));
        }
        if (String.isNotBlank(f.search)) {
            soql += ' AND (Record_Name__c LIKE :search OR Record_Id__c = :exact)';
            binds.put('search', '%' + f.search.trim() + '%');
            binds.put('exact', f.search.trim());
        }
        soql += ' ORDER BY Assigned_At__c DESC LIMIT 500';
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static DE_Assignment_Log__c getLogTrace(Id logId) {
        DE_Permissions.require(DE_Permissions.isUser(), 'view distribution logs');
        return [SELECT Id, Name, Decision_Trace__c, Message__c, Record_Id__c FROM DE_Assignment_Log__c WHERE Id = :logId WITH USER_MODE];
    }

    /** Clears hold and failures for the records and tries to distribute them now. Returns records assigned. */
    @AuraEnabled
    public static Integer retry(List<String> recordIds) {
        DE_Permissions.require(DE_Permissions.isTeamManager(), 'retry distributions');
        try {
            Set<Id> ids = new Set<Id>();
            for (String s : recordIds) {
                Id i = DE_Ids.toId(s);
                if (i != null) {
                    ids.add(i);
                }
            }
            clearHolds(ids);
            return DE_DistributionRunner.runStandard(ids, null).assigned;
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    /** Clears hold for up to 9000 records with an Error or On Hold log in the last 7 days; the scheduler retries them. */
    @AuraEnabled
    public static Integer retryAll() {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'retry all');
        Datetime since = System.now().addDays(-7);
        Set<Id> ids = new Set<Id>();
        for (DE_Assignment_Log__c l : [
            SELECT Record_Id__c
            FROM DE_Assignment_Log__c
            WHERE Status__c IN ('Error', 'On Hold') AND Assigned_At__c >= :since
            WITH USER_MODE
            LIMIT 9000
        ]) {
            Id i = DE_Ids.toId(l.Record_Id__c);
            if (i != null) {
                ids.add(i);
            }
        }
        clearHolds(ids);
        return ids.size();
    }

    private static void clearHolds(Set<Id> ids) {
        Map<Id, DE_Record_Detail__c> details = DE_RecordDetails.load(ids, null);
        for (DE_Record_Detail__c d : details.values()) {
            d.On_Hold_Until__c = null;
            d.Failed_Attempts__c = 0;
        }
        DE_RecordDetails.save(details.values());
    }

    @AuraEnabled
    public static List<DE_Run_Log__c> getRunLogs(String process) {
        requireView();
        if (String.isBlank(process)) {
            return [
                SELECT Id, Name, Process__c, Status__c, Started_At__c, Duration_Ms__c, Records_Processed__c, Assignments__c, Errors__c, Message__c
                FROM DE_Run_Log__c
                WITH USER_MODE
                ORDER BY Started_At__c DESC
                LIMIT 200
            ];
        }
        return [
            SELECT Id, Name, Process__c, Status__c, Started_At__c, Duration_Ms__c, Records_Processed__c, Assignments__c, Errors__c, Message__c
            FROM DE_Run_Log__c
            WHERE Process__c = :process
            WITH USER_MODE
            ORDER BY Started_At__c DESC
            LIMIT 200
        ];
    }

    // ------------------------------------------------------------------ analytics and performance

    @AuraEnabled
    public static Analytics getAnalytics(Date fromDate, Date toDate, Id teamId, String objectName, String splitBy) {
        requireView();
        Analytics a = new Analytics();
        Datetime fromAt = Datetime.newInstance(fromDate == null ? Date.today().addDays(-30) : fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime toAt = Datetime.newInstance((toDate == null ? Date.today() : toDate).addDays(1), Time.newInstance(0, 0, 0, 0));
        String keyField = splitBy == 'Distributor' ? 'Distributor__r.Name' : 'Assigned_User__r.Name';
        String whereClause = 'Assigned_At__c >= :fromAt AND Assigned_At__c < :toAt AND Status__c IN :statuses';
        Map<String, Object> binds = new Map<String, Object>{ 'fromAt' => fromAt, 'toAt' => toAt, 'statuses' => DE_CapService.COUNTED_STATUSES };
        if (teamId != null) {
            whereClause += ' AND Team__c = :teamId';
            binds.put('teamId', teamId);
        }
        if (String.isNotBlank(objectName)) {
            whereClause += ' AND Object_API_Name__c = :obj';
            binds.put('obj', objectName);
        }
        for (
            AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT DAY_ONLY(convertTimezone(Assigned_At__c)) d, ' +
                    keyField +
                    ' k, COUNT(Id) c FROM DE_Assignment_Log__c WHERE ' +
                    whereClause +
                    ' GROUP BY DAY_ONLY(convertTimezone(Assigned_At__c)), ' +
                    keyField +
                    ' ORDER BY DAY_ONLY(convertTimezone(Assigned_At__c))',
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            a.overTime.add(new SeriesPoint(String.valueOf(ar.get('d')), (String) ar.get('k'), Decimal.valueOf(String.valueOf(ar.get('c')))));
        }
        for (
            AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT HOUR_IN_DAY(convertTimezone(Assigned_At__c)) h, COUNT(Id) c FROM DE_Assignment_Log__c WHERE ' +
                    whereClause +
                    ' GROUP BY HOUR_IN_DAY(convertTimezone(Assigned_At__c)) ORDER BY HOUR_IN_DAY(convertTimezone(Assigned_At__c))',
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            a.hourly.add(new SeriesPoint(String.valueOf(ar.get('h')), 'Assignments', Decimal.valueOf(String.valueOf(ar.get('c')))));
        }
        for (
            AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
                'SELECT ' +
                    keyField +
                    ' k, AVG(Time_To_Action_Mins__c) m FROM DE_Assignment_Log__c WHERE ' +
                    whereClause +
                    ' AND Time_To_Action_Mins__c != null GROUP BY ' +
                    keyField,
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            Decimal m = (Decimal) ar.get('m');
            a.timeToAction.add(new SeriesPoint((String) ar.get('k'), 'Avg minutes', m == null ? null : m.setScale(1)));
        }
        for (AggregateResult ar : [
            SELECT User__r.Name u, Online__c o, COUNT(Id) c
            FROM DE_Availability_Event__c
            WHERE Changed_At__c >= :fromAt AND Changed_At__c < :toAt
            WITH USER_MODE
            GROUP BY User__r.Name, Online__c
        ]) {
            a.userActivity.add(
                new SeriesPoint((String) ar.get('u'), ar.get('o') == true ? 'Toggled on' : 'Toggled off', Decimal.valueOf(String.valueOf(ar.get('c'))))
            );
        }
        return a;
    }

    @AuraEnabled
    public static List<PerformanceRow> getTeamPerformance(Id teamId, Date fromDate, Date toDate) {
        requireView();
        Datetime fromAt = Datetime.newInstance(fromDate == null ? Date.today().addDays(-30) : fromDate, Time.newInstance(0, 0, 0, 0));
        Datetime toAt = Datetime.newInstance((toDate == null ? Date.today() : toDate).addDays(1), Time.newInstance(0, 0, 0, 0));
        Map<String, PerformanceRow> rows = new Map<String, PerformanceRow>();
        Map<String, Set<String>> leadIdsByUser = new Map<String, Set<String>>();
        for (DE_Assignment_Log__c l : [
            SELECT
                Assignee_Id__c,
                Assigned_User__r.Name,
                Status__c,
                Time_To_Action_Mins__c,
                Action_At__c,
                SLA_Missed__c,
                Speed_To_Assign_Seconds__c,
                Object_API_Name__c,
                Record_Id__c
            FROM DE_Assignment_Log__c
            WHERE
                Team__c = :teamId
                AND Assigned_At__c >= :fromAt
                AND Assigned_At__c < :toAt
                AND Status__c IN ('Assigned', 'SLA Alert', 'Reassigned', 'Rejected')
            WITH USER_MODE
            LIMIT 20000
        ]) {
            PerformanceRow r = rows.get(l.Assignee_Id__c);
            if (r == null) {
                r = new PerformanceRow();
                r.name = l.Assigned_User__r == null ? l.Assignee_Id__c : l.Assigned_User__r.Name;
                r.avgTimeToAction = 0;
                r.avgSpeedToAssignSeconds = 0;
                rows.put(l.Assignee_Id__c, r);
            }
            r.assigned++;
            if (l.Action_At__c != null && l.Time_To_Action_Mins__c != null) {
                r.avgTimeToAction += l.Time_To_Action_Mins__c;
                r.actioned++;
            }
            if (l.Speed_To_Assign_Seconds__c != null) {
                r.avgSpeedToAssignSeconds += l.Speed_To_Assign_Seconds__c;
            }
            if (l.Status__c == 'Reassigned') {
                r.reassignments++;
            }
            if (l.Status__c == 'Rejected') {
                r.rejected++;
            }
            r.slasMissed += l.SLA_Missed__c == null ? 0 : l.SLA_Missed__c.intValue();
            if (l.Object_API_Name__c == 'Lead') {
                if (!leadIdsByUser.containsKey(l.Assignee_Id__c)) {
                    leadIdsByUser.put(l.Assignee_Id__c, new Set<String>());
                }
                leadIdsByUser.get(l.Assignee_Id__c).add(l.Record_Id__c);
            }
        }
        Set<String> allLeads = new Set<String>();
        for (Set<String> s : leadIdsByUser.values()) {
            allLeads.addAll(s);
        }
        Set<String> converted = new Set<String>();
        if (!allLeads.isEmpty()) {
            for (Lead l : [SELECT Id FROM Lead WHERE Id IN :allLeads AND IsConverted = TRUE WITH USER_MODE LIMIT 20000]) {
                converted.add(String.valueOf(l.Id));
            }
        }
        for (String key : rows.keySet()) {
            PerformanceRow r = rows.get(key);
            r.avgTimeToAction = r.actioned == 0 ? null : (r.avgTimeToAction / r.actioned).setScale(1);
            r.actionedPercent = r.assigned == 0 ? 0 : (Decimal.valueOf(r.actioned) * 100 / r.assigned).setScale(1);
            r.avgSpeedToAssignSeconds = r.assigned == 0 ? null : (r.avgSpeedToAssignSeconds / r.assigned).setScale(0);
            if (leadIdsByUser.containsKey(key)) {
                Set<String> mine = leadIdsByUser.get(key);
                Integer c = 0;
                for (String id : mine) {
                    if (converted.contains(id)) {
                        c++;
                    }
                }
                r.conversionPercent = (Decimal.valueOf(c) * 100 / mine.size()).setScale(1);
            }
        }
        return rows.values();
    }

    // ------------------------------------------------------------------ simulator

    @AuraEnabled
    public static DE_Simulator.Result simulate(Id recordId, DE_Simulator.Options options) {
        requireView();
        try {
            return DE_Simulator.simulate(recordId, options);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ object sync

    @AuraEnabled
    public static List<DE_ClassifierController.ConditionalRecord> getSyncActions() {
        requireView();
        List<DE_ClassifierController.ConditionalRecord> out = new List<DE_ClassifierController.ConditionalRecord>();
        for (DE_Object_Sync__c a : [
            SELECT
                Id,
                Name,
                Parent_Object__c,
                Child_Object__c,
                Lookup_Field__c,
                Filter_Logic__c,
                Active__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Object_Sync__c
            WITH USER_MODE
            ORDER BY Name
        ]) {
            DE_ClassifierController.ConditionalRecord cr = new DE_ClassifierController.ConditionalRecord();
            cr.record = a;
            cr.conditions = a.Conditions__r;
            out.add(cr);
        }
        return out;
    }

    @AuraEnabled
    public static Id saveSyncAction(DE_Object_Sync__c action, List<DE_Condition__c> conditions) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'edit object sync');
        List<DE_Condition__c> c = DE_Ui.prepare(conditions, 'Sync Filter');
        DE_Ui.throwIfErrors(DE_ConfigValidator.objectSync(action, c));
        Savepoint sp = Database.setSavepoint();
        try {
            Database.upsert(action, true, AccessLevel.USER_MODE);
            DE_Ui.replaceConditions('Object_Sync__c', action.Id, new Set<String>{ 'Sync Filter' }, 'Sync Filter', c);
            return action.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw DE_Ui.error(e);
        }
    }

    @AuraEnabled
    public static void deleteSyncAction(Id actionId) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'delete object sync actions');
        try {
            DE_Ui.deleteAll([SELECT Id FROM DE_Condition__c WHERE Object_Sync__c = :actionId], true, AccessLevel.USER_MODE);
            Database.delete(new DE_Object_Sync__c(Id = actionId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }

    // ------------------------------------------------------------------ archive

    @AuraEnabled
    public static List<Map<String, Object>> getArchived(String objectName) {
        requireView();
        if (!DE_ArchiveService.OBJECTS.contains(objectName)) {
            throw DE_Ui.error('Archive is available for Leads and Cases.');
        }
        String nameField = DE_Schema.nameField(objectName);
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (
            SObject r : Database.query(
                'SELECT Id, ' +
                    nameField +
                    ', DE_Last_Archive_Date__c, DE_Source_Queue__c FROM ' +
                    objectName +
                    ' WHERE DE_Is_Archived__c = true ORDER BY DE_Last_Archive_Date__c DESC LIMIT 200',
                AccessLevel.USER_MODE
            )
        ) {
            out.add(
                new Map<String, Object>{
                    'id' => r.Id,
                    'name' => r.get(nameField),
                    'archivedAt' => r.get('DE_Last_Archive_Date__c'),
                    'sourceQueue' => r.get('DE_Source_Queue__c')
                }
            );
        }
        return out;
    }

    @AuraEnabled
    public static Integer restoreArchived(List<Id> recordIds) {
        DE_Permissions.require(DE_Permissions.isSystemManager(), 'restore archived records');
        try {
            return DE_ArchiveService.restore(new Set<Id>(recordIds));
        } catch (Exception e) {
            throw DE_Ui.error(e);
        }
    }
}
