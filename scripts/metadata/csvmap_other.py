"""Mapping for non-object metadata: Apex classes (rule based), VF pages/components, LWC, Aura, flows and the rest."""
import re

# ---------------------------------------------------------------- Apex: ordered rules (regex, area, targets, kind, note)
# kind: impl (equivalent implemented / planned target), blocked, na, test
APEX_RULES = [
    (r'Slack|Heroku|IntegrationsMiddleware|MrkdwnEscape|^Integrations|HmacVerifier', 'Slack integration', [], 'blocked',
     'Needs the vendor Slack app, OAuth tokens and middleware endpoint; not reproducible by an independent build.'),
    (r'FeatureParam|FeatureUsage|^Licen|License|Licence|LicensedUser|Tier|PostInstall|UpgradeExecutor|UpgradeBatch|IUpgradeExecutor', 'Licensing / ISV telemetry / package upgrades', [], 'na',
     'Managed-package licensing, LMA feature parameters and version upgrade scripts; not applicable to an unmanaged independent build.'),
    (r'TargetedMessage|InAppMessage|DisplayCriteria', 'Vendor in-app messaging', [], 'na', 'Vendor in-app marketing/onboarding messages.'),
    (r'SupportSettings|SupportEmail|AbstractSupportEmailBuilder|ISupportEmailBuilder', 'Vendor support', [], 'na', 'Sends diagnostics to the vendor support team.'),
    (r'^(Export|Import)(Teams|Tags|TerritoryMaps)|Settings_ExportImport|TeamsMigration|TagsMigration|TerritoryMapsMigration|TerritoryMapMigration|TeamMigrationVO|GenericMigration|^Migration|MultiMigration|IMigrationOperation|ImportTagsValidation|ImportTeamsValidation|ImportTerritoryMapsValidation',
     'Configuration export/import', ['cls:DE_ConfigTransfer', 'cls:DE_SettingsController'], 'impl', 'JSON export/import of teams, tags and territories.'),
    (r'DataMigration|ScheduledDataMigration|NoOpDataMigrationJob|IDataMigrationJobCreator|RollbackExecutor', 'Package data migrations', [], 'na', 'Internal data migrations between package versions.'),
    (r'Persona|^Profile|ProfileHistory|UserProfile|Settings_CustomPermissions|PermissionsUIVO|CommonPermissionUtils|HousekeepingDeleteDEProfiles',
     'Personas and permissions', ['cls:DE_PersonaService', 'cls:DE_Permissions'], 'impl', 'Personas map users to capability sets on top of the four permission sets.'),
    (r'ShiftPlanner|CloneShiftPlannerTask|TeamMemberShiftBlocks|HousekeepingShiftPlanner', 'Shift planner', ['cls:DE_ShiftPlannerService', 'lwc:deShiftPlanner'], 'impl', ''),
    (r'SalesforceTeam|UserAccountTeamMemberVO|UserOpportunityTeamMemberVO|DefaultSalesforceTeamMemberVO', 'Salesforce team (role) assignment',
     ['cls:DE_SalesforceTeamService'], 'impl', 'Adds the assignee to the Account/Opportunity/Case team with a role.'),
    (r'RecordHistoryUtility|HistoryComponentController', 'Record history (inline)', ['cls:DE_RecordDetailController', 'lwc:deRecordHistoryComponent'], 'impl', ''),
    (r'AutoConversionHistory', 'Auto conversion logs', ['cls:DE_ClassifierLogs', 'DE_Conversion_Log__c'], 'impl', ''),
    (r'CustomClassificationHistory', 'Custom classification logs', ['cls:DE_ClassifierLogs', 'DE_Classification_Log__c'], 'impl', ''),
    (r'History|IHistoryRecordTransformer', 'Change history', ['cls:DE_HistoryService', 'DE_History__c'], 'impl', 'Configuration change history.'),
    (r'Reject', 'Assignment rejection', ['cls:DE_RejectionService', 'DE_Reject_Request__c', 'lwc:deRejectComponent'], 'impl', ''),
    (r'OutOfBand', 'Out-of-band (manual/pull) assignment accounting', ['cls:DE_ManualAssignService', 'cls:DE_PullService'], 'impl', 'Manual and pull assignments are logged with Counts_As_Hit__c.'),
    (r'HolidayRegion|Holiday', 'Holidays', ['cls:DE_AvailabilityService', 'cls:DE_AvailabilityController', 'DE_Holiday_Region__c'], 'impl', ''),
    (r'OutOfOffice|CalendarResolver|CalendarIntegration', 'Out of office and calendar', ['cls:DE_AvailabilityController', 'cls:DE_CalendarSync'], 'impl', ''),
    (r'Calendar', 'Availability calendar', ['cls:DE_AvailabilityController'], 'impl', ''),
    (r'DistributionHours|ShiftHours|ShiftUIVO|WorkingHours|UnifiedShiftPeriod|TimezoneUtility|Availability_Shifts', 'Distribution hours and shifts', ['cls:DE_ShiftCalendar', 'cls:DE_AvailabilityController'], 'impl', ''),
    (r'CriteriaCap|TeamLevelCaps|TeamLevelFixed|FixedCapping|ICapping|ITeamLevelCapping|^Cap|Capping|TagCap|MultipleTeamLevelCaps', 'Caps', ['cls:DE_CapService', 'DE_Cap__c'], 'impl', ''),
    (r'Weighting|TagCombination', 'Weighting', ['cls:DE_RotationService', 'cls:DE_ConfigRepository'], 'impl', ''),
    (r'^Tag|^Tags|CollectionTagAssignment|SimpleUserTagAssignment|UserTagAssignment|GlobalAPITags|TeamDistributorTagUIVO', 'Tags', ['cls:DE_AvailabilityController', 'lwc:deTags', 'DE_Agent__c'], 'impl', ''),
    (r'Territor|ClsCleanTerritoryData|ClsTerritory', 'Territory classification', ['cls:DE_TerritoryClassifier', 'cls:DE_ClassifierController', 'DE_Territory_Log__c'], 'impl', ''),
    (r'AutoConversion|ClsAutoConversion|ClsDuplicateLead|ClsPostDedup|TestUtils_Conversion', 'Lead auto conversion and de-duplication', ['cls:DE_LeadConversion', 'DE_Conversion_Log__c'], 'impl', ''),
    (r'LeadMatching|ClsMatch|^Match|MatchLog|MatchSettings|ClassifierMatch|ApiClassifierMatch|ClassifierTieBreaker|^Domain|DomainUtils|DomainProcessor', 'Lead matching',
     ['cls:DE_LeadMatcher', 'cls:DE_TextMatch', 'DE_Matching_Log__c', 'DE_Account_Domain__c'], 'impl', ''),
    (r'CustomClassification|ClsCustomClassification|^Stamp|StampGroup|StampUsage|HousekeepingCleanDeletedStamps|HousekeepingDeleteStampGroups', 'Custom classification (stamps)',
     ['cls:DE_StampClassifier', 'DE_Classification_Log__c'], 'impl', ''),
    (r'Backfill', 'Classifier backfill', ['cls:DE_BackfillBatch', 'cls:DE_ClassifierController'], 'impl', ''),
    (r'ClassificationFailures|ClassifierFailureChecker|ClassifierMatchFailureEmail', 'Classifier failure alerts', ['cls:DE_AdminAlerts'], 'impl', 'Admin email when classification keeps failing.'),
    (r'Classif|^Cls|ApiClassifier|TriggerCls|GlobalAPIClassifier|DataPrepJobStatus|ProcessingFilterUIVO', 'Classifier framework',
     ['cls:DE_ClassifierService', 'cls:DE_ClassifierJob', 'cls:DE_ClassifierController', 'lwc:deClassifier'], 'impl', ''),
    (r'ObjectSyncLog|CompleteObjectSyncLogsTask', 'Object sync logs', ['cls:DE_ObjectSyncService', 'DE_Object_Sync_Log__c'], 'impl', ''),
    (r'ObjectSync', 'Object sync', ['cls:DE_ObjectSyncService', 'lwc:deObjectSync'], 'impl', ''),
    (r'Archive|TriggerDeArchive', 'Auto archive', ['cls:DE_ArchiveService', 'cls:DE_MaintenanceBatch'], 'impl', ''),
    (r'AssignmentSimulation|Simulat|TestToolComponent|DistributorTestTool|PreviewDistribution|CapTestResultVO', 'Assignment simulator and test tool',
     ['cls:DE_Simulator', 'lwc:deSimulator', 'lwc:deTestToolComponent'], 'impl', ''),
    (r'^AppAnalytics', 'Usage analytics', [], 'na', 'Vendor product-usage analytics.'),
    (r'Analytics|TeamPerformance', 'Analytics and team performance', ['cls:DE_ConsoleController', 'lwc:deAnalytics'], 'impl', ''),
    (r'HealthChecker|ParallelMode|DistributionLimitsMonitor|IDistributionLimitsMonitor|MaintenanceMode', 'Health checker and monitoring',
     ['cls:DE_HealthChecker', 'cls:DE_SchedulerJob', 'cls:DE_AdminAlerts'], 'impl', ''),
    (r'FailureEmail|ErrorsEmailBuilder|ErrorChecker|FailureChecker|ExceptionNotificationEmail|WarningEmailBuilder|LimitEmailBuilder|^ErrorIssue|ErrorEntry|ErrorUtils',
     'Admin failure notifications', ['cls:DE_AdminAlerts', 'cls:DE_RunLogger'], 'impl', ''),
    (r'Console_|AppMonitoring|SchedulerLog|^Scheduler|AsyncApexJob|JobStatusUIVO|AppStatusUIVO|DistributionStatusUIVO|^Logs_Scheduler', 'Console and scheduler',
     ['cls:DE_ConsoleController', 'cls:DE_SchedulerJob', 'lwc:deConsole'], 'impl', ''),
    (r'Housekeep', 'Housekeeping', ['cls:DE_MaintenanceBatch'], 'impl', 'Log retention, OOO clean-up, sticky clean-up.'),
    (r'ChainedQueueable|EndMarkerTask|LogsQueueable', 'Async chaining', ['cls:DE_SchedulerJob'], 'impl', ''),
    (r'TriggerDistribut|ApiTriggerDistribution|TriggerEnabledObject|TriggerSettingsUtils|TriggerPendingAssignment|Settings_TriggerDistr', 'Trigger distribution',
     ['cls:DE_TriggerDistribution', 'cls:DE_SettingsController'], 'impl', ''),
    (r'TriggerActionTracking|TriggerAutoAction|ActionTracking|TeamTrackingUIVO', 'Action tracking', ['cls:DE_ActionTracking'], 'impl', ''),
    (r'AutoReassign|DistributionLogsAlertProcessor|TeamSLA|DistributorSLAs|TriggerAutoReassign', 'SLAs and auto reassign', ['cls:DE_SlaService', 'DE_SLA__c'], 'impl', ''),
    (r'^Trigger', 'Trigger framework', ['cls:DE_TriggerHandler'], 'impl', ''),
    (r'Pull', 'Pull distribution', ['cls:DE_PullService', 'cls:DE_WidgetController'], 'impl', ''),
    (r'Manual', 'Manual distribution', ['cls:DE_ManualAssignService', 'lwc:deManualAssignment'], 'impl', ''),
    (r'DynamicTeamMember|DynamicTM|NewDynamicTeamMember', 'Dynamic team members', ['cls:DE_DynamicMembers'], 'impl', ''),
    (r'^Logs_|DistributionLog|RecentDistributionLog|InlineLogs|LogsSortOrder|ArchiveLogUI', 'Distribution logs UI', ['cls:DE_ConsoleController', 'lwc:deLogs'], 'impl', ''),
    (r'^Widget|LightningWidget|UserToggle|EndOfShiftToggle|UserAvailabilitySettings|UserActivityDAO|^Availability_|AvailableTeamsUIVO|TeamMemberStatusUIVO',
     'Widget and availability toggle', ['cls:DE_WidgetController', 'cls:DE_AgentService', 'lwc:deWidget'], 'impl', ''),
    (r'InlineComponent|RecordDetailsComponent', 'Record inline component', ['cls:DE_RecordDetailController', 'lwc:deInlineComponent'], 'impl', ''),
    (r'EmailNotification|EmailBuilder|EmailStyling|EmailResponses|HtmlUtils|EmailApexJobTables', 'Email notifications', ['cls:DE_Notifier', 'flow:DE_Email_Notification_on_new_log'], 'impl', ''),
    (r'DistributionEngineGlobal|GlobalAPI', 'Global API', ['cls:DE_Api', 'cls:DE_FlowActions'], 'impl', ''),
    (r'CacheUtils|UserProfileCache', 'Platform cache', ['cls:DE_Cache'], 'impl', 'Org cache partition "DE" with a transaction fallback.'),
    (r'CommonLock|LockUtils', 'Locking', ['cls:DE_TeamLock'], 'impl', ''),
    (r'CommonEventBus|ICommonEventBus|TriggerDistributionEvent|AsyncDistribution', 'Events', ['cls:DE_Notifier', 'DE_Assignment_Event__e'], 'impl', ''),
    (r'CommonLog|CommonExceptionHandler|CommonExceptions|CommonUIExceptions|ExceptionVO', 'Logging and exceptions', ['cls:DE_RunLogger', 'cls:DE_Ui'], 'impl', ''),
    (r'CommonTier|CommonFeatureParam', 'Licensing helpers', [], 'na', 'Tier and feature-parameter helpers.'),
    (r'^Common|Pair$|FieldOption|SelectOption|SerialisableSelectOption|BasicSObjectUIVO|DurationUIVO|ValidationErrorVO|GenericValidationVO|StageProcessingResult|JobSettingUtil|AppSettingUtils|AppSettingsUIVO|AdvancedSettingsUIVO|UserSettingsUtils|SObjectUIUtils|OrgUIDAO|QueueDAO|QueueUIDAO|QueueUIVO|UserDAO|UserUIDAO|UserUIUtils|UserUIVO|UserUtils|UserConstants|UserOrQueueWithTeams|UserManagerFilter|CampaignUIDAO|LinkedObjectFilterUIVO|SourceUIDAO|SourceDetails|ProfileConstants|ReliabilityHelper|RuntimeUtility',
     'Shared utilities and settings', ['cls:DE_Schema', 'cls:DE_Ids', 'cls:DE_Ui', 'cls:DE_Settings', 'cls:DE_SettingsController', 'cls:DE_AdminController'], 'impl', ''),
    (r'^Settings_', 'Settings pages', ['cls:DE_SettingsController', 'lwc:deSettings'], 'impl', ''),
    (r'LookupOwner|SortOrders|FieldsToUpdate|FilterComparison|LogicAndFilters|RecordCountMatcher|RecordOwnerCount|LastAssignee|StuckRecords|DistributionSequence|DistributorCounters|PreventOverflow|IPreventOverflow',
     'Distribution engine internals', ['cls:DE_DistributionCore', 'cls:DE_Conditions', 'cls:DE_Logic', 'cls:DE_FieldUpdates', 'cls:DE_OwnerResolver', 'cls:DE_RotationService'], 'impl', ''),
    (r'Distribut|BatchDistribution|IBatchDistribution|GenericDistribution|IPullDistribution|IManualDistribution|ISimulatedDistribution|ITriggerDistribution|SchedulerDetails|AssignmentDetailVO|DistributorSoqlVO',
     'Distribution engine', ['cls:DE_DistributionRunner', 'cls:DE_DistributionCore', 'cls:DE_AssignmentWriter', 'cls:DE_RecordQuery', 'cls:DE_AdminController', 'lwc:deDistributorEditor'], 'impl', ''),
    (r'^APV', 'Assignment process view', ['cls:DE_AdminController', 'lwc:deTeamWorkspace'], 'impl', 'Distribution process view per team.'),
    (r'^Team_|^Team|TeamManager|TeamHoliday|TeamFeatures|TeamObjectSync|TeamCaps|TeamWeighting', 'Teams and members UI/services',
     ['cls:DE_AdminController', 'cls:DE_ConfigRepository', 'lwc:deTeams', 'lwc:deTeamWorkspace', 'lwc:deTeamMembers'], 'impl', ''),
    (r'^Base_Controller|^Settings_BaseSettings|^Logs_BaseLogs|PageContext|ApplicationContext', 'VF controller base classes', ['cls:DE_Ui'], 'impl', 'LWC + Apex controllers replace the VF base controllers.'),
    (r'^Mock|^TestUtils|^Test|MockingHelper|CaptureMethodCallsMock|PassThrough|TestFinalizerContext|TestContext', 'Test infrastructure', ['cls:DE_TestFactory'], 'test', 'Test data builders and mocks.'),
    (r'^Distributor$|^ClassifierConstants|^DistributionConstants|^MigrationConstants|ClassificationMode|ClassificationType', 'Engine constants', ['cls:DE_Model', 'cls:DE_Settings'], 'impl', ''),
    (r'.*', 'Unclassified', [], 'investigate', 'Purpose not established from available evidence.'),
]

