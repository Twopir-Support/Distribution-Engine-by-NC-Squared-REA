/**
 * Calendar integration: Salesforce Events shown as "Out of Office" create Distribution Engine
 * out of office entries for their owner, so routing skips that user while they are away.
 * Each entry keeps the Event Id (Activity_Id__c); editing the Event updates the entry and deleting
 * it (or no longer showing it as Out of Office) removes the entry.
 */
public without sharing class DE_CalendarSync {
    public static final Integer MIN_MINUTES = 60;

    public static void createOutOfOffice(List<SObject> events) {
        List<DE_Out_Of_Office__c> entries = new List<DE_Out_Of_Office__c>();
        Map<Id, String> zones = ownerTimezones(events);
        for (SObject e : events) {
            DE_Out_Of_Office__c o = entryFor(e, zones);
            if (o != null) {
                entries.add(o);
            }
        }
        if (!entries.isEmpty()) {
            Database.insert(entries, false, AccessLevel.SYSTEM_MODE);
        }
    }

    /** Event after update / after delete: keep the linked out of office entries in step. */
    public static void onEventChange(List<SObject> newEvents, Map<Id, SObject> oldMap, Boolean isDelete) {
        if (DE_TriggerHandler.bypass || !DE_Settings.engineEnabled()) {
            return;
        }
        Set<String> eventIds = new Set<String>();
        for (Id i : oldMap.keySet()) {
            eventIds.add(String.valueOf(i));
        }
        Map<String, DE_Out_Of_Office__c> existing = new Map<String, DE_Out_Of_Office__c>();
        for (DE_Out_Of_Office__c o : [SELECT Id, Activity_Id__c FROM DE_Out_Of_Office__c WHERE Activity_Id__c IN :eventIds AND Source__c = 'Calendar']) {
            existing.put(o.Activity_Id__c, o);
        }
        if (isDelete) {
            Database.delete(existing.values(), false, AccessLevel.SYSTEM_MODE);
            return;
        }
        Map<Id, String> zones = ownerTimezones(newEvents);
        List<DE_Out_Of_Office__c> upserts = new List<DE_Out_Of_Office__c>();
        List<DE_Out_Of_Office__c> deletes = new List<DE_Out_Of_Office__c>();
        for (SObject e : newEvents) {
            DE_Out_Of_Office__c current = existing.get(String.valueOf(e.Id));
            DE_Out_Of_Office__c wanted = entryFor(e, zones);
            if (wanted == null) {
                if (current != null) {
                    deletes.add(current);
                }
                continue;
            }
            if (current != null) {
                wanted.Id = current.Id;
            }
            upserts.add(wanted);
        }
        Database.delete(deletes, false, AccessLevel.SYSTEM_MODE);
        Database.upsert(upserts, false, AccessLevel.SYSTEM_MODE);
    }

    /** The out of office entry an Event should produce, or null when it should produce none. */
    @TestVisible
    private static DE_Out_Of_Office__c entryFor(SObject e, Map<Id, String> zones) {
        if (e.get('ShowAs') != 'OutOfOffice') {
            return null;
        }
        Id owner = (Id) e.get('OwnerId');
        Datetime startAt = (Datetime) e.get('StartDateTime');
        Datetime endAt = (Datetime) e.get('EndDateTime');
        if (owner == null || owner.getSobjectType() != User.SObjectType || startAt == null || endAt == null) {
            return null;
        }
        Boolean allDay = e.get('IsAllDayEvent') == true;
        String tz = zones.containsKey(owner) ? zones.get(owner) : UserInfo.getTimeZone().getID();
        if (allDay) {
            // All-day events are stored as midnight GMT dates; cover the whole local days in the owner's timezone.
            DE_ShiftCalendar cal = DE_ShiftCalendar.always(tz);
            startAt = Datetime.newInstance(cal.utcMs(startAt.dateGmt(), 0));
            endAt = Datetime.newInstance(cal.utcMs(endAt.dateGmt().addDays(1), 0));
        } else if ((endAt.getTime() - startAt.getTime()) / 60000 < MIN_MINUTES) {
            return null;
        }
        String subject = (String) e.get('Subject');
        return new DE_Out_Of_Office__c(
            User__c = owner,
            Start__c = startAt,
            End__c = endAt,
            All_Day__c = allDay,
            Timezone__c = tz,
            Activity_Id__c = e.Id,
            Reason__c = String.isBlank(subject) ? 'Calendar' : subject.left(80),
            Source__c = 'Calendar'
        );
    }

    private static Map<Id, String> ownerTimezones(List<SObject> events) {
        Set<Id> owners = new Set<Id>();
        for (SObject e : events) {
            Id owner = (Id) e.get('OwnerId');
            if (owner != null && owner.getSobjectType() == User.SObjectType) {
                owners.add(owner);
            }
        }
        Map<Id, String> out = new Map<Id, String>();
        for (User u : [SELECT Id, TimeZoneSidKey FROM User WHERE Id IN :owners]) {
            out.put(u.Id, u.TimeZoneSidKey);
        }
        return out;
    }
}
