/**
 * Text helpers for the classifier: company name normalisation, Jaro-Winkler similarity,
 * email/website domains, and country/state normalisation for territories.
 */
public inherited sharing class DE_TextMatch {
    private static final Set<String> LEGAL_SUFFIXES = new Set<String>{
        'inc',
        'incorporated',
        'ltd',
        'limited',
        'llc',
        'llp',
        'plc',
        'gmbh',
        'ag',
        'sa',
        'sas',
        'bv',
        'nv',
        'pty',
        'corp',
        'corporation',
        'co',
        'company',
        'the',
        'srl',
        'spa',
        'oy',
        'ab',
        'as',
        'kk'
    };

    public static final Map<String, String> COUNTRY_ALIASES = new Map<String, String>{
        'us' => 'United States',
        'usa' => 'United States',
        'u.s.' => 'United States',
        'u.s.a.' => 'United States',
        'united states' => 'United States',
        'united states of america' => 'United States',
        'america' => 'United States',
        'uk' => 'United Kingdom',
        'gb' => 'United Kingdom',
        'gbr' => 'United Kingdom',
        'great britain' => 'United Kingdom',
        'britain' => 'United Kingdom',
        'england' => 'United Kingdom',
        'scotland' => 'United Kingdom',
        'wales' => 'United Kingdom',
        'northern ireland' => 'United Kingdom',
        'united kingdom' => 'United Kingdom',
        'ca' => 'Canada',
        'can' => 'Canada',
        'canada' => 'Canada',
        'au' => 'Australia',
        'aus' => 'Australia',
        'australia' => 'Australia',
        'nz' => 'New Zealand',
        'new zealand' => 'New Zealand',
        'de' => 'Germany',
        'deu' => 'Germany',
        'germany' => 'Germany',
        'deutschland' => 'Germany',
        'fr' => 'France',
        'fra' => 'France',
        'france' => 'France',
        'ie' => 'Ireland',
        'ireland' => 'Ireland',
        'es' => 'Spain',
        'spain' => 'Spain',
        'españa' => 'Spain',
        'it' => 'Italy',
        'italy' => 'Italy',
        'italia' => 'Italy',
        'nl' => 'Netherlands',
        'netherlands' => 'Netherlands',
        'the netherlands' => 'Netherlands',
        'holland' => 'Netherlands',
        'be' => 'Belgium',
        'belgium' => 'Belgium',
        'ch' => 'Switzerland',
        'switzerland' => 'Switzerland',
        'at' => 'Austria',
        'austria' => 'Austria',
        'se' => 'Sweden',
        'sweden' => 'Sweden',
        'no' => 'Norway',
        'norway' => 'Norway',
        'dk' => 'Denmark',
        'denmark' => 'Denmark',
        'fi' => 'Finland',
        'finland' => 'Finland',
        'pt' => 'Portugal',
        'portugal' => 'Portugal',
        'pl' => 'Poland',
        'poland' => 'Poland',
        'in' => 'India',
        'ind' => 'India',
        'india' => 'India',
        'jp' => 'Japan',
        'japan' => 'Japan',
        'cn' => 'China',
        'china' => 'China',
        'sg' => 'Singapore',
        'singapore' => 'Singapore',
        'br' => 'Brazil',
        'brazil' => 'Brazil',
        'mx' => 'Mexico',
        'mexico' => 'Mexico',
        'za' => 'South Africa',
        'south africa' => 'South Africa',
        'ae' => 'United Arab Emirates',
        'uae' => 'United Arab Emirates',
        'united arab emirates' => 'United Arab Emirates'
    };

    private static final Map<String, String> DIAL_CODES = new Map<String, String>{
        '+1' => 'United States',
        '+44' => 'United Kingdom',
        '+33' => 'France',
        '+49' => 'Germany',
        '+61' => 'Australia',
        '+64' => 'New Zealand',
        '+353' => 'Ireland',
        '+34' => 'Spain',
        '+39' => 'Italy',
        '+31' => 'Netherlands',
        '+91' => 'India',
        '+81' => 'Japan',
        '+65' => 'Singapore'
    };

    private static final Map<String, String> TLD_COUNTRIES = new Map<String, String>{
        'uk' => 'United Kingdom',
        'de' => 'Germany',
        'fr' => 'France',
        'au' => 'Australia',
        'ca' => 'Canada',
        'nz' => 'New Zealand',
        'ie' => 'Ireland',
        'es' => 'Spain',
        'it' => 'Italy',
        'nl' => 'Netherlands',
        'in' => 'India',
        'jp' => 'Japan',
        'sg' => 'Singapore'
    };

    public static final Map<String, String> US_STATES = new Map<String, String>{
        'alabama' => 'AL',
        'alaska' => 'AK',
        'arizona' => 'AZ',
        'arkansas' => 'AR',
        'california' => 'CA',
        'colorado' => 'CO',
        'connecticut' => 'CT',
        'delaware' => 'DE',
        'district of columbia' => 'DC',
        'florida' => 'FL',
        'georgia' => 'GA',
        'hawaii' => 'HI',
        'idaho' => 'ID',
        'illinois' => 'IL',
        'indiana' => 'IN',
        'iowa' => 'IA',
        'kansas' => 'KS',
        'kentucky' => 'KY',
        'louisiana' => 'LA',
        'maine' => 'ME',
        'maryland' => 'MD',
        'massachusetts' => 'MA',
        'michigan' => 'MI',
        'minnesota' => 'MN',
        'mississippi' => 'MS',
        'missouri' => 'MO',
        'montana' => 'MT',
        'nebraska' => 'NE',
        'nevada' => 'NV',
        'new hampshire' => 'NH',
        'new jersey' => 'NJ',
        'new mexico' => 'NM',
        'new york' => 'NY',
        'north carolina' => 'NC',
        'north dakota' => 'ND',
        'ohio' => 'OH',
        'oklahoma' => 'OK',
        'oregon' => 'OR',
        'pennsylvania' => 'PA',
        'rhode island' => 'RI',
        'south carolina' => 'SC',
        'south dakota' => 'SD',
        'tennessee' => 'TN',
        'texas' => 'TX',
        'utah' => 'UT',
        'vermont' => 'VT',
        'virginia' => 'VA',
        'washington' => 'WA',
        'west virginia' => 'WV',
        'wisconsin' => 'WI',
        'wyoming' => 'WY'
    };

    // ------------------------------------------------------------------ company names

    public static String normalizeCompany(String name) {
        if (String.isBlank(name)) {
            return '';
        }
        String s = name.toLowerCase().replace('&', ' and ').replaceAll('[^a-z0-9 ]', ' ');
        List<String> kept = new List<String>();
        for (String token : s.split('\\s+')) {
            if (String.isNotBlank(token) && !LEGAL_SUFFIXES.contains(token)) {
                kept.add(token);
            }
        }
        return String.join(kept, ' ');
    }

    public static String firstToken(String normalized) {
        return String.isBlank(normalized) ? '' : normalized.split(' ')[0];
    }

    /** Jaro-Winkler similarity in [0, 1]. */
    public static Decimal jaroWinkler(String a, String b) {
        if (a == null || b == null) {
            return 0;
        }
        if (a == b) {
            return 1;
        }
        Integer la = a.length();
        Integer lb = b.length();
        if (la == 0 || lb == 0) {
            return 0;
        }
        Integer range = Math.max(0, Math.max(la, lb) / 2 - 1);
        List<Boolean> ma = new List<Boolean>();
        List<Boolean> mb = new List<Boolean>();
        for (Integer i = 0; i < la; i++) {
            ma.add(false);
        }
        for (Integer i = 0; i < lb; i++) {
            mb.add(false);
        }
        Integer matches = 0;
        for (Integer i = 0; i < la; i++) {
            Integer lo = Math.max(0, i - range);
            Integer hi = Math.min(lb - 1, i + range);
            for (Integer j = lo; j <= hi; j++) {
                if (!mb[j] && a.charAt(i) == b.charAt(j)) {
                    ma[i] = true;
                    mb[j] = true;
                    matches++;
                    break;
                }
            }
        }
        if (matches == 0) {
            return 0;
        }
        Integer k = 0;
        Integer transpositions = 0;
        for (Integer i = 0; i < la; i++) {
            if (!ma[i]) {
                continue;
            }
            while (!mb[k]) {
                k++;
            }
            if (a.charAt(i) != b.charAt(k)) {
                transpositions++;
            }
            k++;
        }
        Decimal m = matches;
        Decimal jaro = (m / la + m / lb + (m - transpositions / 2.0) / m) / 3;
        Integer prefix = 0;
        for (Integer i = 0; i < Math.min(4, Math.min(la, lb)); i++) {
            if (a.charAt(i) == b.charAt(i)) {
                prefix++;
            } else {
                break;
            }
        }
        return jaro + prefix * 0.1 * (1 - jaro);
    }

    // ------------------------------------------------------------------ domains

    public static String emailDomain(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return null;
        }
        return email.substringAfterLast('@').trim().toLowerCase();
    }

    public static String websiteDomain(String website) {
        if (String.isBlank(website)) {
            return null;
        }
        String s = website.trim().toLowerCase();
        s = s.replaceFirst('^[a-z]+://', '');
        s = s.replaceFirst('^www\\.', '');
        s = s.split('[/?#:]')[0];
        return String.isBlank(s) ? null : s;
    }

    // ------------------------------------------------------------------ geography

    public static String normalizeCountry(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String key = value.trim().toLowerCase();
        return COUNTRY_ALIASES.containsKey(key) ? COUNTRY_ALIASES.get(key) : value.trim();
    }

    public static String countryFromPhone(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String p = phone.replaceAll('[^0-9+]', '');
        if (!p.startsWith('+')) {
            return null;
        }
        for (Integer len = 4; len >= 2; len--) {
            if (p.length() >= len && DIAL_CODES.containsKey(p.left(len))) {
                return DIAL_CODES.get(p.left(len));
            }
        }
        return null;
    }

    public static String countryFromDomain(String domain) {
        if (String.isBlank(domain) || !domain.contains('.')) {
            return null;
        }
        return TLD_COUNTRIES.get(domain.substringAfterLast('.'));
    }

    /** Lower-case set of the forms a state can be written in (code and name for US states). */
    public static Set<String> stateForms(String state) {
        Set<String> out = new Set<String>();
        if (String.isBlank(state)) {
            return out;
        }
        String s = state.trim().toLowerCase();
        out.add(s);
        if (US_STATES.containsKey(s)) {
            out.add(US_STATES.get(s).toLowerCase());
        }
        for (String name : US_STATES.keySet()) {
            if (US_STATES.get(name).toLowerCase() == s) {
                out.add(name);
            }
        }
        return out;
    }

    /** Postal code match against "code", "prefix*" or "low..high" entries. */
    public static Boolean postalMatches(String postal, List<String> entries) {
        if (String.isBlank(postal)) {
            return false;
        }
        String p = postal.trim().toUpperCase().replace(' ', '');
        for (String raw : entries) {
            String e = raw.trim().toUpperCase().replace(' ', '');
            if (String.isBlank(e)) {
                continue;
            }
            if (e.endsWith('*')) {
                if (p.startsWith(e.removeEnd('*'))) {
                    return true;
                }
            } else if (e.contains('..')) {
                String low = e.substringBefore('..');
                String high = e.substringAfter('..');
                String cmp = p.left(Math.max(low.length(), high.length()));
                if (cmp.isNumeric() && low.isNumeric() && high.isNumeric()) {
                    Long v = Long.valueOf(cmp);
                    if (v >= Long.valueOf(low) && v <= Long.valueOf(high)) {
                        return true;
                    }
                } else if (cmp.compareTo(low) >= 0 && cmp.compareTo(high) <= 0) {
                    return true;
                }
            } else if (p == e) {
                return true;
            }
        }
        return false;
    }
}
