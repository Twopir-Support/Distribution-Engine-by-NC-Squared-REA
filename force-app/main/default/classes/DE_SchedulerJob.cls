/**
 * The distribution scheduler: a self-chaining Queueable that runs every 1-10 minutes.
 * Each run: availability housekeeping, Standard distributors, SLA monitor, classifier retries, run log, re-enqueue.
 * The health checker restarts the chain if it stops.
 */
public without sharing class DE_SchedulerJob implements Queueable {
    public static final Integer SLA_BATCH = 200;
    /** Records whose classification failed that are retried per run. */
    public static final Integer CLASSIFIER_RETRY_BATCH = 50;
    private Id resumeAfterTeamId;
    private Boolean chain = true;

    public DE_SchedulerJob() {
        this(null, true);
    }

    public DE_SchedulerJob(Id resumeAfterTeamId, Boolean chain) {
        this.resumeAfterTeamId = resumeAfterTeamId;
        this.chain = chain;
    }

    public void execute(QueueableContext context) {
        Datetime started = System.now();
        DE_DistributionRunner.Summary summary;
        DE_SlaService.MonitorSummary sla;
        String status = 'Success';
        List<String> messages = new List<String>();
        Id resume = null;
        try {
            if (!DE_Settings.engineEnabled()) {
                return;
            }
            Integer timers = DE_AgentService.expireTimers(started);
            Integer boundaries = DE_AgentService.applyDayBoundaries(started);
            if (timers + boundaries > 0) {
                messages.add(timers + ' timer toggles ended; ' + boundaries + ' start/end of day toggles applied.');
            }
            summary = DE_DistributionRunner.runStandard(null, resumeAfterTeamId);
            resume = summary.resumeAfterTeamId;
            messages.addAll(summary.messages);
            sla = DE_SlaService.monitor(SLA_BATCH, System.now());
            messages.addAll(sla.messages);
            if (sla.missed > 0) {
                messages.add(sla.missed + ' SLAs missed, ' + sla.reassigned + ' records reassigned.');
            }
            if (DE_Settings.classifierEnabled()) {
                Integer retried = DE_ClassifierLogs.retryFailed(CLASSIFIER_RETRY_BATCH);
                if (retried > 0) {
                    messages.add(retried + ' records with failed classification were retried.');
                }
            }
            if (summary.errors > 0) {
                status = 'Warning';
            }
        } catch (Exception e) {
            status = 'Error';
            messages.add(e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        insertRunLog(started, status, summary, messages, context == null ? null : context.getJobId());
        if (chain && DE_Settings.engineEnabled() && !Test.isRunningTest()) {
            enqueueNext(resume);
        }
    }

    private static void insertRunLog(Datetime started, String status, DE_DistributionRunner.Summary summary, List<String> messages, Id jobId) {
        // Zero-assignment runs are only logged when something noteworthy happened, to keep the log readable.
        Boolean noteworthy = status != 'Success' || (summary != null && (summary.processed > 0 || summary.onHold > 0)) || !messages.isEmpty();
        if (!noteworthy) {
            return;
        }
        Database.insert(
            DE_RunLogger.build(
                'Scheduler',
                status,
                summary == null ? 0 : summary.processed,
                summary == null ? 0 : summary.assigned,
                summary == null ? (status == 'Error' ? 1 : 0) : summary.errors,
                messages.isEmpty() ? null : String.join(messages, '\n'),
                started,
                System.now().getTime() - started.getTime(),
                jobId
            ),
            false,
            AccessLevel.SYSTEM_MODE
        );
    }

    private static void enqueueNext(Id resume) {
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return;
        }
        AsyncOptions options = new AsyncOptions();
        options.MinimumQueueableDelayInMinutes = resume != null ? 0 : DE_Settings.schedulerIntervalMinutes();
        System.enqueueJob(new DE_SchedulerJob(resume, true), options);
    }

    /** True when a scheduler job is queued, holding or running. */
    public static Boolean isRunning() {
        return [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'DE_SchedulerJob' AND JobType = 'Queueable' AND Status IN ('Queued', 'Holding', 'Preparing', 'Processing')
            ] > 0;
    }

    /** Starts the chain unless it is already running. Returns true when a job was enqueued. */
    public static Boolean start() {
        if (isRunning()) {
            return false;
        }
        System.enqueueJob(new DE_SchedulerJob());
        return true;
    }

    /** Stops the chain by aborting queued scheduler jobs (a job already running finishes and re-enqueues only if the engine is enabled). */
    public static Integer stop() {
        Integer n = 0;
        for (AsyncApexJob j : [
            SELECT Id
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'DE_SchedulerJob' AND JobType = 'Queueable' AND Status IN ('Queued', 'Holding', 'Preparing')
        ]) {
            System.abortJob(j.Id);
            n++;
        }
        return n;
    }
}
