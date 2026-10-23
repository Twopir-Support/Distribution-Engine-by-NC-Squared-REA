@IsTest
private class DE_TextMatchTest {
    @IsTest
    static void normalizesCompanyNames() {
        Assert.areEqual('acme and sons', DE_TextMatch.normalizeCompany('The Acme & Sons, Ltd.'), 'legal suffixes and punctuation removed');
        Assert.areEqual('globex', DE_TextMatch.normalizeCompany('Globex Corporation'), 'corporation removed');
        Assert.areEqual('initech 2000', DE_TextMatch.normalizeCompany('  INITECH   2000 GmbH '), 'extra spaces collapsed');
        Assert.areEqual('', DE_TextMatch.normalizeCompany(null), 'null');
        Assert.areEqual('', DE_TextMatch.normalizeCompany('Inc.'), 'only a suffix');
        Assert.areEqual('acme', DE_TextMatch.firstToken('acme and sons'), 'first token');
        Assert.areEqual('', DE_TextMatch.firstToken(''), 'blank first token');
    }

    @IsTest
    static void jaroWinklerSimilarity() {
        Decimal s = DE_TextMatch.jaroWinkler('martha', 'marhta');
        Assert.isTrue(s > 0.96 && s < 0.962, 'classic martha/marhta example: ' + s);
        Decimal d = DE_TextMatch.jaroWinkler('dwayne', 'duane');
        Assert.isTrue(d > 0.83 && d < 0.85, 'classic dwayne/duane example: ' + d);
        Assert.isTrue(DE_TextMatch.jaroWinkler('acme', 'acme') == 1, 'identical');
        Assert.isTrue(DE_TextMatch.jaroWinkler('abc', 'xyz') == 0, 'nothing in common');
        Assert.isTrue(DE_TextMatch.jaroWinkler('', 'a') == 0, 'empty');
        Assert.isTrue(DE_TextMatch.jaroWinkler(null, 'a') == 0, 'null');
        Assert.isTrue(
            DE_TextMatch.jaroWinkler('acme industries', 'acme industry') > DE_TextMatch.jaroWinkler('acme industries', 'zenith industries'),
            'shared prefix scores higher'
        );
    }

    @IsTest
    static void extractsDomains() {
        Assert.areEqual('example.com', DE_TextMatch.emailDomain('Bob.Smith@Example.COM '), 'email domain lower-cased');
        Assert.areEqual('b.com', DE_TextMatch.emailDomain('"a@b"@b.com'), 'last @ wins');
        Assert.isNull(DE_TextMatch.emailDomain('no-at-sign'), 'no @');
        Assert.isNull(DE_TextMatch.emailDomain(null), 'null email');
        Assert.areEqual('acme.co.uk', DE_TextMatch.websiteDomain('https://www.Acme.co.uk/about?x=1'), 'scheme, www and path removed');
        Assert.areEqual('acme.com', DE_TextMatch.websiteDomain('acme.com:8080'), 'port removed');
        Assert.areEqual('shop.acme.com', DE_TextMatch.websiteDomain('http://shop.acme.com#top'), 'subdomain kept');
        Assert.isNull(DE_TextMatch.websiteDomain(' '), 'blank website');
    }

    @IsTest
    static void normalizesGeography() {
        Assert.areEqual('United States', DE_TextMatch.normalizeCountry(' USA '), 'alias');
        Assert.areEqual('United Kingdom', DE_TextMatch.normalizeCountry('england'), 'constituent country');
        Assert.areEqual('Narnia', DE_TextMatch.normalizeCountry(' Narnia '), 'unknown country is trimmed and kept');
        Assert.isNull(DE_TextMatch.normalizeCountry(''), 'blank country');

        Assert.areEqual('United Kingdom', DE_TextMatch.countryFromPhone('+44 20 7946 0000'), 'UK dial code');
        Assert.areEqual('United States', DE_TextMatch.countryFromPhone('+1 (555) 010-0000'), 'US dial code');
        Assert.areEqual('Ireland', DE_TextMatch.countryFromPhone('+353 1 555 0000'), 'longest dial code wins');
        Assert.isNull(DE_TextMatch.countryFromPhone('020 7946 0000'), 'no international prefix');
        Assert.isNull(DE_TextMatch.countryFromPhone('+999 123'), 'unknown dial code');
        Assert.isNull(DE_TextMatch.countryFromPhone(null), 'blank phone');

        Assert.areEqual('United Kingdom', DE_TextMatch.countryFromDomain('acme.co.uk'), 'country TLD');
        Assert.isNull(DE_TextMatch.countryFromDomain('acme.com'), 'generic TLD');
        Assert.isNull(DE_TextMatch.countryFromDomain('localhost'), 'no dot');

        Set<String> ca = DE_TextMatch.stateForms('CA');
        Assert.isTrue(ca.contains('ca') && ca.contains('california'), 'code gives code and name: ' + ca);
        Set<String> ny = DE_TextMatch.stateForms('New York');
        Assert.isTrue(ny.contains('new york') && ny.contains('ny'), 'name gives name and code: ' + ny);
        Assert.areEqual(new Set<String>{ 'ontario' }, DE_TextMatch.stateForms(' Ontario '), 'non-US state kept as is');
        Assert.isTrue(DE_TextMatch.stateForms(null).isEmpty(), 'blank state');
    }

    @IsTest
    static void matchesPostalCodes() {
        Assert.isTrue(DE_TextMatch.postalMatches('SW1A 1AA', new List<String>{ 'EC*', 'sw1*' }), 'prefix wildcard');
        Assert.isTrue(DE_TextMatch.postalMatches('90210', new List<String>{ '90000..90999' }), 'numeric range');
        Assert.isFalse(DE_TextMatch.postalMatches('91000', new List<String>{ '90000..90999' }), 'outside numeric range');
        Assert.isTrue(DE_TextMatch.postalMatches('90210-1234', new List<String>{ '90000..90999' }), 'ZIP+4 compares the leading digits');
        Assert.isTrue(DE_TextMatch.postalMatches('B2', new List<String>{ 'A..C' }), 'alphabetic range');
        Assert.isFalse(DE_TextMatch.postalMatches('M1', new List<String>{ 'A..C' }), 'outside alphabetic range');
        Assert.isTrue(DE_TextMatch.postalMatches('ec1a 1bb', new List<String>{ ' ', 'EC1A1BB' }), 'exact match ignoring spaces and case');
        Assert.isFalse(DE_TextMatch.postalMatches(null, new List<String>{ '*' }), 'blank postal code');
    }
}
