trigger UserTrigger on User (after delete, after insert, after undelete, after update, before delete, before insert, before update) {
    
    //Handles all user triggers
    
    if ((trigger.isInsert || trigger.isUpdate) && trigger.isAfter){
        
        Set<Id> userIds = new Set<Id>();
        
        for (User u : trigger.new) {
            if (u.UserType == 'Standard') {
                // Add the user id to the set of ids
                userIds.add(u.Id);
            }
        }
        if (!System.isFuture() && !System.isBatch()) {
            //upsert contact records with the changes in user records
            UpsertUserContact.execute(userIds);
        }
        
    }
}
