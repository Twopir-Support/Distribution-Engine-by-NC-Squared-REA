/**
 * Territory classification: the first active territory (lowest order) whose country, state,
 * postal code lists and extra conditions all match. Country is detected from the address field,
 * then the phone dial code, then the email or website domain.
 */
public without sharing class DE_TerritoryClassifier {
    public class Location {
        public String country;
        public String state;
        public String postal;
    }

    public static final Map<String, List<String>> LOCATION_FIELDS = new Map<String, List<String>>{
        'lead' => new List<String>{ 'Country', 'State', 'PostalCode', 'Phone', 'Email', 'Website' },
        'account' => new List<String>{ 'BillingCountry', 'BillingState', 'BillingPostalCode', 'Phone', null, 'Website' },
        'contact' => new List<String>{ 'MailingCountry', 'MailingState', 'MailingPostalCode', 'Phone', 'Email', null },
        'opportunity' => new List<String>{ 'Account.BillingCountry', 'Account.BillingState', 'Account.BillingPostalCode', 'Account.Phone', null, 'Account.Website' },
        'case' => new List<String>{ 'Account.BillingCountry', 'Account.BillingState', 'Account.BillingPostalCode', 'SuppliedPhone', 'SuppliedEmail', 'Account.Website' }
    };

    public static List<DE_Territory__c> territories(String objectName) {
        return [
            SELECT
                Id,
                Name,
                Object_API_Name__c,
                Map__c,
                Status__c,
                Priority__c,
                Condition_Logic__c,
                Countries__c,
                States__c,
                Postal_Codes__c,
                Stamp_Field__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Territory__c
            WHERE Object_API_Name__c = :objectName AND Status__c = 'Active'
            ORDER BY Priority__c, Name
        ];
    }

    public static Set<String> requiredPaths(String objectName, List<DE_Territory__c> territories) {
        Set<String> out = new Set<String>();
        List<String> loc = LOCATION_FIELDS.get(objectName.toLowerCase());
        if (loc != null) {
            for (String f : loc) {
                if (f != null) {
                    out.add(f);
                }
            }
        }
        for (DE_Territory__c t : territories) {
            out.addAll(DE_Conditions.recordPaths(t.Conditions__r));
        }
        return out;
    }

    private static String read(SObject rec, String path) {
        if (path == null) {
            return null;
        }
        try {
            Object v = DE_Conditions.readPath(rec, path);
            return v == null ? null : String.valueOf(v);
        } catch (Exception e) {
            return null;
        }
    }

    public static Location locate(String objectName, SObject rec) {
        Location l = new Location();
        List<String> f = LOCATION_FIELDS.get(objectName.toLowerCase());
        if (f == null) {
            return l;
        }
        l.country = DE_TextMatch.normalizeCountry(read(rec, f[0]));
        l.state = read(rec, f[1]);
        l.postal = read(rec, f[2]);
        if (l.country == null) {
            l.country = DE_TextMatch.countryFromPhone(read(rec, f[3]));
        }
        if (l.country == null) {
            String domain = DE_TextMatch.emailDomain(read(rec, f[4]));
            if (domain == null) {
                domain = DE_TextMatch.websiteDomain(read(rec, f[5]));
            }
            l.country = DE_TextMatch.countryFromDomain(domain);
        }
        if (l.country == null && l.state != null && DE_TextMatch.stateForms(l.state).size() > 1) {
            l.country = 'United States';
        }
        return l;
    }

    public static Boolean matches(DE_Territory__c t, Location l, SObject rec, DE_Conditions.Context ctx) {
        List<String> countries = DE_Conditions.splitValues(t.Countries__c);
        if (!countries.isEmpty()) {
            if (l.country == null) {
                return false;
            }
            Boolean found = false;
            for (String c : countries) {
                if (DE_TextMatch.normalizeCountry(c).equalsIgnoreCase(l.country)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        List<String> states = DE_Conditions.splitValues(t.States__c);
        if (!states.isEmpty()) {
            Set<String> forms = DE_TextMatch.stateForms(l.state);
            Boolean found = false;
            for (String s : states) {
                if (forms.contains(s.trim().toLowerCase())) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        List<String> postals = DE_Conditions.splitValues(t.Postal_Codes__c);
        if (!postals.isEmpty() && !DE_TextMatch.postalMatches(l.postal, postals)) {
            return false;
        }
        return DE_Conditions.matches(rec, t.Conditions__r, t.Condition_Logic__c, ctx, null);
    }

    /** Classifies records; returns the field stamps to write back on the records (recordId -> field -> value). */
    public static Map<Id, Map<String, Object>> classify(String objectName, List<SObject> records, Map<Id, DE_Record_Detail__c> details, List<DE_Territory__c> territories) {
        Map<Id, Map<String, Object>> stamps = new Map<Id, Map<String, Object>>();
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        ctx.details = details;
        Boolean defaultField = DE_Schema.hasField(objectName, 'DE_Territory__c');
        for (SObject rec : records) {
            DE_Record_Detail__c d = DE_RecordDetails.ensure(details, rec.Id, objectName);
            Location l = locate(objectName, rec);
            DE_Territory__c found = null;
            for (DE_Territory__c t : territories) {
                if (matches(t, l, rec, ctx)) {
                    found = t;
                    break;
                }
            }
            d.Territory__c = found == null ? null : found.Id;
            d.Territory_Name__c = found == null ? null : found.Name.left(80);
            String field = found != null && String.isNotBlank(found.Stamp_Field__c) ? found.Stamp_Field__c : (defaultField ? 'DE_Territory__c' : null);
            if (field != null && DE_Schema.hasField(objectName, field)) {
                if (!stamps.containsKey(rec.Id)) {
                    stamps.put(rec.Id, new Map<String, Object>());
                }
                stamps.get(rec.Id).put(field, d.Territory_Name__c);
            }
        }
        return stamps;
    }
}
