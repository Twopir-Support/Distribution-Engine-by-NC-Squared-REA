/**
 * Typed accessor for the DE_Settings__c hierarchy setting. Every value has a documented default
 * so the engine behaves predictably in a fresh org where no setting record exists yet.
 */
public inherited sharing class DE_Settings {
    @TestVisible
    private static DE_Settings__c cached;

    public static final Set<String> DEFAULT_PERSONAL_DOMAINS = new Set<String>{
        'gmail.com',
        'googlemail.com',
        'yahoo.com',
        'yahoo.co.uk',
        'hotmail.com',
        'hotmail.co.uk',
        'outlook.com',
        'live.com',
        'msn.com',
        'aol.com',
        'icloud.com',
        'me.com',
        'mac.com',
        'protonmail.com',
        'proton.me',
        'gmx.com',
        'gmx.de',
        'mail.com',
        'yandex.com',
        'zoho.com',
        'qq.com',
        '163.com'
    };

    public static DE_Settings__c get() {
        if (cached == null) {
            cached = DE_Settings__c.getOrgDefaults();
            if (cached == null) {
                cached = new DE_Settings__c();
            }
        }
        return cached;
    }

    /** Test hook and admin save path: replace the cached values for this transaction. */
    public static void setForTransaction(DE_Settings__c s) {
        cached = s;
    }

    private static Boolean flag(Boolean value, Boolean defaultValue) {
        return value == null ? defaultValue : value;
    }

    private static Integer num(Decimal value, Integer defaultValue) {
        return value == null ? defaultValue : value.intValue();
    }

    private static List<String> splitList(String value, String defaultValue) {
        String v = String.isBlank(value) ? defaultValue : value;
        List<String> out = new List<String>();
        if (String.isBlank(v)) {
            return out;
        }
        for (String part : v.split('[,;\\n]')) {
            if (String.isNotBlank(part)) {
                out.add(part.trim());
            }
        }
        return out;
    }

    public static Boolean engineEnabled() {
        return flag(get().Engine_Enabled__c, true);
    }

    public static Integer schedulerIntervalMinutes() {
        Integer v = num(get().Scheduler_Interval_Minutes__c, 1);
        return Math.min(10, Math.max(1, v));
    }

    public static Integer recordsPerRun() {
        return Math.max(1, num(get().Records_Per_Run__c, 500));
    }

    public static Boolean classifierEnabled() {
        return flag(get().Classifier_Enabled__c, true);
    }

    public static Set<String> classifierObjects() {
        Set<String> out = new Set<String>();
        for (String s : splitList(get().Classifier_Objects__c, 'Lead,Case,Account,Contact,Opportunity')) {
            out.add(s.toLowerCase());
        }
        return out;
    }

    public static Boolean distributeAfterClassify() {
        return flag(get().Distribute_After_Classify__c, true);
    }

    public static Boolean triggerDistributionEnabled() {
        return flag(get().Trigger_Distribution_Enabled__c, true);
    }

    public static Integer previousAssigneesTracked() {
        return Math.min(50, Math.max(0, num(get().Previous_Assignees_Tracked__c, 1)));
    }

    public static Integer holdAfterFailures() {
        return Math.max(1, num(get().Hold_After_Failures__c, 10));
    }

    public static Integer holdMinutes() {
        return Math.max(1, num(get().Hold_Minutes__c, 60));
    }

    public static Integer logRetentionDays() {
        return Math.max(1, num(get().Log_Retention_Days__c, 30));
    }

    public static Boolean decisionTraceEnabled() {
        return flag(get().Decision_Trace_Enabled__c, true);
    }

    public static List<String> rejectReasons() {
        return splitList(get().Reject_Reasons__c, 'Not my territory,Duplicate,Insufficient information,Workload');
    }

    public static Boolean allowOtherRejectReason() {
        return flag(get().Allow_Other_Reject_Reason__c, true);
    }

    public static List<String> toggleReasons() {
        return splitList(get().Toggle_Reasons__c, 'Meeting,Break,Lunch,Training,End of shift');
    }

    public static Boolean requireToggleReason() {
        return flag(get().Require_Toggle_Reason__c, false);
    }

    public static List<Integer> timerDurations() {
        List<Integer> out = new List<Integer>();
        for (String s : splitList(get().Timer_Durations__c, '15,30,60,120')) {
            try {
                out.add(Integer.valueOf(s));
            } catch (Exception e) {
                continue;
            }
        }
        return out;
    }

    public static Boolean timerTogglesOnly() {
        return flag(get().Timer_Toggles_Only__c, false);
    }

    public static String toggleAtStartOfDay() {
        return String.isBlank(get().Toggle_At_Start_Of_Day__c) ? 'No Change' : get().Toggle_At_Start_Of_Day__c;
    }

    public static String toggleAtEndOfDay() {
        return String.isBlank(get().Toggle_At_End_Of_Day__c) ? 'No Change' : get().Toggle_At_End_Of_Day__c;
    }

    public static Set<String> personalDomains() {
        Set<String> out = new Set<String>(DEFAULT_PERSONAL_DOMAINS);
        for (String s : splitList(get().Personal_Domains__c, '')) {
            out.add(s.toLowerCase());
        }
        return out;
    }

    public static Boolean countPullAsHit() {
        return flag(get().Count_Pull_As_Hit__c, true);
    }

    public static Boolean countManualAsHit() {
        return flag(get().Count_Manual_As_Hit__c, false);
    }

    public static Boolean countStickyInBalance() {
        return flag(get().Count_Sticky_In_Balance__c, true);
    }

    public static Boolean countLookupInBalance() {
        return flag(get().Count_Lookup_In_Balance__c, true);
    }

    public static Boolean archiveEnabled() {
        return flag(get().Archive_Enabled__c, false);
    }

    public static Integer archiveAfterDays() {
        return Math.max(1, num(get().Archive_After_Days__c, 90));
    }

    public static String archiveQueueId() {
        return get().Archive_Queue_Id__c;
    }

    public static Boolean publishPlatformEvents() {
        return flag(get().Publish_Platform_Events__c, true);
    }

    public static Integer historyRetentionDays() {
        return Math.max(1, num(get().History_Retention_Days__c, 90));
    }

    public static Integer classifierLogRetentionDays() {
        return Math.max(1, num(get().Classifier_Log_Retention_Days__c, 30));
    }

    public static List<String> adminAlertEmails() {
        List<String> out = new List<String>();
        for (String s : splitList(get().Admin_Alert_Emails__c, '')) {
            if (s.contains('@')) {
                out.add(s);
            }
        }
        return out;
    }

    public static Integer failureAlertThreshold() {
        return Math.max(1, num(get().Failure_Alert_Threshold__c, 5));
    }

    public static Boolean usePlatformCache() {
        return flag(get().Use_Platform_Cache__c, true);
    }

    /** 1 = Monday ... 7 = Sunday. */
    public static Integer weekStartDay() {
        return 'sunday'.equalsIgnoreCase(get().Default_Weekday_Start__c) ? 7 : 1;
    }
}