TEST_SUFFIX = re.compile(r'(_Tests?|Tests?)$')


def classify_apex(name):
    base = TEST_SUFFIX.sub('', name)
    is_test = bool(TEST_SUFFIX.search(name)) and name != base
    for rx, area, targets, kind, note in APEX_RULES:
        if re.search(rx, base):
            if is_test and kind == 'impl':
                return area, targets, 'test', 'Test class for: ' + base + '. Equivalent tests cover the target classes.'
            return area, targets, kind, note
    return 'Unclassified', [], 'investigate', ''


# ---------------------------------------------------------------- VF pages -> LWC
VF_PAGES = {
    'AssignmentSimulation_Results': ['lwc:deSimulator'], 'Availability_Holidays': ['lwc:deAvailability'], 'Analytics_Distribution': ['lwc:deAnalytics'],
    'Cls_AutoConversionSettings': ['lwc:deClassifier'], 'Cls_Backfill': ['lwc:deClassifier'], 'Availability_OutOfOffice': ['lwc:deAvailability'],
    'Availability_Shifts': ['lwc:deAvailability'], 'Cls_LeadMatchingObject': ['lwc:deClassifier'], 'Settings_TriggerDistributorsSettings': ['lwc:deSettings'],
    'Cls_LeadMatchingSettings': ['lwc:deClassifier'], 'SupportSettings': 'na:Vendor support diagnostics page.', 'Cls_CustomClassificationSettings': ['lwc:deClassifier'],
    'Settings_PersonaManagement': ['lwc:dePersonas'], 'Cls_DelayFilters': ['lwc:deDistributorEditor'], 'Settings_TierReduction': 'na:Licence tier management.',
    'Settings_AppSettings': ['lwc:deSettings'], 'Settings_CustomPermissions': ['lwc:dePersonas'], 'Profile_PermissionDenied': ['lwc:deUtils'],
    'Settings_AdvancedSettings': ['lwc:deSettings'], 'Settings_LicensedUsers': 'na:Licence seat assignment.', 'Settings_PersonaAssignment': ['lwc:dePersonas'],
    'Settings_ExportImport': ['lwc:deSettings'], 'Settings_Integrations': 'blocked:Slack integration settings.', 'InlineCaseLogs': ['lwc:deInlineComponent'],
    'Team_TeamPerformance': ['lwc:deAnalytics'], 'InlineContactLogs': ['lwc:deInlineComponent'], 'Team_TeamSettings': ['lwc:deTeamWorkspace'],
    'Console_TodaysDistributionList': ['lwc:deConsole'], 'Team_TeamList': ['lwc:deTeams'], 'InlineAccountLogs': ['lwc:deInlineComponent'],
    'Team_TeamMemberList': ['lwc:deTeamMembers'], 'Logs_ArchiveLogList': ['lwc:deLogs'], 'Team_WeightingAndCaps': ['lwc:deTeamWorkspace'],
    'Logs_AutoConversionLogList': ['lwc:deLogs'], 'Widget': ['lwc:deWidget'], 'InlineLeadLogs': ['lwc:deInlineComponent'], 'Team_TeamSummary': ['lwc:deTeamWorkspace'],
    'InlineOpportunityLogs': ['lwc:deInlineComponent'], 'Team_TrackingAndSlas': ['lwc:deTeamWorkspace'], 'Logs_LeadMatchingLogList': ['lwc:deLogs'],
    'Logs_ObjectSyncLogList': ['lwc:deLogs'], 'Logs_CustomClassificationLogList': ['lwc:deLogs'], 'Logs_DistributionLogList': ['lwc:deLogs'],
    'ObjectSync_Actions': ['lwc:deObjectSync'], 'ObjectSync_Settings': ['lwc:deObjectSync'], 'Logs_SchedulerLogList': ['lwc:deLogs'],
    'Logs_TerritoriesLogList': ['lwc:deLogs'], 'Cls_TerritoryMapEdit': ['lwc:deClassifier'], 'Tags_TagValueList': ['lwc:deTags'], 'Cls_TerritoryMapList': ['lwc:deClassifier'],
    'Team_AssignmentRejection': ['lwc:deTeamWorkspace'], 'Cls_StampGroupList': ['lwc:deClassifier'], 'Tags_TagAssignmentList': ['lwc:deTags'], 'Cls_StampList': ['lwc:deClassifier'],
    'Tags_TagCollectionList': ['lwc:deTags'], 'Cls_TerritorySettings': ['lwc:deClassifier'], 'Console_ApplicationMonitoring': ['lwc:deConsole'],
    'Cls_TerritoryObjectEdit': ['lwc:deClassifier'], 'Team_Availability': ['lwc:deTeamWorkspace'], 'Cls_TerritoryObjectList': ['lwc:deClassifier'],
    'Team_DistributionHours': ['lwc:deWorkingHoursDetail'], 'Console_Calendar': ['lwc:deAvailability'], 'Team_DistributorSettings': ['lwc:deDistributorEditor'],
    'Console_SourceList': ['lwc:deConsole'], 'Team_PostAssignment': ['lwc:deDistributorEditor'], 'Team_DistributorList': ['lwc:deTeamWorkspace'],
}

