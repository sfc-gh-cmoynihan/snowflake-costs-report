# Snowflake Cost Report

Automated Snowflake cost and usage reporting. Generates Excel reports with compute credits, user token usage, storage costs, data transfer, and credit balances, then emails them on a schedule.

## Report Sections

| Section | Metrics |
|---------|---------|
| Compute | Warehouse credits, Snowpipe, Cloud Services (today + month-to-date) |
| Users | Cortex AI token usage, credit usage per user |
| Storage | Disk and Failsafe costs |
| Data Transfer | Transfer costs |
| Totals | Total credits used, credits remaining |

## Architecture

```
COSTS_DB.REPORTING
  ├── EMAIL_RECIPIENTS     -- who receives the report
  ├── REPORT_SCHEDULE      -- reference table of send times
  ├── REPORT_STAGE         -- internal stage for generated Excel files
  ├── GENERATE_AND_SEND_COST_REPORT()  -- Python stored procedure
  └── COST_REPORT_TASK     -- CRON task (9am, 5pm Europe/London)
```

The Python stored procedure:
1. Queries `SNOWFLAKE.ACCOUNT_USAGE` and `SNOWFLAKE.ORGANIZATION_USAGE` views
2. Builds a formatted Excel workbook using `openpyxl`
3. Uploads the file to an internal stage
4. Generates a 24-hour presigned download URL
5. Sends an HTML email with a summary table and download link

## Prerequisites

- ACCOUNTADMIN role
- A warehouse (default: `COMPUTE_WH`)
- An email notification integration (see `sql/02_notification_integration.sql`)

## Installation

### Option 1: Run the install script

```bash
chmod +x install.sh
./install.sh
# or with a named SnowSQL connection:
./install.sh --connection my_conn
```

### Option 2: Run SQL files manually

Execute the SQL files in order:

```sql
-- 1. Create database, schema, tables, stage
@sql/01_setup.sql

-- 2. Create/configure email notification integration
@sql/02_notification_integration.sql

-- 3. Insert default recipients and schedule
@sql/03_seed_data.sql

-- 4. Create the Python stored procedure
@sql/04_procedure.sql

-- 5. Create and resume the scheduled task
@sql/05_task.sql
```

## Configuration

### Email Notification Integration

The procedure uses a notification integration to send emails. Update the integration name in `sql/04_procedure.sql` to match your account:

```sql
-- Check your existing integrations:
SHOW NOTIFICATION INTEGRATIONS;

-- The procedure references 'LP_EMAIL_INT' by default.
-- Change it in the SYSTEM$SEND_EMAIL call if yours is named differently.
```

### Managing Recipients

```sql
-- Add a recipient
INSERT INTO COSTS_DB.REPORTING.EMAIL_RECIPIENTS (EMAIL, NAME)
VALUES ('user@example.com', 'User Name');

-- Deactivate a recipient
UPDATE COSTS_DB.REPORTING.EMAIL_RECIPIENTS SET ACTIVE = FALSE WHERE EMAIL = 'user@example.com';

-- View all recipients
SELECT * FROM COSTS_DB.REPORTING.EMAIL_RECIPIENTS;
```

### Changing the Schedule

The task uses a CRON expression. To change the schedule:

```sql
ALTER TASK COSTS_DB.REPORTING.COST_REPORT_TASK SUSPEND;
ALTER TASK COSTS_DB.REPORTING.COST_REPORT_TASK SET SCHEDULE = 'USING CRON 0 9,13,17 * * * Europe/London';
ALTER TASK COSTS_DB.REPORTING.COST_REPORT_TASK RESUME;
```

### Running Manually

```sql
-- Call the procedure directly
CALL COSTS_DB.REPORTING.GENERATE_AND_SEND_COST_REPORT();

-- Or trigger the task
EXECUTE TASK COSTS_DB.REPORTING.COST_REPORT_TASK;
```

## Sample Report

See `samples/costs_report_sample.xlsx` for an example of the generated output.

## Project Structure

```
costs/
├── README.md
├── install.sh
├── sql/
│   ├── 01_setup.sql                  -- Database, schema, tables, stage
│   ├── 02_notification_integration.sql -- Email integration
│   ├── 03_seed_data.sql              -- Default recipients and schedule
│   ├── 04_procedure.sql             -- Python stored procedure
│   └── 05_task.sql                  -- Scheduled task
└── samples/
    └── costs_report_sample.xlsx
```
