/**
 * Health checker (hourly by default): restarts the scheduler chain if it has stopped and records
 * the outcome, and emails administrators about repeated failures (DE_AdminAlerts). Also runs daily
 * maintenance once per day: log purge, auto archive and dynamic team members.
 */
public without sharing class DE_HealthChecker implements Schedulable {
    public static final String JOB_NAME = 'Distribution Engine Health Checker';

    public void execute(SchedulableContext context) {
        check();
        try {
            DE_AdminAlerts.checkAll(System.now());
        } catch (Exception e) {
            DE_RunLogger.log('Health Checker', 'Error', 0, 0, 1, 'Admin alerts failed: ' + e.getMessage());
        }
        if (!dailyMaintenanceRanToday()) {
            Database.executeBatch(new DE_MaintenanceBatch(), 200);
        }
    }

    public static String check() {
        String message;
        String status = 'Success';
        if (!DE_Settings.engineEnabled()) {
            message = 'Engine is disabled in Distribution Settings.';
        } else if (DE_SchedulerJob.isRunning()) {
            message = 'Scheduler is running.';
        } else {
            DE_SchedulerJob.start();
            message = 'Scheduler was not running and has been restarted.';
            status = 'Warning';
            DE_AdminAlerts.send(DE_AdminAlerts.SCHEDULER_RESTARTED, 'The Distribution Engine scheduler had stopped. The health checker restarted it at ' + System.now().format() + '.');
        }
        DE_RunLogger.log('Health Checker', status, 0, 0, 0, message);
        return message;
    }

    private static Boolean dailyMaintenanceRanToday() {
        Datetime since = DE_ShiftCalendar.always(UserInfo.getTimeZone().getID()).localMidnight(System.now());
        return [SELECT COUNT() FROM DE_Run_Log__c WHERE Process__c = 'Purge' AND Started_At__c >= :since] > 0;
    }

    /** Schedules the health checker hourly (or every 15/30 minutes). */
    public static void schedule(Integer everyMinutes) {
        unschedule();
        Integer step = everyMinutes == null ? 60 : everyMinutes;
        if (step >= 60) {
            System.schedule(JOB_NAME, '0 7 * * * ?', new DE_HealthChecker());
            return;
        }
        for (Integer m = 7; m < 60; m += step) {
            System.schedule(JOB_NAME + ' :' + String.valueOf(m).leftPad(2, '0'), '0 ' + m + ' * * * ?', new DE_HealthChecker());
        }
    }

    public static void unschedule() {
        String pattern = JOB_NAME + '%';
        for (CronTrigger c : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern]) {
            System.abortJob(c.Id);
        }
    }

    public static Boolean isScheduled() {
        String pattern = JOB_NAME + '%';
        return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern] > 0;
    }
}