VF_COMPONENTS = {
    'EmailNotification': ['cmp:DE_EmailNotification'], 'EmailNotificationLink': ['cmp:DE_EmailNotificationLink'],
    'EmailNotificationFooter': ['cmp:DE_EmailNotificationFooter'], 'EmailNotificationLogo': 'na:Vendor logo in emails.',
    'HistoryTable': ['lwc:deRecordHistoryComponent'], 'InlineLogs': ['lwc:deRecordHistoryComponent'], 'InlineLogs2': ['lwc:deRecordHistoryComponent'],
    'LogsContext': ['lwc:deLogs'], 'PageContext': ['lwc:deUtils'], 'PageHead': ['lwc:deUtils'], 'Team_TeamBase': ['lwc:deTeamWorkspace'],
    'APVHead': ['lwc:deTeamWorkspace'], 'CommonHeader': ['lwc:deUtils'], 'CommonHelp': ['lwc:deUtils'], 'CommonInlineHelp': ['lwc:deUtils'],
    'CommonMask': ['lwc:deUtils'], 'CommonSavedMask': ['lwc:deUtils'], 'GetPageReference': ['lwc:deUtils'], 'WidgetMask': ['lwc:deWidget'],
    'ApplicationContext': ['lwc:deUtils'], 'AssignmentReject': ['lwc:deRejectComponent'],
}

