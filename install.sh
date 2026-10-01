#!/bin/bash
# install.sh - Deploy the Snowflake Cost Report to your account
#
# Prerequisites:
#   - SnowSQL CLI installed and configured
#   - ACCOUNTADMIN role access
#   - An email notification integration (the procedure references 'LP_EMAIL_INT')
#
# Usage:
#   ./install.sh                          # uses default SnowSQL connection
#   ./install.sh --connection my_conn     # uses a named SnowSQL connection

set -e

CONNECTION_FLAG=""
if [ "$1" = "--connection" ] && [ -n "$2" ]; then
    CONNECTION_FLAG="--connection $2"
fi

echo "=== Snowflake Cost Report Installer ==="
echo ""
echo "This will create the following in your Snowflake account:"
echo "  - Database: COSTS_DB"
echo "  - Schema: COSTS_DB.REPORTING"
echo "  - Tables: EMAIL_RECIPIENTS, REPORT_SCHEDULE"
echo "  - Stage: REPORT_STAGE"
echo "  - Procedure: GENERATE_AND_SEND_COST_REPORT()"
echo "  - Task: COST_REPORT_TASK (9am, 5pm Europe/London)"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "[1/5] Creating database, schema, tables, and stage..."
snowsql $CONNECTION_FLAG -f sql/01_setup.sql

echo "[2/5] Creating notification integration..."
snowsql $CONNECTION_FLAG -f sql/02_notification_integration.sql

echo "[3/5] Seeding default data..."
snowsql $CONNECTION_FLAG -f sql/03_seed_data.sql

echo "[4/5] Creating stored procedure..."
snowsql $CONNECTION_FLAG -f sql/04_procedure.sql

echo "[5/5] Creating and resuming task..."
snowsql $CONNECTION_FLAG -f sql/05_task.sql

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Verify your notification integration name in sql/04_procedure.sql"
echo "     (default: LP_EMAIL_INT). Run SHOW NOTIFICATION INTEGRATIONS to check."
echo "  2. Add recipients:"
echo "     INSERT INTO COSTS_DB.REPORTING.EMAIL_RECIPIENTS (EMAIL, NAME)"
echo "     VALUES ('user@example.com', 'User Name');"
echo "  3. Send a test report:"
echo "     CALL COSTS_DB.REPORTING.GENERATE_AND_SEND_COST_REPORT();"
echo "  4. Or trigger the task immediately:"
echo "     EXECUTE TASK COSTS_DB.REPORTING.COST_REPORT_TASK;"
