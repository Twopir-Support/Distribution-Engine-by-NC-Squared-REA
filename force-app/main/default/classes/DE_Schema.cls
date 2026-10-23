/**
 * Cached describe helpers. All metadata-driven routing (dynamic objects, fields and paths)
 * goes through this class so field names typed by administrators are validated before use.
 */
public inherited sharing class DE_Schema {
    private static final Map<String, Schema.DescribeSObjectResult> OBJECTS = new Map<String, Schema.DescribeSObjectResult>();
    private static final Map<String, Map<String, Schema.SObjectField>> FIELDS = new Map<String, Map<String, Schema.SObjectField>>();
    private static final Map<String, Map<String, Schema.SObjectField>> RELATIONSHIPS = new Map<String, Map<String, Schema.SObjectField>>();

    public class SchemaException extends Exception {
    }

    /** Returns the describe for an object, or null when it does not exist or is not accessible. */
    public static Schema.DescribeSObjectResult describe(String objectName) {
        if (String.isBlank(objectName)) {
            return null;
        }
        String key = objectName.trim().toLowerCase();
        if (!OBJECTS.containsKey(key)) {
            Schema.DescribeSObjectResult result = null;
            try {
                List<Schema.DescribeSObjectResult> results = Schema.describeSObjects(new List<String>{ objectName.trim() });
                if (!results.isEmpty()) {
                    result = results[0];
                }
            } catch (Exception e) {
                result = null;
            }
            OBJECTS.put(key, result);
        }
        return OBJECTS.get(key);
    }

    public static Boolean objectExists(String objectName) {
        return describe(objectName) != null;
    }

    /** Canonical API name of an object (fixes case typed by the admin). */
    public static String objectName(String objectName) {
        Schema.DescribeSObjectResult d = describe(objectName);
        return d == null ? objectName : d.getName();
    }

    public static Map<String, Schema.SObjectField> fields(String objectName) {
        String key = objectName.trim().toLowerCase();
        if (!FIELDS.containsKey(key)) {
            Schema.DescribeSObjectResult d = describe(objectName);
            if (d == null) {
                throw new SchemaException('Object ' + objectName + ' does not exist or is not accessible.');
            }
            Map<String, Schema.SObjectField> lower = new Map<String, Schema.SObjectField>();
            Map<String, Schema.SObjectField> rels = new Map<String, Schema.SObjectField>();
            for (Schema.SObjectField f : d.fields.getMap().values()) {
                Schema.DescribeFieldResult fd = f.getDescribe();
                lower.put(fd.getName().toLowerCase(), f);
                if (fd.getRelationshipName() != null) {
                    rels.put(fd.getRelationshipName().toLowerCase(), f);
                }
            }
            FIELDS.put(key, lower);
            RELATIONSHIPS.put(key, rels);
        }
        return FIELDS.get(key);
    }

    public static Boolean hasField(String objectName, String fieldName) {
        if (String.isBlank(fieldName) || !objectExists(objectName)) {
            return false;
        }
        return fields(objectName).containsKey(fieldName.trim().toLowerCase());
    }

    public static Schema.DescribeFieldResult field(String objectName, String fieldName) {
        if (!hasField(objectName, fieldName)) {
            return null;
        }
        return fields(objectName).get(fieldName.trim().toLowerCase()).getDescribe();
    }

    /**
     * Resolves a field path such as Account.Owner.Name to the describe of the final field.
     * Returns null when any part of the path does not exist.
     */
    public static Schema.DescribeFieldResult resolvePath(String objectName, String path) {
        if (String.isBlank(path) || !objectExists(objectName)) {
            return null;
        }
        List<String> parts = path.trim().split('\\.');
        if (parts.size() > 6) {
            return null;
        }
        String current = objectName;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            fields(current);
            Schema.SObjectField rel = RELATIONSHIPS.get(current.toLowerCase()).get(parts[i].toLowerCase());
            if (rel == null) {
                return null;
            }
            List<Schema.SObjectType> targets = rel.getDescribe().getReferenceTo();
            if (targets.isEmpty()) {
                return null;
            }
            current = targets[0].getDescribe().getName();
        }
        return field(current, parts[parts.size() - 1]);
    }

    /** Returns the path with each part in canonical case, or null if invalid. */
    public static String canonicalPath(String objectName, String path) {
        if (resolvePath(objectName, path) == null) {
            return null;
        }
        List<String> parts = path.trim().split('\\.');
        List<String> out = new List<String>();
        String current = objectName;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            Schema.SObjectField rel = RELATIONSHIPS.get(current.toLowerCase()).get(parts[i].toLowerCase());
            Schema.DescribeFieldResult rd = rel.getDescribe();
            out.add(rd.getRelationshipName());
            current = rd.getReferenceTo()[0].getDescribe().getName();
            fields(current);
        }
        out.add(field(current, parts[parts.size() - 1]).getName());
        return String.join(out, '.');
    }

    public static String nameField(String objectName) {
        for (Schema.SObjectField f : fields(objectName).values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.isNameField()) {
                return d.getName();
            }
        }
        return 'Id';
    }

    /** True when the field is a lookup that can hold a User Id. */
    public static Boolean isUserReference(String objectName, String fieldName) {
        Schema.DescribeFieldResult d = field(objectName, fieldName);
        if (d == null || d.getType() != Schema.DisplayType.REFERENCE) {
            return false;
        }
        for (Schema.SObjectType t : d.getReferenceTo()) {
            if (t == User.SObjectType) {
                return true;
            }
        }
        return false;
    }

    /** True when the object's OwnerId accepts queues. */
    public static Boolean supportsQueues(String objectName) {
        Schema.DescribeFieldResult d = field(objectName, 'OwnerId');
        if (d == null) {
            return false;
        }
        for (Schema.SObjectType t : d.getReferenceTo()) {
            if (t == Group.SObjectType) {
                return true;
            }
        }
        return false;
    }

    public static Schema.SObjectType sobjectType(String objectName) {
        Schema.DescribeSObjectResult d = describe(objectName);
        return d == null ? null : d.getSObjectType();
    }

    public static Boolean isNumeric(Schema.DisplayType t) {
        return t == Schema.DisplayType.INTEGER ||
            t == Schema.DisplayType.DOUBLE ||
            t == Schema.DisplayType.CURRENCY ||
            t == Schema.DisplayType.PERCENT ||
            t == Schema.DisplayType.LONG;
    }

    /** Converts a text value to the field's Apex type for DML. */
    public static Object coerce(Schema.DescribeFieldResult d, String value) {
        if (value == null) {
            return null;
        }
        String v = value.trim();
        if (v == '' || v.equalsIgnoreCase('null')) {
            return null;
        }
        Schema.DisplayType t = d.getType();
        if (t == Schema.DisplayType.BOOLEAN) {
            return v.equalsIgnoreCase('true') || v == '1' || v.equalsIgnoreCase('yes');
        }
        if (t == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(v);
        }
        if (t == Schema.DisplayType.LONG) {
            return Long.valueOf(v);
        }
        if (isNumeric(t)) {
            return Decimal.valueOf(v);
        }
        if (t == Schema.DisplayType.DATE) {
            return v.equalsIgnoreCase('TODAY') ? Date.today() : Date.valueOf(v);
        }
        if (t == Schema.DisplayType.DATETIME) {
            return v.equalsIgnoreCase('NOW') ? System.now() : (Datetime) JSON.deserialize('"' + v + '"', Datetime.class);
        }
        if (t == Schema.DisplayType.ID || t == Schema.DisplayType.REFERENCE) {
            return Id.valueOf(v);
        }
        return v;
    }
}