LWC = {
    'myAssignmentsUtils': ['lwc:deUtils'], 'filtersTable': ['lwc:deConditionBuilder'], 'rejectOptions': ['lwc:deRejectOptions'], 'basePopover': ['lwc:deBasePopover'],
    'baseComponent': ['lwc:deUtils'], 'deInlineComponent': ['lwc:deInlineComponent'], 'deAssignedToMe': ['lwc:deAssignedToMe'],
    'deRecordHistoryComponent': ['lwc:deRecordHistoryComponent'], 'deManualAssignment': ['lwc:deManualAssignment'], 'deTestToolComponent': ['lwc:deTestToolComponent'],
    'deRejectComponent': ['lwc:deRejectComponent'], 'deWidget': ['lwc:deWidget'], 'deTimerToggleComponent': ['lwc:deTimerToggleComponent'],
    'svgProvider': 'na:Vendor SVG sprite; lightning-icon and SLDS icons are used.', 'teamMembers': ['lwc:deTeamMembers'],
    'teamMemberDetail': ['lwc:deTeamMemberDetail'], 'workingHoursDetail': ['lwc:deWorkingHoursDetail'], 'teamMembersTable': ['lwc:deTeamMembersTable'],
}

AURA = {
    'rejectlogapp': ['lwc:deRejectComponent'], 'testtoolapp': ['lwc:deTestToolComponent'], 'widgetWrapper': ['lwc:deWidget'],
}

