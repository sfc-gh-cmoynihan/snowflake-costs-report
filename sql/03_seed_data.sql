-- Seed Data
-- Insert default recipients and schedule entries.
-- Update these values for your environment.

USE ROLE ACCOUNTADMIN;
USE SCHEMA COSTS_DB.REPORTING;

-- Default recipient (update with your email)
INSERT INTO EMAIL_RECIPIENTS (EMAIL, NAME)
SELECT 'colm.moynihan@snowflake.com', 'Colm Moynihan'
WHERE NOT EXISTS (
    SELECT 1 FROM EMAIL_RECIPIENTS WHERE EMAIL = 'colm.moynihan@snowflake.com'
);

-- Default schedule: 9am and 5pm London time
INSERT INTO REPORT_SCHEDULE (SEND_HOUR, SEND_MINUTE, DESCRIPTION)
SELECT 9, 0, 'Morning report'
WHERE NOT EXISTS (
    SELECT 1 FROM REPORT_SCHEDULE WHERE SEND_HOUR = 9 AND SEND_MINUTE = 0
);

INSERT INTO REPORT_SCHEDULE (SEND_HOUR, SEND_MINUTE, DESCRIPTION)
SELECT 17, 0, 'End of day report'
WHERE NOT EXISTS (
    SELECT 1 FROM REPORT_SCHEDULE WHERE SEND_HOUR = 17 AND SEND_MINUTE = 0
);
