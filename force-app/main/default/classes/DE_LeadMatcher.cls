/**
 * Lead matching (classifier): Lead to Account, Lead to Contact and Lead to Lead.
 *
 * Lead to Account, in priority order: email domain of the account's contacts, account website domain
 * (personal domains never match), exact normalised company name, fuzzy company name (Jaro-Winkler
 * above the rule threshold), custom field pair. Candidates must pass the rule's Match Filter
 * conditions; ties are broken by the rule's order field (default newest LastModifiedDate).
 */
public without sharing class DE_LeadMatcher {
    public static final List<String> LEAD_FIELDS = new List<String>{ 'Email', 'Company', 'Website', 'Phone', 'IsConverted' };

    public class Candidate {
        public SObject rec;
        public Integer rank; // lower = stronger
        public String confidence;
        public Candidate(SObject rec, Integer rank, String confidence) {
            this.rec = rec;
            this.rank = rank;
            this.confidence = confidence;
        }
    }

    public static List<DE_Matching_Rule__c> rules() {
        return [
            SELECT
                Id,
                Name,
                Match_Type__c,
                Priority__c,
                Match_Email_Domain__c,
                Match_Company_Name__c,
                Fuzzy_Threshold__c,
                Match_Email__c,
                Source_Field__c,
                Target_Field__c,
                Filter_Logic__c,
                Tie_Breaker_Field__c,
                Tie_Breaker_Direction__c,
                (SELECT Id, Sequence__c, Field_API_Name__c, Operator__c, Value__c, Purpose__c FROM Conditions__r ORDER BY Sequence__c)
            FROM DE_Matching_Rule__c
            WHERE Active__c = TRUE
            ORDER BY Priority__c, Name
        ];
    }

    public static Set<String> requiredPaths(List<DE_Matching_Rule__c> rules) {
        Set<String> out = new Set<String>(LEAD_FIELDS);
        for (DE_Matching_Rule__c r : rules) {
            if (String.isNotBlank(r.Source_Field__c)) {
                out.add(r.Source_Field__c);
            }
        }
        return out;
    }

    public static void match(List<SObject> leads, Map<Id, DE_Record_Detail__c> details, List<DE_Matching_Rule__c> rules) {
        Set<String> personal = DE_Settings.personalDomains();
        for (SObject l : leads) {
            DE_Record_Detail__c d = DE_RecordDetails.ensure(details, l.Id, 'Lead');
            String domain = DE_TextMatch.emailDomain((String) l.get('Email'));
            if (domain == null) {
                domain = DE_TextMatch.websiteDomain((String) l.get('Website'));
            }
            d.Domain__c = domain;
            d.Personal_Email__c = domain != null && personal.contains(domain);
        }
        List<String> confidence = new List<String>();
        for (DE_Matching_Rule__c rule : rules) {
            if (rule.Match_Type__c == 'Lead to Account') {
                matchAccounts(leads, details, rule, personal);
            } else if (rule.Match_Type__c == 'Lead to Contact') {
                matchContacts(leads, details, rule);
            } else if (rule.Match_Type__c == 'Lead to Lead') {
                matchLeads(leads, details, rule);
            }
        }
    }

    // ------------------------------------------------------------------ helpers

    private static String tieField(DE_Matching_Rule__c rule, String objectName) {
        String f = String.isBlank(rule.Tie_Breaker_Field__c) ? 'LastModifiedDate' : rule.Tie_Breaker_Field__c;
        String c = DE_Schema.canonicalPath(objectName, f);
        return c == null ? 'LastModifiedDate' : c;
    }

    private static List<SObject> query(String objectName, Set<String> extra, DE_Matching_Rule__c rule, String whereClause, Map<String, Object> binds) {
        Set<String> paths = new Set<String>{ 'Id', 'OwnerId', 'LastModifiedDate', tieField(rule, objectName) };
        paths.addAll(extra);
        paths.addAll(DE_Conditions.recordPaths(rule.Conditions__r));
        String soql = 'SELECT ' + DE_RecordQuery.selectList(objectName, paths, null) + ' FROM ' + objectName + ' WHERE ' + whereClause + ' LIMIT 2000';
        List<SObject> rows = Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        List<SObject> out = new List<SObject>();
        DE_Conditions.Context ctx = new DE_Conditions.Context();
        for (SObject r : rows) {
            if (DE_Conditions.matches(r, rule.Conditions__r, rule.Filter_Logic__c, ctx, null)) {
                out.add(r);
            }
        }
        return out;
    }

    private static Candidate pick(List<Candidate> candidates, DE_Matching_Rule__c rule, String objectName) {
        Candidate best;
        String tf = tieField(rule, objectName);
        Boolean newest = rule.Tie_Breaker_Direction__c != 'Oldest or Lowest';
        for (Candidate c : candidates) {
            if (best == null || c.rank < best.rank) {
                best = c;
                continue;
            }
            if (c.rank == best.rank) {
                Object a = c.rec.get(tf);
                Object b = best.rec.get(tf);
                Integer cmp;
                if (a instanceof Datetime && b instanceof Datetime) {
                    Long diff = ((Datetime) a).getTime() - ((Datetime) b).getTime();
                    cmp = diff > 0 ? 1 : (diff < 0 ? -1 : 0);
                } else {
                    cmp = b == null ? 1 : DE_Conditions.compareValues(a, String.valueOf(b), System.now());
                }
                if (cmp != null && ((newest && cmp > 0) || (!newest && cmp < 0))) {
                    best = c;
                }
            }
        }
        return best;
    }

    private static String customValue(SObject lead, DE_Matching_Rule__c rule) {
        if (String.isBlank(rule.Source_Field__c) || String.isBlank(rule.Target_Field__c)) {
            return null;
        }
        try {
            Object v = DE_Conditions.readPath(lead, rule.Source_Field__c);
            return v == null || String.isBlank(String.valueOf(v)) ? null : String.valueOf(v).trim();
        } catch (Exception e) {
            return null;
        }
    }

    // ------------------------------------------------------------------ Lead to Account

    private static void matchAccounts(List<SObject> leads, Map<Id, DE_Record_Detail__c> details, DE_Matching_Rule__c rule, Set<String> personal) {
        Set<String> domains = new Set<String>();
        Set<String> prefixes = new Set<String>();
        Set<String> customValues = new Set<String>();
        for (SObject l : leads) {
            DE_Record_Detail__c d = details.get(l.Id);
            if (d.Matched_Account__c != null) {
                continue;
            }
            if (rule.Match_Email_Domain__c && d.Domain__c != null && !d.Personal_Email__c) {
                domains.add(d.Domain__c);
            }
            if (rule.Match_Company_Name__c) {
                String n = DE_TextMatch.normalizeCompany((String) l.get('Company'));
                if (String.isNotBlank(n)) {
                    prefixes.add(DE_TextMatch.firstToken(n) + '%');
                }
            }
            String cv = customValue(l, rule);
            if (cv != null) {
                customValues.add(cv);
            }
        }
        if (domains.isEmpty() && prefixes.isEmpty() && customValues.isEmpty()) {
            return;
        }
        Map<String, Set<Id>> accountsByContactDomain = new Map<String, Set<Id>>();
        Set<Id> accountIds = new Set<Id>();
        if (!domains.isEmpty()) {
            List<String> emailPatterns = new List<String>();
            for (String dm : domains) {
                emailPatterns.add('%@' + dm);
            }
            for (Contact c : [SELECT AccountId, Email FROM Contact WHERE Email LIKE :emailPatterns AND AccountId != NULL LIMIT 2000]) {
                String dm = DE_TextMatch.emailDomain(c.Email);
                if (!accountsByContactDomain.containsKey(dm)) {
                    accountsByContactDomain.put(dm, new Set<Id>());
                }
                accountsByContactDomain.get(dm).add(c.AccountId);
                accountIds.add(c.AccountId);
            }
        }
        List<String> websitePatterns = new List<String>();
        for (String dm : domains) {
            websitePatterns.add('%' + dm + '%');
        }
        String targetField = String.isBlank(rule.Target_Field__c) ? null : DE_Schema.canonicalPath('Account', rule.Target_Field__c);
        List<String> clauses = new List<String>();
        Map<String, Object> binds = new Map<String, Object>{ 'ids' => accountIds, 'web' => websitePatterns, 'names' => new List<String>(prefixes), 'custom' => customValues };
        if (!accountIds.isEmpty()) {
            clauses.add('Id IN :ids');
        }
        if (!websitePatterns.isEmpty()) {
            clauses.add('Website LIKE :web');
        }
        if (!prefixes.isEmpty()) {
            clauses.add('Name LIKE :names');
        }
        if (targetField != null && !customValues.isEmpty()) {
            clauses.add(targetField + ' IN :custom');
        }
        if (clauses.isEmpty()) {
            return;
        }
        Set<String> extra = new Set<String>{ 'Name', 'Website' };
        if (targetField != null) {
            extra.add(targetField);
        }
        List<SObject> accounts = query('Account', extra, rule, '(' + String.join(clauses, ' OR ') + ')', binds);
        Decimal threshold = (rule.Fuzzy_Threshold__c == null ? 85 : rule.Fuzzy_Threshold__c) / 100;
        for (SObject l : leads) {
            DE_Record_Detail__c d = details.get(l.Id);
            if (d.Matched_Account__c != null) {
                continue;
            }
            String leadName = DE_TextMatch.normalizeCompany((String) l.get('Company'));
            String cv = customValue(l, rule);
            List<Candidate> candidates = new List<Candidate>();
            for (SObject a : accounts) {
                Boolean domainOk = rule.Match_Email_Domain__c && d.Domain__c != null && !d.Personal_Email__c;
                if (domainOk && accountsByContactDomain.containsKey(d.Domain__c) && accountsByContactDomain.get(d.Domain__c).contains(a.Id)) {
                    candidates.add(new Candidate(a, 1, 'Exact (contact email domain)'));
                    continue;
                }
                if (domainOk && d.Domain__c == DE_TextMatch.websiteDomain((String) a.get('Website'))) {
                    candidates.add(new Candidate(a, 2, 'Exact (website domain)'));
                    continue;
                }
                if (rule.Match_Company_Name__c && String.isNotBlank(leadName)) {
                    String accName = DE_TextMatch.normalizeCompany((String) a.get('Name'));
                    if (accName == leadName) {
                        candidates.add(new Candidate(a, 3, 'Exact (company name)'));
                        continue;
                    }
                    Decimal score = DE_TextMatch.jaroWinkler(leadName, accName);
                    if (score >= threshold) {
                        candidates.add(new Candidate(a, 4, 'Fuzzy ' + (score * 100).setScale(0) + '% (company name)'));
                        continue;
                    }
                }
                if (cv != null && targetField != null && a.get(targetField) != null && String.valueOf(a.get(targetField)).equalsIgnoreCase(cv)) {
                    candidates.add(new Candidate(a, 5, 'Exact (' + rule.Source_Field__c + ')'));
                }
            }
            Candidate best = pick(candidates, rule, 'Account');
            if (best != null) {
                d.Matched_Account__c = best.rec.Id;
                d.Match_Confidence__c = ('Account: ' + best.confidence).left(80);
            }
        }
    }

    // ------------------------------------------------------------------ Lead to Contact

    private static void matchContacts(List<SObject> leads, Map<Id, DE_Record_Detail__c> details, DE_Matching_Rule__c rule) {
        Set<String> emails = new Set<String>();
        Set<String> customValues = new Set<String>();
        for (SObject l : leads) {
            if (details.get(l.Id).Matched_Contact__c != null) {
                continue;
            }
            String e = (String) l.get('Email');
            if (rule.Match_Email__c && String.isNotBlank(e)) {
                emails.add(e.trim().toLowerCase());
            }
            String cv = customValue(l, rule);
            if (cv != null) {
                customValues.add(cv);
            }
        }
        String targetField = String.isBlank(rule.Target_Field__c) ? null : DE_Schema.canonicalPath('Contact', rule.Target_Field__c);
        List<String> clauses = new List<String>();
        if (!emails.isEmpty()) {
            clauses.add('Email IN :emails');
        }
        if (targetField != null && !customValues.isEmpty()) {
            clauses.add(targetField + ' IN :custom');
        }
        if (clauses.isEmpty()) {
            return;
        }
        Set<String> extra = new Set<String>{ 'Email', 'AccountId' };
        if (targetField != null) {
            extra.add(targetField);
        }
        List<SObject> contacts = query('Contact', extra, rule, '(' + String.join(clauses, ' OR ') + ')', new Map<String, Object>{ 'emails' => emails, 'custom' => customValues });
        for (SObject l : leads) {
            DE_Record_Detail__c d = details.get(l.Id);
            if (d.Matched_Contact__c != null) {
                continue;
            }
            String e = (String) l.get('Email');
            String cv = customValue(l, rule);
            List<Candidate> candidates = new List<Candidate>();
            for (SObject c : contacts) {
                if (rule.Match_Email__c && String.isNotBlank(e) && e.equalsIgnoreCase((String) c.get('Email'))) {
                    candidates.add(new Candidate(c, 1, 'Exact (email)'));
                } else if (cv != null && targetField != null && c.get(targetField) != null && String.valueOf(c.get(targetField)).equalsIgnoreCase(cv)) {
                    candidates.add(new Candidate(c, 2, 'Exact (' + rule.Source_Field__c + ')'));
                }
            }
            Candidate best = pick(candidates, rule, 'Contact');
            if (best != null) {
                d.Matched_Contact__c = best.rec.Id;
                if (d.Matched_Account__c == null) {
                    d.Matched_Account__c = (Id) best.rec.get('AccountId');
                }
                d.Match_Confidence__c = ('Contact: ' + best.confidence).left(80);
            }
        }
    }

    // ------------------------------------------------------------------ Lead to Lead

    private static void matchLeads(List<SObject> leads, Map<Id, DE_Record_Detail__c> details, DE_Matching_Rule__c rule) {
        Set<String> emails = new Set<String>();
        Set<String> customValues = new Set<String>();
        for (SObject l : leads) {
            String e = (String) l.get('Email');
            if (rule.Match_Email__c && String.isNotBlank(e)) {
                emails.add(e.trim().toLowerCase());
            }
            String cv = customValue(l, rule);
            if (cv != null) {
                customValues.add(cv);
            }
        }
        String targetField = String.isBlank(rule.Target_Field__c) ? null : DE_Schema.canonicalPath('Lead', rule.Target_Field__c);
        List<String> clauses = new List<String>();
        if (!emails.isEmpty()) {
            clauses.add('Email IN :emails');
        }
        if (targetField != null && !customValues.isEmpty()) {
            clauses.add(targetField + ' IN :custom');
        }
        if (clauses.isEmpty()) {
            return;
        }
        Set<Id> own = new Map<Id, SObject>(leads).keySet();
        Set<String> extra = new Set<String>{ 'Email', 'CreatedDate' };
        if (targetField != null) {
            extra.add(targetField);
        }
        List<SObject> existing = query(
            'Lead',
            extra,
            rule,
            'IsConverted = false AND Id NOT IN :own AND (' + String.join(clauses, ' OR ') + ')',
            new Map<String, Object>{ 'emails' => emails, 'custom' => customValues, 'own' => own }
        );
        for (SObject l : leads) {
            DE_Record_Detail__c d = details.get(l.Id);
            if (d.Matched_Lead__c != null) {
                continue;
            }
            String e = (String) l.get('Email');
            String cv = customValue(l, rule);
            List<Candidate> candidates = new List<Candidate>();
            for (SObject x : existing) {
                if (rule.Match_Email__c && String.isNotBlank(e) && e.equalsIgnoreCase((String) x.get('Email'))) {
                    candidates.add(new Candidate(x, 1, 'Exact (email)'));
                } else if (cv != null && targetField != null && x.get(targetField) != null && String.valueOf(x.get(targetField)).equalsIgnoreCase(cv)) {
                    candidates.add(new Candidate(x, 2, 'Exact (' + rule.Source_Field__c + ')'));
                }
            }
            Candidate best = pick(candidates, rule, 'Lead');
            if (best != null) {
                d.Matched_Lead__c = best.rec.Id;
                if (d.Match_Confidence__c == null) {
                    d.Match_Confidence__c = ('Lead: ' + best.confidence).left(80);
                }
            }
        }
    }
}