FLOWS = {
    'ProcessAsyncDistributionEvent': ['cls:DE_SchedulerJob'],
    'DE_Slack_Update_on_new_log': 'blocked:Slack integration.',
    'DE_Slack_Update_Flow': 'blocked:Slack integration.',
    'DE_Email_Team_Role_Notification_on_log_update': ['flow:DE_Email_Team_Role_Notification_on_log_update'],
    'DE_Email_Notification_on_new_log': ['flow:DE_Email_Notification_on_new_log'],
    'DE_Email_Team_Role_Notification_on_new_log': ['flow:DE_Email_Team_Role_Notification_on_new_log'],
    'DE_Email_Notification_on_log_update': ['flow:DE_Email_Notification_on_log_update'],
}

TRIGGERS = {
    'DEAccountTrigger': ['trigger:DE_AccountTrigger'], 'DECaseTrigger': ['trigger:DE_CaseTrigger'], 'DEContactTrigger': ['trigger:DE_ContactTrigger'],
    'DETaskTrigger': ['trigger:DE_TaskTrigger'], 'DEDistributionLogTrigger': ['cls:DE_AssignmentWriter', 'flow:DE_Email_Notification_on_new_log', 'flow:DE_Email_Notification_on_log_update'], 'DEEventTrigger': ['trigger:DE_EventTrigger'],
    'DELeadTrigger': ['trigger:DE_LeadTrigger'], 'DEOpportunityTrigger': ['trigger:DE_OpportunityTrigger'],
}

