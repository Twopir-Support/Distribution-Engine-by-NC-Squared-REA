@IsTest
private class DE_LogicTest {
    private static Map<Integer, Boolean> vals(Boolean a, Boolean b, Boolean c) {
        return new Map<Integer, Boolean>{ 1 => a, 2 => b, 3 => c };
    }

    @IsTest
    static void blankExpressionMeansAllTrue() {
        Assert.isTrue(DE_Logic.evaluate(null, vals(true, true, true)), 'Blank logic should AND every row');
        Assert.isFalse(DE_Logic.evaluate('', vals(true, false, true)), 'Blank logic fails when one row is false');
        Assert.isTrue(DE_Logic.evaluate(' ', new Map<Integer, Boolean>()), 'No rows and no logic is true');
    }

    @IsTest
    static void andOrNotAndPrecedence() {
        Assert.isTrue(DE_Logic.evaluate('1 AND 2', vals(true, true, false)), '1 AND 2');
        Assert.isFalse(DE_Logic.evaluate('1 AND 3', vals(true, true, false)), '1 AND 3');
        Assert.isTrue(DE_Logic.evaluate('1 OR 3', vals(false, true, true)), '1 OR 3');
        Assert.isTrue(DE_Logic.evaluate('NOT 3', vals(true, true, false)), 'NOT 3');
        Assert.isTrue(DE_Logic.evaluate('NOT NOT 1', vals(true, true, false)), 'double negation');
        // AND binds tighter than OR: 1 OR (2 AND 3)
        Assert.isTrue(DE_Logic.evaluate('1 OR 2 AND 3', vals(true, false, false)), 'AND binds tighter than OR');
        Assert.isFalse(DE_Logic.evaluate('(1 OR 2) AND 3', vals(true, false, false)), 'brackets override precedence');
        Assert.isTrue(DE_Logic.evaluate('(1 and 2) or not 3', vals(true, true, true)), 'lower-case keywords are accepted');
        Assert.isTrue(DE_Logic.evaluate('((1)AND(2))', vals(true, true, false)), 'brackets without spaces are tokenised');
    }

    @IsTest
    static void malformedExpressionsThrow() {
        for (String bad : new List<String>{ '1 AND', '(1 OR 2', '1 2', '1 XOR 2', '4', ')' }) {
            Boolean threw = false;
            try {
                DE_Logic.evaluate(bad, vals(true, true, true));
            } catch (DE_Logic.LogicException e) {
                threw = true;
            }
            Assert.isTrue(threw, 'Expected a LogicException for "' + bad + '"');
        }
    }

    @IsTest
    static void validateReportsProblems() {
        Set<Integer> rows = new Set<Integer>{ 1, 2 };
        Assert.isNull(DE_Logic.validate(null, rows), 'Blank logic is valid');
        Assert.isNull(DE_Logic.validate('1 OR NOT 2', rows), 'Valid logic');
        Assert.isTrue(DE_Logic.validate('1 OR 3', rows).contains('condition 3'), 'Unknown row is reported');
        Assert.isTrue(DE_Logic.validate('(1 OR 2', rows).contains('closing bracket'), 'Missing bracket is reported');
        Assert.isTrue(DE_Logic.validate('1 2', rows).startsWith('Unexpected "2"'), 'Trailing token is reported');
        Assert.isTrue(DE_Logic.validate('1 AND', rows).contains('ends unexpectedly'), 'Dangling operator is reported');
    }
}
