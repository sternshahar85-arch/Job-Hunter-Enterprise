/**
 * @description       : Master Trigger for Job_Application__c object.
 *                      Delegates logic to JobApplicationTriggerHandler to ensure
 *                      separation of concerns and testability.
 * @author            : Shahar Stern
 * @group             : Triggers
 * @last modified on  : 02-13-2026
 * @last modified by  : Shahar Stern
**/
trigger JobApplicationTrigger on Job_Application__c (before insert, before update, after insert, after update) {
    
    if (Trigger.isBefore) {
        JobApplicationTriggerHandler.handleBeforeInsertUpdate(Trigger.new);
    }

    if (Trigger.isAfter) {
        JobApplicationTriggerHandler.handleAfterInsertUpdate(Trigger.new, Trigger.oldMap);
    }
}