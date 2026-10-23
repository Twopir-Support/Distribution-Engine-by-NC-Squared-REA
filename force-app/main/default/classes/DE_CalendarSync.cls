/**
 * Calendar integration: Salesforce Events shown as "Out of Office" create Distribution Engine
 * out of office entries for their owner, so routing skips that user while they are away.
 */
public without sharing class DE_CalendarSync {
    public static final Integer MIN_MINUTES = 60;

    public static void createOutOfOffice(List<SObject> events) {
        List<DE_Out_Of_Office__c> entries = new List<DE_Out_Of_Office__c>();
        for (SObject e : events) {
            if (e.get('ShowAs') != 'OutOfOffice') {
                continue;
            }
            Id owner = (Id) e.get('OwnerId');
            Datetime startAt = (Datetime) e.get('StartDateTime');
            Datetime endAt = (Datetime) e.get('EndDateTime');
            if (owner == null || owner.getSobjectType() != User.SObjectType || startAt == null || endAt == null) {
                continue;
            }
            if ((endAt.getTime() - startAt.getTime()) / 60000 < MIN_MINUTES) {
                continue;
            }
            String subject = (String) e.get('Subject');
            entries.add(
                new DE_Out_Of_Office__c(
                    User__c = owner,
                    Start__c = startAt,
                    End__c = endAt,
                    All_Day__c = e.get('IsAllDayEvent') == true,
                    Reason__c = String.isBlank(subject) ? 'Calendar' : subject.left(80),
                    Source__c = 'Calendar'
                )
            );
        }
        if (!entries.isEmpty()) {
            Database.insert(entries, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
