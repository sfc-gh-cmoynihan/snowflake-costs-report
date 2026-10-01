-- Task: Cost Report Scheduler
-- Runs the cost report procedure on a CRON schedule.
-- Update the CRON expression and timezone as needed.

USE ROLE ACCOUNTADMIN;
USE SCHEMA COSTS_DB.REPORTING;

CREATE OR REPLACE TASK COSTS_DB.REPORTING.COST_REPORT_TASK
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = 'USING CRON 0 9,17 * * * Europe/London'
    COMMENT = 'Generates Excel cost report and emails to recipients at 9am and 5pm London time'
AS
    CALL COSTS_DB.REPORTING.GENERATE_AND_SEND_COST_REPORT();

-- Resume the task to activate it
ALTER TASK COSTS_DB.REPORTING.COST_REPORT_TASK RESUME;