TABS = {
    'Distribution Analytics': ['tab:DE_Analytics'], 'Distribution Console': ['tab:DE_Console'], 'Distribution Sync': ['tab:DE_Sync'],
    'Distribution Logs': ['tab:DE_Logs'], 'Distribution Tags': ['tab:DE_Tags'], 'Record Classification': ['tab:DE_Classifier'],
    'Distribution Settings': ['tab:DE_Settings'], 'Distribution Availability': ['tab:DE_Availability'], 'Distribution Team': ['tab:DE_Teams'],
}

PERMSETS = {
    'Distribution_Engine_Admin': ['permset:DE_Admin'], 'Distribution_Engine_Manager': ['permset:DE_System_Manager'],
    'Distribution_Engine_Team_Manager': ['permset:DE_Team_Manager'], 'Distribution_Engine_User': ['permset:DE_User'],
    'Distribution_Engine_Custom_Team_Manager': ['permset:DE_Custom_Team_Manager'], 'Distribution_Engine_Community_User': ['permset:DE_Community_User'],
    'Distribution_Engine_Slack_Integration': 'blocked:Slack integration.',
}

REPORTS = {
    'Distribution logs by team': ['report:DE_Reports/DE_Distributions_by_Team'],
    'Rejected DE assignments by day': ['report:DE_Reports/DE_Rejections_by_Day'],
    'Total Distribution Volumes': ['report:DE_Reports/DE_Distributions_by_Day'],
    'User Activity History': ['report:DE_Reports/DE_User_Availability_History'],
}

