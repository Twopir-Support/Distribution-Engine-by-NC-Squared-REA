trigger DE_TerritoryCacheTrigger on DE_Territory__c(after insert, after update, after delete) {
    // Classifier configuration changed: cached territories, stamp groups and rules are rebuilt on next use.
    DE_Cache.invalidateClassifier();
}
