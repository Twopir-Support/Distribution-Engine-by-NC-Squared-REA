/**
 * Assignment and SLA notifications: Salesforce in-app notifications (custom notification type
 * DE_Assignment), optional email, and DE_Assignment_Event__e platform events for real-time widgets.
 * Notification failures never roll back an assignment.
 */
public without sharing class DE_Notifier {
    private static Id notificationTypeId;
    private static Boolean typeLoaded = false;

    private static Id typeId() {
        if (!typeLoaded) {
            typeLoaded = true;
            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'DE_Assignment' LIMIT 1];
            notificationTypeId = types.isEmpty() ? null : types[0].Id;
        }
        return notificationTypeId;
    }

    public class Item {
        public Id recipientId;
        public Id targetId;
        public String title;
        public String body;
        public Boolean email = false;
        public Item(Id recipientId, Id targetId, String title, String body) {
            this.recipientId = recipientId;
            this.targetId = targetId;
            this.title = title;
            this.body = body;
        }
    }

    /** Sends grouped in-app notifications (one per recipient) and individual emails. */
    public static void send(List<Item> items) {
        if (items == null || items.isEmpty()) {
            return;
        }
        Map<Id, List<Item>> byRecipient = new Map<Id, List<Item>>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        for (Item i : items) {
            if (i.recipientId == null || i.recipientId.getSobjectType() != User.SObjectType) {
                continue;
            }
            if (!byRecipient.containsKey(i.recipientId)) {
                byRecipient.put(i.recipientId, new List<Item>());
            }
            byRecipient.get(i.recipientId).add(i);
            if (i.email) {
                Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
                m.setTargetObjectId(i.recipientId);
                m.setSaveAsActivity(false);
                m.setSubject(i.title);
                m.setPlainTextBody(i.body + '\n\n' + URL.getOrgDomainUrl().toExternalForm() + '/' + i.targetId);
                emails.add(m);
            }
        }
        Id typeId = typeId();
        if (typeId != null) {
            for (Id recipient : byRecipient.keySet()) {
                List<Item> mine = byRecipient.get(recipient);
                try {
                    Messaging.CustomNotification n = new Messaging.CustomNotification();
                    n.setNotificationTypeId(typeId);
                    n.setTargetId(mine[0].targetId);
                    n.setTitle(mine.size() == 1 ? mine[0].title : mine.size() + ' new Distribution Engine notifications');
                    n.setBody(mine.size() == 1 ? mine[0].body : mine[0].body + ' (and ' + (mine.size() - 1) + ' more)');
                    n.send(new Set<String>{ String.valueOf(recipient) });
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'DE notification failed: ' + e.getMessage());
                }
            }
        }
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'DE email failed: ' + e.getMessage());
            }
        }
    }

    public static void publish(List<DE_Assignment_Event__e> events) {
        if (events == null || events.isEmpty() || !DE_Settings.publishPlatformEvents()) {
            return;
        }
        for (Database.SaveResult r : EventBus.publish(events)) {
            if (!r.isSuccess()) {
                System.debug(LoggingLevel.WARN, 'DE platform event failed: ' + r.getErrors());
            }
        }
    }
}
