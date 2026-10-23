/**
 * Small cache over the org platform cache partition "DE" (local.DE) with a per-transaction fallback.
 * Platform cache is optional: when the partition has no capacity, is missing, or Use Platform Cache is
 * off in Distribution Settings, values live only for the current transaction.
 * Values are stored as JSON strings so any serialisable structure (including SObjects with children) round-trips.
 */
public without sharing class DE_Cache {
    public static final String PARTITION = 'local.DE';
    private static final Integer TTL_SECONDS = 3600;
    private static final String CLASSIFIER_VERSION_KEY = 'clsversion';
    private static Map<String, String> transactionCache = new Map<String, String>();

    private static Cache.OrgPartition partition() {
        if (!DE_Settings.usePlatformCache()) {
            return null;
        }
        try {
            return Cache.Org.getPartition(PARTITION);
        } catch (Exception e) {
            return null;
        }
    }

    /** Cache keys must be alphanumeric. */
    public static String key(String raw) {
        return raw == null ? 'null' : raw.replaceAll('[^A-Za-z0-9]', '');
    }

    public static String get(String rawKey) {
        String k = key(rawKey);
        if (transactionCache.containsKey(k)) {
            return transactionCache.get(k);
        }
        Cache.OrgPartition p = partition();
        if (p == null) {
            return null;
        }
        try {
            Object v = p.get(k);
            if (v instanceof String) {
                transactionCache.put(k, (String) v);
                return (String) v;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.FINE, 'Platform cache unavailable: ' + e.getMessage());
        }
        return null;
    }

    public static void put(String rawKey, String value) {
        String k = key(rawKey);
        transactionCache.put(k, value);
        Cache.OrgPartition p = partition();
        if (p == null || value == null) {
            return;
        }
        try {
            p.put(k, value, TTL_SECONDS);
        } catch (Exception e) {
            // No capacity or value too large: the transaction cache still serves this transaction.
            System.debug(LoggingLevel.FINE, 'Platform cache put skipped: ' + e.getMessage());
        }
    }

    public static void remove(String rawKey) {
        String k = key(rawKey);
        transactionCache.remove(k);
        Cache.OrgPartition p = partition();
        if (p == null) {
            return;
        }
        try {
            p.remove(k);
        } catch (Exception e) {
            System.debug(LoggingLevel.FINE, 'Platform cache remove skipped: ' + e.getMessage());
        }
    }

    // ------------------------------------------------------------------ classifier configuration

    /** Version stamp included in every classifier cache key; changing it invalidates them all at once. */
    public static String classifierVersion() {
        String v = get(CLASSIFIER_VERSION_KEY);
        if (v == null) {
            v = String.valueOf(System.now().getTime());
            put(CLASSIFIER_VERSION_KEY, v);
        }
        return v;
    }

    public static String classifierKey(String kind, String objectName) {
        return 'cls' + classifierVersion() + kind + (objectName == null ? '' : objectName);
    }

    /** Called whenever territories, stamp groups, stamps, matching or conversion rules change. */
    public static void invalidateClassifier() {
        transactionCache.clear();
        put(CLASSIFIER_VERSION_KEY, String.valueOf(System.now().getTime()) + String.valueOf(Crypto.getRandomInteger()));
    }
}
