# salesforce-user-contacts
*An employee contact record for every Salesforce user*

There are a number of reasons why it might be helpful for every Salesforce user to have a related contact record that is updated whenever certain user fields are updated. A couple of those reasons might be:

* using cases for internal support (to benefit from case contact functionality)
* making the built-in contact hierarchy org chart work for your company

Prerequisites:

* custom picklist field called Status (Status__c) on the contact object with values of 'Active' and 'Inactive'
* custom metadata type of Employee Contact Setting (Employee_Contact_Setting__mdt) with custom field of ID (ID__c) and record called Company Account (Company_Account)


<a href="https://githubsfdeploy.herokuapp.com">
  <img alt="Deploy to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>
