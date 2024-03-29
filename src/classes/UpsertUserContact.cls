public with sharing class UpsertUserContact {
    @Future
    public static void execute(Set<Id> userIds) {
        
        List<Contact> contactsToUpsert = new List<Contact>(); // Create a list of contacts to upsert
        
        List <Employee_Contact_Setting__mdt> companyAcctIds = [SELECT ID__c
                                                               FROM Employee_Contact_Setting__mdt
                                                               WHERE DeveloperName =: 'Company_Account'
                                                               LIMIT 1];
        
        List<User> users =
            [SELECT Id,Email,Extension,FirstName,LastName,Department,ManagerId,Manager.LastName, 
             Fax, IsActive, Phone, MobilePhone, Title, Street, City, State, PostalCode, Country
             FROM User WHERE Id IN : userIds];
        
        Map <Id,Id> managerContactMap = new Map<Id,Id>();      // manager userId, manager contactId
        Map<ID,String> userManagersMap = new Map<ID,String>(); // manager Id, manager LastName
        
        for(User managedUser: users){
            if (managedUser.ManagerId != null){
                userManagersMap.put(managedUser.ManagerId, managedUser.Manager.LastName);
            }
        }
        
        if (!userManagersMap.isEmpty()) {
            List<Contact> managerContacts = [SELECT Id, LastName, OwnerId, Owner.LastName from Contact
                                             WHERE OwnerId =: users[0].ManagerId
                                             OR LastName =: userManagersMap.get(users[0].ManagerId)];
            
            for(Contact managerContact: managerContacts){
                if (managerContact.LastName == managerContact.Owner.LastName) {
                    managerContactMap.put(managerContact.OwnerId,managerContact.Id);
                }
            }
        }
        
        List<Contact> contacts =
            [SELECT Id, LastName, OwnerId, Owner.LastName
             FROM Contact
             WHERE (OwnerId IN: userIds
                    OR LastName =: users[0].LastName)
             AND AccountId =: companyAcctIds[0].ID__c
             ORDER BY LastModifiedDate DESC];
        
        Map <Id,Id> userContactMap = new Map <Id,Id>(); // Create a user contact map of userId, contactId
        
        for(Contact userContact: contacts){
            if (userContact.LastName == userContact.Owner.LastName) {
                userContactMap.put(userContact.OwnerId,userContact.Id);
            }
            else {
                userContactMap.put(users[0].Id,userContact.Id);
            }
        }
        
        for (User u : users){                               // Loop through each upserted user
            
            Contact c = new Contact(                        // Create a contact record in memory
                Email = u.Email,                            // Populate the email
                FirstName = u.FirstName,                    // Populate the first name
                LastName = u.LastName,                      // Populate the last name
                Department = u.Department,                  // Populate the user department
                Fax = u.Fax,                                // Populate the fax number
                Extension__c = u.Extension,          // Populate the phone extension
                Phone = u.Phone,                            // Populate the phone number
                MobilePhone = u.MobilePhone,                // Populate the mobile phone number
                Title = u.Title,                            // Populate the title of user
                MailingStreet = u.Street,                   // Populate the mailing street
                MailingCity = u.City,                       // Populate the mailing city
                MailingState = u.State,                     // Populate the mailing state
                MailingPostalCode = u.PostalCode,           // Populate the postal code
                MailingCountry = u.Country,                 // Populate the country
                OwnerId = u.Id);                            // Populate the contact owner
            if (u.IsActive == true) {
                c.Status__c = 'Active';
                c.No_Longer_There__c = false;
            } else {
                c.Status__c = 'Inactive';
                c.No_Longer_There__c = true;
            }
            if (!companyAcctIds.isEmpty()) {
                c.AccountId = companyAcctIds[0].ID__c;      // Populate the account lookup
            }
            if (managerContactMap.get(u.ManagerId) != null) {
                c.ReportsToId = managerContactMap.get(u.ManagerId); // Populate the Reports To field
            }
            if (userContactMap.get(u.Id) != null) {
                c.Id = userContactMap.get(u.Id);            // specify the contact to be updated
            }
            
            contactsToUpsert.add(c);                        // Add the contact to the bulk upsert list
            
        }
        
        if(!contactsToUpsert.isEmpty()){
            upsert contactsToUpsert;                        // Upsert all contacts in single DML statement
        }
    }
}
