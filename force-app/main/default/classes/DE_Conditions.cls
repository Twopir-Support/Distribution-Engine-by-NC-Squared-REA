/**
 * Evaluates filter rows (DE_Condition__c) against records.
 *
 * Paths:
 *  - Field or relationship path on the record, e.g. LeadSource or Account.Industry (up to 5 levels).
 *  - Classifier output: DE.Territory, DE.Domain, DE.PersonalEmail, DE.MatchConfidence, DE.Stamps,
 *    DE.Stamp.<Group>, DE.MatchedAccount[.Field], DE.MatchedContact[.Field], DE.MatchedLead[.Field].
 *
 * All text comparisons are case-insensitive. List values are separated by semicolons (or tabs).
 * Date values accept TODAY, NOW, ISO dates/datetimes, "n minutes|hours|days|weeks ago" and "... from now".
 */
public inherited sharing class DE_Conditions {
    public static final Set<String> OPERATORS = new Set<String>{
        'equals',
        'not equals',
        'less than',
        'greater than',
        'less or equal',
        'greater or equal',
        'contains',
        'does not contain',
        'starts with',
        'does not start with',
        'ends with',
        'does not end with',
        'in',
        'not in',
        'includes',
        'includes all',
        'does not include',
        'between',
        'is blank',
        'is not blank'
    };

    private static final Map<String, String> DETAIL_FIELDS = new Map<String, String>{
        'territory' => 'Territory_Name__c',
        'domain' => 'Domain__c',
        'personalemail' => 'Personal_Email__c',
        'matchconfidence' => 'Match_Confidence__c',
        'stamps' => 'Stamps__c',
        'failedattempts' => 'Failed_Attempts__c',
        'classifierstatus' => 'Classifier_Status__c',
        'matchedaccount' => 'Matched_Account__c',
        'matchedcontact' => 'Matched_Contact__c',
        'matchedlead' => 'Matched_Lead__c'
    };
    private static final Map<String, String> DETAIL_RELATIONSHIPS = new Map<String, String>{
        'matchedaccount' => 'Matched_Account__r',
        'matchedcontact' => 'Matched_Contact__r',
        'matchedlead' => 'Matched_Lead__r'
    };
    private static final Map<String, String> DETAIL_TARGETS = new Map<String, String>{
        'matchedaccount' => 'Account',
        'matchedcontact' => 'Contact',
        'matchedlead' => 'Lead'
    };

    /** Evaluation context shared by every record in a run. */
    public class Context {
        public Map<Id, DE_Record_Detail__c> details = new Map<Id, DE_Record_Detail__c>();
        public Datetime now = System.now();
    }

    public class ConditionException extends Exception {
    }

    // ------------------------------------------------------------------ evaluation

    public static Boolean matches(SObject rec, List<DE_Condition__c> conditions, String logic, Context ctx, List<String> trace) {
        if (conditions == null || conditions.isEmpty()) {
            return true;
        }
        Map<Integer, Boolean> results = new Map<Integer, Boolean>();
        for (DE_Condition__c c : conditions) {
            Object actual = resolve(rec, c.Field_API_Name__c, ctx);
            Boolean ok = compare(actual, c.Operator__c, c.Value__c, ctx == null ? System.now() : ctx.now);
            results.put(c.Sequence__c.intValue(), ok);
            if (trace != null) {
                trace.add(
                    '  ' +
                        c.Sequence__c.intValue() +
                        '. ' +
                        c.Field_API_Name__c +
                        ' ' +
                        c.Operator__c +
                        ' ' +
                        (c.Value__c == null ? '' : c.Value__c) +
                        ' → ' +
                        (ok ? 'TRUE' : 'FALSE') +
                        ' (value: ' +
                        String.valueOf(actual) +
                        ')'
                );
            }
        }
        Boolean outcome = DE_Logic.evaluate(logic, results);
        if (trace != null && String.isNotBlank(logic)) {
            trace.add('  logic ' + logic + ' → ' + (outcome ? 'TRUE' : 'FALSE'));
        }
        return outcome;
    }

    public static Boolean isDetailPath(String path) {
        return path != null && path.trim().toLowerCase().startsWith('de.');
    }

    /** Reads a value from the record or from its classifier details. */
    public static Object resolve(SObject rec, String path, Context ctx) {
        if (rec == null || String.isBlank(path)) {
            return null;
        }
        if (isDetailPath(path)) {
            DE_Record_Detail__c d = (ctx == null || rec.Id == null) ? null : ctx.details.get(rec.Id);
            return resolveDetail(d, path);
        }
        return readPath(rec, path);
    }

    public static Object readPath(SObject rec, String path) {
        List<String> parts = path.trim().split('\\.');
        SObject current = rec;
        try {
            for (Integer i = 0; i < parts.size() - 1; i++) {
                current = current.getSObject(parts[i]);
                if (current == null) {
                    return null;
                }
            }
            return current.get(parts[parts.size() - 1]);
        } catch (SObjectException e) {
            throw new ConditionException('Field ' + path + ' was not loaded or does not exist: ' + e.getMessage());
        }
    }

    public static Object resolveDetail(DE_Record_Detail__c d, String path) {
        if (d == null) {
            return null;
        }
        List<String> parts = path.trim().split('\\.');
        if (parts.size() < 2) {
            return null;
        }
        String key = parts[1].toLowerCase();
        if (key == 'stamp' && parts.size() >= 3) {
            return stampsInGroup(d.Stamps__c, parts[2]);
        }
        if (DETAIL_RELATIONSHIPS.containsKey(key) && parts.size() >= 3) {
            SObject related = d.getSObject(DETAIL_RELATIONSHIPS.get(key));
            if (related == null) {
                return null;
            }
            List<String> rest = new List<String>();
            for (Integer i = 2; i < parts.size(); i++) {
                rest.add(parts[i]);
            }
            return readPath(related, String.join(rest, '.'));
        }
        String field = DETAIL_FIELDS.get(key);
        return field == null ? null : d.get(field);
    }

    /** Returns the stamps of one group as a semicolon-separated list (multi-select style). */
    public static String stampsInGroup(String stamps, String groupName) {
        if (String.isBlank(stamps)) {
            return null;
        }
        List<String> out = new List<String>();
        String prefix = groupName.trim().toLowerCase() + ':';
        for (String s : stamps.split(';')) {
            if (s.trim().toLowerCase().startsWith(prefix)) {
                out.add(s.trim().substring(prefix.length()));
            }
        }
        return out.isEmpty() ? null : String.join(out, ';');
    }

    // ------------------------------------------------------------------ comparison

    public static List<String> splitValues(String expected) {
        List<String> out = new List<String>();
        if (expected == null) {
            return out;
        }
        for (String s : expected.split('[;\\t]')) {
            if (String.isNotBlank(s)) {
                out.add(s.trim());
            }
        }
        return out;
    }

    public static Boolean compare(Object actual, String operator, String expected, Datetime now) {
        String op = String.isBlank(operator) ? 'equals' : operator.trim().toLowerCase();
        Boolean blank = actual == null || String.valueOf(actual).trim() == '';
        if (op == 'is blank') {
            return blank;
        }
        if (op == 'is not blank') {
            return !blank;
        }
        String exp = expected == null ? '' : expected.trim();
        List<String> values = splitValues(exp);
        switch on op {
            when 'equals' {
                return exp == '' ? blank : equalsOne(actual, exp, now);
            }
            when 'not equals' {
                return exp == '' ? !blank : !equalsOne(actual, exp, now);
            }
            when 'in' {
                return equalsAny(actual, values, now);
            }
            when 'not in' {
                return !equalsAny(actual, values, now);
            }
            when 'contains' {
                return textAny(actual, values, 'contains');
            }
            when 'does not contain' {
                return !textAny(actual, values, 'contains');
            }
            when 'starts with' {
                return textAny(actual, values, 'starts');
            }
            when 'does not start with' {
                return !textAny(actual, values, 'starts');
            }
            when 'ends with' {
                return textAny(actual, values, 'ends');
            }
            when 'does not end with' {
                return !textAny(actual, values, 'ends');
            }
            when 'includes' {
                return overlap(actual, values) > 0;
            }
            when 'does not include' {
                return overlap(actual, values) == 0;
            }
            when 'includes all' {
                return !values.isEmpty() && overlap(actual, values) == new Set<String>(lowerAll(values)).size();
            }
            when 'less than', 'greater than', 'less or equal', 'greater or equal' {
                if (blank) {
                    return false;
                }
                Integer c = compareValues(actual, exp, now);
                if (c == null) {
                    return false;
                }
                return (op == 'less than' &&
                    c < 0) ||
                    (op == 'greater than' &&
                    c > 0) ||
                    (op == 'less or equal' &&
                    c <= 0) ||
                    (op == 'greater or equal' &&
                    c >= 0);
            }
            when 'between' {
                if (blank || !exp.contains('..')) {
                    return false;
                }
                String low = exp.substringBefore('..').trim();
                String high = exp.substringAfter('..').trim();
                Integer a = compareValues(actual, low, now);
                Integer b = compareValues(actual, high, now);
                return a != null && b != null && a >= 0 && b <= 0;
            }
            when else {
                throw new ConditionException('Unknown operator "' + operator + '".');
            }
        }
    }

    private static List<String> lowerAll(List<String> values) {
        List<String> out = new List<String>();
        for (String v : values) {
            out.add(v.toLowerCase());
        }
        return out;
    }

    private static Integer overlap(Object actual, List<String> values) {
        if (actual == null) {
            return 0;
        }
        Set<String> have = new Set<String>(lowerAll(splitValues(String.valueOf(actual))));
        Set<String> want = new Set<String>(lowerAll(values));
        Integer n = 0;
        for (String w : want) {
            if (have.contains(w)) {
                n++;
            }
        }
        return n;
    }

    private static Boolean textAny(Object actual, List<String> values, String mode) {
        if (actual == null) {
            return false;
        }
        String a = String.valueOf(actual).toLowerCase();
        for (String v : values) {
            String w = v.toLowerCase();
            if ((mode == 'contains' && a.contains(w)) || (mode == 'starts' && a.startsWith(w)) || (mode == 'ends' && a.endsWith(w))) {
                return true;
            }
        }
        return false;
    }

    private static Boolean equalsAny(Object actual, List<String> values, Datetime now) {
        for (String v : values) {
            if (equalsOne(actual, v, now)) {
                return true;
            }
        }
        return false;
    }

    public static Boolean equalsOne(Object actual, String expected, Datetime now) {
        if (actual == null) {
            return String.isBlank(expected);
        }
        if (actual instanceof Boolean) {
            return (Boolean) actual == (expected.equalsIgnoreCase('true') || expected == '1' || expected.equalsIgnoreCase('yes'));
        }
        if (actual instanceof Id) {
            Id want = DE_Ids.toId(expected);
            return want != null && ((Id) actual) == want;
        }
        if (actual instanceof Date || actual instanceof Datetime || isNumber(actual)) {
            Integer c = compareValues(actual, expected, now);
            return c != null && c == 0;
        }
        String a = String.valueOf(actual);
        if (a.contains(';')) {
            // multi-select picklist: equals means the same set of values
            Set<String> have = new Set<String>(lowerAll(splitValues(a)));
            Set<String> want = new Set<String>(lowerAll(splitValues(expected)));
            return have.equals(want);
        }
        return a.equalsIgnoreCase(expected);
    }

    private static Boolean isNumber(Object v) {
        return v instanceof Decimal || v instanceof Integer || v instanceof Long || v instanceof Double;
    }

    private static Decimal toDecimal(String s) {
        try {
            return Decimal.valueOf(s.trim());
        } catch (Exception e) {
            return null;
        }
    }

    /** Returns negative, zero or positive, or null when the values cannot be compared. */
    public static Integer compareValues(Object actual, String expected, Datetime now) {
        if (actual == null || expected == null) {
            return null;
        }
        if (isNumber(actual)) {
            Decimal b = toDecimal(expected);
            if (b == null) {
                return null;
            }
            Decimal a = Decimal.valueOf(String.valueOf(actual));
            return a < b ? -1 : (a > b ? 1 : 0);
        }
        if (actual instanceof Datetime) {
            Datetime b = parseDatetime(expected, now);
            if (b == null) {
                return null;
            }
            Long diff = ((Datetime) actual).getTime() - b.getTime();
            return diff < 0 ? -1 : (diff > 0 ? 1 : 0);
        }
        if (actual instanceof Date) {
            Date b = parseDate(expected, now);
            if (b == null) {
                return null;
            }
            Date a = (Date) actual;
            return a < b ? -1 : (a > b ? 1 : 0);
        }
        String sa = String.valueOf(actual).trim();
        Decimal na = toDecimal(sa);
        Decimal nb = toDecimal(expected);
        if (na != null && nb != null) {
            return na < nb ? -1 : (na > nb ? 1 : 0);
        }
        Integer c = sa.toLowerCase().compareTo(expected.trim().toLowerCase());
        return c < 0 ? -1 : (c > 0 ? 1 : 0);
    }

    /** Parses NOW, TODAY, "n unit(s) ago|from now", ISO date or datetime. */
    public static Datetime parseDatetime(String value, Datetime now) {
        if (String.isBlank(value)) {
            return null;
        }
        String v = value.trim().toLowerCase();
        Datetime base = now == null ? System.now() : now;
        if (v == 'now') {
            return base;
        }
        if (v == 'today') {
            return Datetime.newInstance(base.date(), Time.newInstance(0, 0, 0, 0));
        }
        Datetime relative = parseRelative(v, base);
        if (relative != null) {
            return relative;
        }
        try {
            if (v.length() == 10) {
                return Datetime.newInstance(Date.valueOf(v), Time.newInstance(0, 0, 0, 0));
            }
            return (Datetime) JSON.deserialize('"' + value.trim().replace(' ', 'T') + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    public static Date parseDate(String value, Datetime now) {
        if (String.isBlank(value)) {
            return null;
        }
        String v = value.trim().toLowerCase();
        Datetime base = now == null ? System.now() : now;
        if (v == 'today' || v == 'now') {
            return base.date();
        }
        Datetime relative = parseRelative(v, base);
        if (relative != null) {
            return relative.date();
        }
        try {
            return Date.valueOf(v.left(10));
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime parseRelative(String v, Datetime base) {
        Pattern p = Pattern.compile('^(\\d+)\\s*(minute|minutes|min|mins|hour|hours|day|days|week|weeks)\\s+(ago|from now)$');
        Matcher m = p.matcher(v);
        if (!m.matches()) {
            return null;
        }
        Integer n = Integer.valueOf(m.group(1));
        if (m.group(3) == 'ago') {
            n = -n;
        }
        String unit = m.group(2);
        if (unit.startsWith('min')) {
            return base.addMinutes(n);
        }
        if (unit.startsWith('hour')) {
            return base.addHours(n);
        }
        if (unit.startsWith('day')) {
            return base.addDays(n);
        }
        return base.addDays(n * 7);
    }

    // ------------------------------------------------------------------ field collection and validation

    /** Record field paths needed to evaluate the conditions (classifier paths excluded). */
    public static Set<String> recordPaths(List<DE_Condition__c> conditions) {
        Set<String> out = new Set<String>();
        if (conditions == null) {
            return out;
        }
        for (DE_Condition__c c : conditions) {
            String p = c.Field_API_Name__c;
            if (String.isNotBlank(p) && !isDetailPath(p) && c.Purpose__c != 'Member Filter') {
                out.add(p.trim());
            }
        }
        return out;
    }

    /** DE_Record_Detail__c fields (incl. relationship paths) needed for DE.* conditions. */
    public static Set<String> detailFields(List<DE_Condition__c> conditions) {
        Set<String> out = new Set<String>();
        if (conditions == null) {
            return out;
        }
        for (DE_Condition__c c : conditions) {
            String f = detailFieldFor(c.Field_API_Name__c);
            if (f != null) {
                out.add(f);
            }
        }
        return out;
    }

    public static String detailFieldFor(String path) {
        if (!isDetailPath(path)) {
            return null;
        }
        List<String> parts = path.trim().split('\\.');
        if (parts.size() < 2) {
            return null;
        }
        String key = parts[1].toLowerCase();
        if (key == 'stamp') {
            return 'Stamps__c';
        }
        if (DETAIL_RELATIONSHIPS.containsKey(key) && parts.size() >= 3) {
            List<String> rest = new List<String>();
            for (Integer i = 2; i < parts.size(); i++) {
                rest.add(parts[i]);
            }
            return DETAIL_RELATIONSHIPS.get(key) + '.' + String.join(rest, '.');
        }
        return DETAIL_FIELDS.get(key);
    }

    /**
     * Validates a list of conditions for an object. Returns the first error or null.
     * Member filters use their own syntax and are validated separately.
     */
    public static String validate(String objectName, List<DE_Condition__c> conditions, String logic) {
        Set<Integer> rows = new Set<Integer>();
        for (DE_Condition__c c : conditions) {
            if (c.Sequence__c == null) {
                return 'Every condition needs a row number.';
            }
            Integer n = c.Sequence__c.intValue();
            if (rows.contains(n)) {
                return 'Row number ' + n + ' is used twice.';
            }
            rows.add(n);
            if (String.isBlank(c.Field_API_Name__c)) {
                return 'Row ' + n + ': choose a field.';
            }
            String op = c.Operator__c == null ? '' : c.Operator__c.toLowerCase();
            if (!OPERATORS.contains(op)) {
                return 'Row ' + n + ': "' + c.Operator__c + '" is not a valid operator.';
            }
            if (c.Purpose__c == 'Member Filter') {
                String memberError = validateMemberFilter(objectName, c);
                if (memberError != null) {
                    return 'Row ' + n + ': ' + memberError;
                }
                continue;
            }
            String path = c.Field_API_Name__c.trim();
            Schema.DescribeFieldResult fd;
            if (isDetailPath(path)) {
                String df = detailFieldFor(path);
                if (df == null) {
                    return 'Row ' + n + ': ' + path + ' is not a Distribution Engine classifier field.';
                }
                fd = DE_Schema.resolvePath('DE_Record_Detail__c', df);
                if (fd == null) {
                    return 'Row ' + n + ': ' + path + ' does not resolve to a field.';
                }
            } else {
                fd = DE_Schema.resolvePath(objectName, path);
                if (fd == null) {
                    return 'Row ' + n + ': field ' + path + ' does not exist on ' + objectName + '.';
                }
            }
            String valueError = validateValue(fd, op, c.Value__c);
            if (valueError != null) {
                return 'Row ' + n + ': ' + valueError;
            }
        }
        return DE_Logic.validate(logic, rows);
    }

    private static String validateValue(Schema.DescribeFieldResult fd, String op, String value) {
        if (op == 'is blank' || op == 'is not blank') {
            return null;
        }
        if (op == 'between' && (value == null || !value.contains('..'))) {
            return 'between needs a value like low..high.';
        }
        Schema.DisplayType t = fd.getType();
        List<String> values = op == 'between' ? new List<String>{ value.substringBefore('..'), value.substringAfter('..') } : splitValues(value);
        for (String v : values) {
            if (DE_Schema.isNumeric(t) && toDecimal(v) == null) {
                return '"' + v + '" is not a number for ' + fd.getLabel() + '.';
            }
            if (t == Schema.DisplayType.DATE && parseDate(v, System.now()) == null) {
                return '"' + v + '" is not a date. Use YYYY-MM-DD, TODAY or "n days ago".';
            }
            if (t == Schema.DisplayType.DATETIME && parseDatetime(v, System.now()) == null) {
                return '"' + v + '" is not a date/time. Use YYYY-MM-DDTHH:MM:SSZ, NOW or "n minutes ago".';
            }
        }
        if ((op == 'includes' || op == 'includes all' || op == 'does not include') && values.isEmpty()) {
            return 'Enter at least one value.';
        }
        return null;
    }

    private static String validateMemberFilter(String objectName, DE_Condition__c c) {
        String f = c.Field_API_Name__c.trim();
        String op = c.Operator__c.toLowerCase();
        Set<String> tagOps = new Set<String>{ 'includes', 'includes all', 'does not include' };
        if (f.equalsIgnoreCase('Territory') || f.toLowerCase().startsWith('stamp:')) {
            return tagOps.contains(op) ? null : 'member filters use includes, includes all or does not include.';
        }
        if (f.toLowerCase().startsWith('tag:')) {
            if (!tagOps.contains(op)) {
                return 'member filters use includes, includes all or does not include.';
            }
            return splitValues(c.Value__c).isEmpty() ? 'enter at least one tag.' : null;
        }
        if (f.toLowerCase().startsWith('dynamictag:')) {
            if (String.isBlank(c.Value__c) || DE_Schema.resolvePath(objectName, c.Value__c.trim()) == null) {
                return 'dynamic tags need the record field whose value names the tag.';
            }
            return null;
        }
        return 'member filter field must be Tag:<Collection>, DynamicTag:<Collection>, Territory or Stamp:<Group>.';
    }
}
