/**
 * "Field__c=Value" lines used for post-assignment, reassignment and rejection updates.
 */
public inherited sharing class DE_FieldUpdates {
    public static final Set<Schema.DisplayType> ALLOWED = new Set<Schema.DisplayType>{
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.MULTIPICKLIST,
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL
    };

    /** Returns an error message for invalid lines, or null. */
    public static String validate(String objectName, String spec) {
        if (String.isBlank(spec)) {
            return null;
        }
        for (String line : spec.split('\\n')) {
            if (String.isBlank(line)) {
                continue;
            }
            if (!line.contains('=')) {
                return '"' + line.trim() + '" must look like Field__c=Value.';
            }
            String field = line.substringBefore('=').trim();
            Schema.DescribeFieldResult fd = DE_Schema.field(objectName, field);
            if (fd == null) {
                return 'Field ' + field + ' does not exist on ' + objectName + '.';
            }
            if (!fd.isUpdateable() || !ALLOWED.contains(fd.getType())) {
                return 'Field ' + field + ' cannot be updated by Distribution Engine.';
            }
            try {
                DE_Schema.coerce(fd, line.substringAfter('='));
            } catch (Exception e) {
                return '"' + line.substringAfter('=').trim() + '" is not a valid value for ' + field + '.';
            }
        }
        return null;
    }

    /** Applies the updates to target. Invalid lines are skipped and reported in warnings. */
    public static void apply(SObject target, String objectName, String spec, List<String> warnings) {
        if (String.isBlank(spec)) {
            return;
        }
        for (String line : spec.split('\\n')) {
            if (String.isBlank(line) || !line.contains('=')) {
                continue;
            }
            String field = line.substringBefore('=').trim();
            Schema.DescribeFieldResult fd = DE_Schema.field(objectName, field);
            if (fd == null || !fd.isUpdateable()) {
                if (warnings != null) {
                    warnings.add('Field update skipped: ' + field + ' is not an updateable field on ' + objectName + '.');
                }
                continue;
            }
            try {
                target.put(fd.getName(), DE_Schema.coerce(fd, line.substringAfter('=')));
            } catch (Exception e) {
                if (warnings != null) {
                    warnings.add('Field update skipped for ' + field + ': ' + e.getMessage());
                }
            }
        }
    }
}
