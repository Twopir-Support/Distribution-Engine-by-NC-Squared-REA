/**
 * Parses and evaluates filter logic such as "(1 AND 2) OR NOT 3".
 * A blank expression means every condition must be true (AND of all rows).
 */
public inherited sharing class DE_Logic {
    public class LogicException extends Exception {
    }

    private List<String> tokens;
    private Integer pos = 0;
    private Map<Integer, Boolean> values;
    private Set<Integer> referenced = new Set<Integer>();

    private DE_Logic(String expression, Map<Integer, Boolean> values) {
        this.values = values;
        String spaced = expression.toUpperCase().replace('(', ' ( ').replace(')', ' ) ');
        this.tokens = new List<String>();
        for (String t : spaced.split('\\s+')) {
            if (String.isNotBlank(t)) {
                tokens.add(t);
            }
        }
    }

    public static Boolean evaluate(String expression, Map<Integer, Boolean> values) {
        if (String.isBlank(expression)) {
            for (Boolean b : values.values()) {
                if (b != true) {
                    return false;
                }
            }
            return true;
        }
        DE_Logic parser = new DE_Logic(expression, values);
        Boolean result = parser.parseOr();
        if (parser.pos < parser.tokens.size()) {
            throw new LogicException('Unexpected "' + parser.tokens[parser.pos] + '" in filter logic "' + expression + '".');
        }
        return result;
    }

    /**
     * Returns a user-facing error message, or null when the expression is valid for the given row numbers.
     * Every row number in the expression must exist.
     */
    public static String validate(String expression, Set<Integer> rowNumbers) {
        if (String.isBlank(expression)) {
            return null;
        }
        Map<Integer, Boolean> all = new Map<Integer, Boolean>();
        for (Integer i : rowNumbers) {
            all.put(i, true);
        }
        DE_Logic parser = new DE_Logic(expression, all);
        try {
            parser.parseOr();
            if (parser.pos < parser.tokens.size()) {
                return 'Unexpected "' + parser.tokens[parser.pos] + '" in filter logic.';
            }
        } catch (LogicException e) {
            return e.getMessage();
        }
        for (Integer r : parser.referenced) {
            if (!rowNumbers.contains(r)) {
                return 'Filter logic references condition ' + r + ', which does not exist.';
            }
        }
        return null;
    }

    private String peek() {
        return pos < tokens.size() ? tokens[pos] : null;
    }

    private Boolean parseOr() {
        Boolean left = parseAnd();
        while (peek() == 'OR') {
            pos++;
            Boolean right = parseAnd();
            left = left || right;
        }
        return left;
    }

    private Boolean parseAnd() {
        Boolean left = parseNot();
        while (peek() == 'AND') {
            pos++;
            Boolean right = parseNot();
            left = left && right;
        }
        return left;
    }

    private Boolean parseNot() {
        if (peek() == 'NOT') {
            pos++;
            return !parseNot();
        }
        return parsePrimary();
    }

    private Boolean parsePrimary() {
        String t = peek();
        if (t == null) {
            throw new LogicException('Filter logic ends unexpectedly.');
        }
        if (t == '(') {
            pos++;
            Boolean innerValue = parseOr();
            if (peek() != ')') {
                throw new LogicException('Filter logic is missing a closing bracket.');
            }
            pos++;
            return innerValue;
        }
        if (!t.isNumeric()) {
            throw new LogicException('Unexpected "' + t + '" in filter logic. Use numbers, AND, OR, NOT and brackets.');
        }
        pos++;
        Integer n = Integer.valueOf(t);
        referenced.add(n);
        if (!values.containsKey(n)) {
            throw new LogicException('Filter logic references condition ' + n + ', which does not exist.');
        }
        return values.get(n);
    }
}
