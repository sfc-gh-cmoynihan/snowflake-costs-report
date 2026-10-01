-- Email Notification Integration
-- Creates or updates the email notification integration.
-- Update ALLOWED_RECIPIENTS with the email addresses that should receive reports.

USE ROLE ACCOUNTADMIN;

-- Create the integration if it doesn't exist.
-- If one already exists, update its ALLOWED_RECIPIENTS instead.
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS COST_REPORT_EMAIL_INT
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('colm.moynihan@snowflake.com');

-- To add more recipients to an existing integration:
-- ALTER NOTIFICATION INTEGRATION COST_REPORT_EMAIL_INT
--     SET ALLOWED_RECIPIENTS = ('user1@example.com', 'user2@example.com');
