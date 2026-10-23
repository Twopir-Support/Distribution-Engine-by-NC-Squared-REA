/**
 * Helpers for the text fields that hold a User or Queue Id.
 */
public inherited sharing class DE_Ids {
    public static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
    }

    public static Boolean isUser(Object value) {
        Id i = value instanceof Id ? (Id) value : toId(String.valueOf(value));
        return i != null && i.getSobjectType() == User.SObjectType;
    }

    public static Boolean isQueue(Object value) {
        Id i = value instanceof Id ? (Id) value : toId(String.valueOf(value));
        return i != null && i.getSobjectType() == Group.SObjectType;
    }

    public static Boolean isUserOrQueue(String value) {
        return isUser(value) || isQueue(value);
    }

    /** Splits a comma, semicolon or newline separated list of Ids. Invalid entries are dropped. */
    public static Set<Id> parseList(String value) {
        Set<Id> out = new Set<Id>();
        if (String.isBlank(value)) {
            return out;
        }
        for (String part : value.split('[,;\\s]+')) {
            Id i = toId(part);
            if (i != null) {
                out.add(i);
            }
        }
        return out;
    }

    /** Validates that a configured owner Id points at an existing active user or queue. */
    public static String ownerError(String value, Boolean allowQueue) {
        if (String.isBlank(value)) {
            return null;
        }
        Id i = toId(value);
        if (i == null) {
            return value + ' is not a valid Id.';
        }
        if (i.getSobjectType() == User.SObjectType) {
            List<User> users = [SELECT Id, IsActive FROM User WHERE Id = :i LIMIT 1];
            if (users.isEmpty() || !users[0].IsActive) {
                return 'User ' + value + ' does not exist or is inactive.';
            }
            return null;
        }
        if (i.getSobjectType() == Group.SObjectType && allowQueue) {
            List<Group> queues = [SELECT Id FROM Group WHERE Id = :i AND Type = 'Queue' LIMIT 1];
            return queues.isEmpty() ? 'Queue ' + value + ' does not exist.' : null;
        }
        return value + (allowQueue ? ' must be a User or Queue Id.' : ' must be a User Id.');
    }
}