MISC = {
    ('Dashboard', 'Distribution Engine Dashboard'): ['dashboard:DE_Dashboards/DE_Distribution_Engine_Overview'],
    ('Custom Report Type', 'DE Rejected Assignments'): ['reporttype:DE_Rejected_Assignments'],
    ('Report Folder', 'Distribution Engine Reports'): ['reportfolder:DE_Reports'],
    ('Dashboard Folder', 'Distribution Engine Dashboards'): ['dashboardfolder:DE_Dashboards'],
    ('App', 'Distribution_Engine'): ['app:DE_Distribution_Engine'],
    ('List View', 'All'): ['listview:DE_Team__c.All'],
    ('Compact Layout', 'Distribution_Engine_details'): ['compact:DE_Record_Detail__c.DE_Record_Detail'],
    ('Platform Cache Partition', 'de'): ['cache:DE'],
    ('Home Page Layout', 'DE Default'): ['flexipage:DE_Home'],
    ('Home Page Component', 'Distribution Engine Widget'): ['flexipage:DE_Home'],
    ('Home Page Component', 'Distribution Engine'): ['flexipage:DE_Home'],
    ('Prompt', 'analyticsGuidance'): 'na:Undocumented vendor in-app guidance prompt on the analytics page (no public evidence of its content).',
    ('Classic Email Template Folder', 'Distribution Engine Templates'): ['emailfolder:DE_Templates'],
    ('Classic Email Template', 'Distribution Engine Notification'): ['email:DE_Templates/DE_Notification'],
    ('Classic Email Template', 'Distribution Engine Notification v2'): ['email:DE_Templates/DE_Notification_v2'],
    ('Classic Email Template', 'Distribution Engine Role Notification'): ['email:DE_Templates/DE_Role_Notification'],
    ('Workflow Email Alert', 'Distribution Engine - Email Notification'): ['alert:DE_Assignment_Log__c.DE_Email_Notification'],
    ('Workflow Email Alert', 'Distribution Engine - Email Notification v2'): ['alert:DE_Assignment_Log__c.DE_Email_Notification_v2'],
    ('Workflow Email Alert', 'Distribution Engine - Email Notification Team Role'): ['alert:DE_Assignment_Log__c.DE_Email_Notification_Team_Role'],
    ('Workflow Rule', 'Distribution Engine Notification'): ['flow:DE_Email_Notification_on_new_log', 'flow:DE_Email_Notification_on_log_update'],
    ('Workflow Rule', 'Distribution Engine Team Role Notification'): ['flow:DE_Email_Team_Role_Notification_on_new_log', 'flow:DE_Email_Team_Role_Notification_on_log_update'],
    ('Document Folder', 'Distribution_engine'): 'na:Vendor branding images; SLDS icons are used.',
}

STATIC_RESOURCES = {
    'apv': 'na:Vendor JS/CSS bundle for the VF assignment process view; replaced by LWC.',
    'delogosvg': 'na:Vendor logo.',
    'dejs': 'na:Vendor JS library for VF pages; replaced by LWC.',
    'DEResources': 'na:Vendor CSS/images for VF pages; SLDS is used.',
    'DistributionEngineSF1Widget': ['lwc:deWidget'],
    'DistributionEngineSF1Console': ['lwc:deConsole'],
}
