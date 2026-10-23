/**
 * Serialises assignment for a team. Every path that assigns records or changes rotation state
 * (scheduler, pull, manual, trigger, reassignment, rejection) locks the team row first, then
 * refreshes the counters it is about to change from the locked row.
 */
public without sharing class DE_TeamLock {
    public class LockException extends Exception {
    }

    public static void lock(DE_Model.TeamConfig cfg) {
        try {
            List<DE_Team__c> rows = [
                SELECT Id, Rotation_Sequence__c, Total_Assignments__c, Last_Assigned_At__c
                FROM DE_Team__c
                WHERE Id = :cfg.team.Id
                FOR UPDATE
            ];
            if (rows.isEmpty()) {
                throw new LockException('Team ' + cfg.team.Name + ' no longer exists.');
            }
            cfg.team.Rotation_Sequence__c = rows[0].Rotation_Sequence__c;
            cfg.team.Total_Assignments__c = rows[0].Total_Assignments__c;
            cfg.team.Last_Assigned_At__c = rows[0].Last_Assigned_At__c;
        } catch (QueryException e) {
            throw new LockException('Another assignment is in progress for team ' + cfg.team.Name + '. Try again.');
        }
    }
}
