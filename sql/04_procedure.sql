-- Stored Procedure: Generate and Send Cost Report
-- Python procedure that queries Snowflake usage views, generates an Excel report,
-- uploads it to a stage, and emails a download link to all active recipients.
--
-- IMPORTANT: Update the notification integration name below to match your account.
-- The default is 'LP_EMAIL_INT'. Change it to match your SHOW NOTIFICATION INTEGRATIONS output.

USE ROLE ACCOUNTADMIN;
USE SCHEMA COSTS_DB.REPORTING;

CREATE OR REPLACE PROCEDURE COSTS_DB.REPORTING.GENERATE_AND_SEND_COST_REPORT()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'openpyxl')
HANDLER = 'main'
EXECUTE AS CALLER
AS
$$
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from datetime import datetime
import io

def main(session):
    wh_today = session.sql("""
        SELECT WAREHOUSE_NAME AS COMPUTE, ROUND(SUM(CREDITS_USED), 2) AS TODAYS_USAGE
        FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
        WHERE START_TIME >= CURRENT_DATE() GROUP BY WAREHOUSE_NAME ORDER BY TODAYS_USAGE DESC
    """).collect()
    wh_total = session.sql("""
        SELECT WAREHOUSE_NAME, ROUND(SUM(CREDITS_USED), 2) AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
        WHERE START_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE()) GROUP BY WAREHOUSE_NAME
    """).collect()
    wh_total_map = {r["WAREHOUSE_NAME"]: float(r["TOTAL_CREDITS"]) for r in wh_total}

    pipe_today = session.sql("""
        SELECT ROUND(COALESCE(SUM(CREDITS_USED), 0), 2) AS TODAYS_USAGE
        FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY WHERE START_TIME >= CURRENT_DATE()
    """).collect()
    pipe_total = session.sql("""
        SELECT ROUND(COALESCE(SUM(CREDITS_USED), 0), 2) AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY WHERE START_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE())
    """).collect()

    cs_today = session.sql("""
        SELECT ROUND(COALESCE(SUM(CREDITS_USED_CLOUD_SERVICES), 0), 2) AS TODAYS_USAGE
        FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY WHERE START_TIME >= CURRENT_DATE()
    """).collect()
    cs_total = session.sql("""
        SELECT ROUND(COALESCE(SUM(CREDITS_USED_CLOUD_SERVICES), 0), 2) AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY WHERE START_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE())
    """).collect()

    user_tokens = session.sql("""
        WITH all_tokens AS (
            SELECT USER_NAME, USAGE_TIME AS TS, TOKENS FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_CODE_DESKTOP_USAGE_HISTORY
            WHERE USAGE_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE()) AND USER_NAME IS NOT NULL AND USER_NAME != ''
            UNION ALL
            SELECT USER_NAME, START_TIME AS TS, TOKENS FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY
            WHERE START_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE()) AND USER_NAME IS NOT NULL AND USER_NAME != ''
            UNION ALL
            SELECT u.NAME AS USER_NAME, h.START_TIME AS TS, h.TOKENS
            FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_REST_API_USAGE_HISTORY h
            JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
            WHERE h.START_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE()) AND u.NAME IS NOT NULL AND u.NAME != ''
        )
        SELECT USER_NAME, SUM(CASE WHEN TS >= CURRENT_DATE() THEN TOKENS ELSE 0 END) AS TOKENS_TODAY,
               SUM(TOKENS) AS TOKENS_MTD
        FROM all_tokens GROUP BY USER_NAME ORDER BY TOKENS_MTD DESC
    """).collect()
    user_tokens_today_map = {r["USER_NAME"]: int(r["TOKENS_TODAY"]) for r in user_tokens}

    user_today = session.sql("""
        SELECT USER_NAME AS USERS, ROUND(COALESCE(SUM(CREDITS_USED_CLOUD_SERVICES), 0), 4) AS CREDIT_USAGE
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY WHERE START_TIME >= CURRENT_DATE()
        GROUP BY USER_NAME ORDER BY CREDIT_USAGE DESC
    """).collect()
    user_total = session.sql("""
        SELECT USER_NAME, ROUND(COALESCE(SUM(CREDITS_USED_CLOUD_SERVICES), 0), 4) AS TOTAL_CREDITS
        FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY WHERE START_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE()) GROUP BY USER_NAME
    """).collect()
    user_total_map = {r["USER_NAME"]: float(r["TOTAL_CREDITS"]) for r in user_total}
    all_users = set()
    for r in user_today: all_users.add(r["USERS"])
    for u in user_tokens_today_map: all_users.add(u)

    storage = session.sql("""
        SELECT ROUND(COALESCE(AVG(STORAGE_BYTES), 0) / POWER(1024, 4) * 23, 2) AS DISK_COST_TODAY,
               ROUND(COALESCE(AVG(FAILSAFE_BYTES), 0) / POWER(1024, 4) * 23, 2) AS FAILSAFE_COST_TODAY
        FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE WHERE USAGE_DATE = CURRENT_DATE()
    """).collect()
    storage_total = session.sql("""
        SELECT ROUND(COALESCE(AVG(STORAGE_BYTES), 0) / POWER(1024, 4) * 23, 2) AS DISK_COST_TOTAL,
               ROUND(COALESCE(AVG(FAILSAFE_BYTES), 0) / POWER(1024, 4) * 23, 2) AS FAILSAFE_COST_TOTAL
        FROM SNOWFLAKE.ACCOUNT_USAGE.STORAGE_USAGE WHERE USAGE_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE())
    """).collect()

    transfer = session.sql("""
        SELECT ROUND(COALESCE(SUM(BYTES_TRANSFERRED), 0) / POWER(1024, 4) * 20, 2) AS TRANSFER_COST_TODAY
        FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_TRANSFER_HISTORY WHERE START_TIME >= CURRENT_DATE()
    """).collect()
    transfer_total = session.sql("""
        SELECT ROUND(COALESCE(SUM(BYTES_TRANSFERRED), 0) / POWER(1024, 4) * 20, 2) AS TRANSFER_COST_TOTAL
        FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_TRANSFER_HISTORY WHERE START_TIME >= DATE_TRUNC('MONTH', CURRENT_DATE())
    """).collect()

    total_credits = session.sql("""
        SELECT ROUND(COALESCE(SUM(CREDITS_USED), 0), 2) AS TOTAL_TODAY
        FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY WHERE USAGE_DATE = CURRENT_DATE()
    """).collect()
    total_credits_month = session.sql("""
        SELECT ROUND(COALESCE(SUM(CREDITS_USED), 0), 2) AS TOTAL_MONTH
        FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY WHERE USAGE_DATE >= DATE_TRUNC('MONTH', CURRENT_DATE())
    """).collect()

    remaining = session.sql("""
        SELECT ROUND(COALESCE(FREE_USAGE_BALANCE, 0) + COALESCE(CAPACITY_BALANCE, 0)
               + COALESCE(ON_DEMAND_CONSUMPTION_BALANCE, 0) + COALESCE(ROLLOVER_BALANCE, 0), 2) AS REMAINING
        FROM SNOWFLAKE.ORGANIZATION_USAGE.REMAINING_BALANCE_DAILY ORDER BY DATE DESC LIMIT 1
    """).collect()

    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Cost Report"
    hf = Font(bold=True, color="FFFFFF", size=11)
    hfill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
    cfmt = "#,##0.00"; dfmt = "$#,##0.00"; tokfmt = "#,##0"
    tb = Border(left=Side(style="thin", color="D9D9D9"), right=Side(style="thin", color="D9D9D9"),
                top=Side(style="thin", color="D9D9D9"), bottom=Side(style="thin", color="D9D9D9"))
    ws.column_dimensions["A"].width = 30; ws.column_dimensions["B"].width = 18
    ws.column_dimensions["C"].width = 20; ws.column_dimensions["D"].width = 22

    now = datetime.now()
    report_date = now.strftime("%d %b %Y @%H:%M")
    excel_title = "Snowflake Costs Report - " + report_date
    hour = now.hour
    if hour == 0: time_str = "12am"
    elif hour < 12: time_str = str(hour) + "am"
    elif hour == 12: time_str = "12pm"
    else: time_str = str(hour - 12) + "pm"
    email_title = "Snowflake Costs Report " + now.strftime("%d-%b-%Y") + " Time = " + time_str

    ws.merge_cells("A1:D1")
    ws["A1"] = excel_title
    ws["A1"].font = Font(bold=True, size=14, color="2F5496")
    row = 3

    def write_hdr(ws, row, headers):
        for col, h in enumerate(headers, 1):
            c = ws.cell(row=row, column=col, value=h)
            c.font = hf; c.fill = hfill; c.alignment = Alignment(horizontal="center"); c.border = tb
        return row + 1
    def write_r(ws, row, values, fmts=None):
        for col, v in enumerate(values, 1):
            c = ws.cell(row=row, column=col, value=v); c.border = tb
            if fmts and col <= len(fmts) and fmts[col-1]: c.number_format = fmts[col-1]
        return row + 1
    def sf(val, default=0):
        try: return float(val) if val is not None else default
        except: return default

    row = write_hdr(ws, row, ["Compute", "Type", "Today's Usage", "Total Credits to Date"])
    for r in wh_today:
        row = write_r(ws, row, [r["COMPUTE"], "Warehouse", sf(r["TODAYS_USAGE"]), wh_total_map.get(r["COMPUTE"], 0)], [None, None, cfmt, cfmt])
    row = write_r(ws, row, ["", "Snowpipe", sf(pipe_today[0]["TODAYS_USAGE"]) if pipe_today else 0, sf(pipe_total[0]["TOTAL_CREDITS"]) if pipe_total else 0], [None, None, cfmt, cfmt])
    row = write_r(ws, row, ["", "Cloud Services", sf(cs_today[0]["TODAYS_USAGE"]) if cs_today else 0, sf(cs_total[0]["TOTAL_CREDITS"]) if cs_total else 0], [None, None, cfmt, cfmt])
    row += 1

    row = write_hdr(ws, row, ["Users", "Token Usage", "Credit Usage", "Total Credits to Date"])
    ucm = {r["USERS"]: sf(r["CREDIT_USAGE"]) for r in user_today}
    for user in sorted(all_users):
        row = write_r(ws, row, [user, user_tokens_today_map.get(user, 0), ucm.get(user, 0), user_total_map.get(user, 0)], [None, tokfmt, cfmt, cfmt])
    row += 1

    dtv = sf(storage[0]["DISK_COST_TODAY"]) if storage else 0; dtov = sf(storage_total[0]["DISK_COST_TOTAL"]) if storage_total else 0
    ftv = sf(storage[0]["FAILSAFE_COST_TODAY"]) if storage else 0; ftov = sf(storage_total[0]["FAILSAFE_COST_TOTAL"]) if storage_total else 0
    row = write_hdr(ws, row, ["Storage", "", "Today's Costs", "Total Costs to Date"])
    row = write_r(ws, row, ["DISK", "", dtv, dtov], [None, None, dfmt, dfmt])
    row = write_r(ws, row, ["FAILSAFE", "", ftv, ftov], [None, None, dfmt, dfmt])
    row += 1

    xtv = sf(transfer[0]["TRANSFER_COST_TODAY"]) if transfer else 0; xtov = sf(transfer_total[0]["TRANSFER_COST_TOTAL"]) if transfer_total else 0
    row = write_hdr(ws, row, ["Data Transfer", "", "Today's Costs", "Total Costs to Date"])
    row = write_r(ws, row, ["Data Transfer", "", xtv, xtov], [None, None, dfmt, dfmt])
    row += 1

    ctv = sf(total_credits[0]["TOTAL_TODAY"]) if total_credits else 0
    cmv = sf(total_credits_month[0]["TOTAL_MONTH"]) if total_credits_month else 0
    rv = sf(remaining[0]["REMAINING"]) if remaining else 0
    row = write_hdr(ws, row, ["Totals", "", "Today's Costs", "Total Costs to Date"])
    row = write_r(ws, row, ["Credits Usage", "", ctv, cmv], [None, None, cfmt, cfmt])
    row = write_r(ws, row, ["Credits Remaining", "", "", rv], [None, None, None, cfmt])

    buf = io.BytesIO(); wb.save(buf); buf.seek(0)
    ts = now.strftime("%Y%m%d_%H%M%S")
    fname = "costs_report_" + ts + ".xlsx"
    session.file.put_stream(buf, "@COSTS_DB.REPORTING.REPORT_STAGE/" + fname, auto_compress=False, overwrite=True)

    url_r = session.sql("SELECT GET_PRESIGNED_URL(@COSTS_DB.REPORTING.REPORT_STAGE, '" + fname + "', 86400) AS URL").collect()
    dl_url = url_r[0]["URL"] if url_r else "URL generation failed"

    recips = session.sql("SELECT EMAIL FROM COSTS_DB.REPORTING.EMAIL_RECIPIENTS WHERE ACTIVE = TRUE").collect()
    recip_list = ",".join([r["EMAIL"] for r in recips])
    if not recip_list: return "No active recipients found"

    body = (
        '<html><body style="font-family: Arial, sans-serif; color: #333;">'
        '<h2 style="color: #2F5496;">' + email_title + '</h2>'
        '<h3>Summary</h3>'
        '<table style="border-collapse: collapse; width: 400px;">'
        '<tr style="background-color: #2F5496; color: white;">'
        '<td style="padding: 8px; border: 1px solid #ddd;"><strong>Metric</strong></td>'
        '<td style="padding: 8px; border: 1px solid #ddd; text-align: right;"><strong>Today</strong></td>'
        '<td style="padding: 8px; border: 1px solid #ddd; text-align: right;"><strong>Month to Date</strong></td></tr>'
        '<tr><td style="padding: 8px; border: 1px solid #ddd;">Credits Used</td>'
        '<td style="padding: 8px; border: 1px solid #ddd; text-align: right;">' + "{:,.2f}".format(ctv) + '</td>'
        '<td style="padding: 8px; border: 1px solid #ddd; text-align: right;">' + "{:,.2f}".format(cmv) + '</td></tr>'
        '<tr><td style="padding: 8px; border: 1px solid #ddd;">Storage (Disk)</td>'
        '<td style="padding: 8px; border: 1px solid #ddd; text-align: right;">$' + "{:,.2f}".format(dtv) + '</td>'
        '<td style="padding: 8px; border: 1px solid #ddd; text-align: right;">$' + "{:,.2f}".format(dtov) + '</td></tr>'
        '<tr><td style="padding: 8px; border: 1px solid #ddd;">Credits Remaining</td>'
        '<td style="padding: 8px; border: 1px solid #ddd; text-align: right;" colspan="2">' + "{:,.2f}".format(rv) + '</td></tr>'
        '</table>'
        '<p><a href="' + dl_url + '" style="background-color: #2F5496; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; margin-top: 10px;">Download Full Report (Excel)</a></p>'
        '<p style="color: #666; font-size: 12px;">Link expires in 24 hours. Generated by COSTS_DB.REPORTING.</p>'
        '</body></html>'
    )
    body_escaped = body.replace("'", "''")
    session.sql("CALL SYSTEM$SEND_EMAIL('LP_EMAIL_INT', '" + recip_list + "', '" + email_title + "', '" + body_escaped + "', 'text/html')").collect()
    return "Report generated and emailed to " + recip_list + ". File: " + fname
$$;
