-- Returns one row per Mirth user named 'mirthadmin' (no rows = user does not exist).
-- Run against MIRTHDB, e.g.: sqlcmd -S .\SQLEXPRESS -d MIRTHDB -E -i check_user_in_mirth.sql
SET NOCOUNT ON;

SELECT p.ID,
       p.USERNAME,
       p.FIRSTNAME,
       p.LASTNAME,
       p.EMAIL,
       CASE WHEN pw.PASSWORD IS NULL THEN 0 ELSE 1 END AS HAS_PASSWORD,
       pw.PASSWORD_DATE,
       pref.VALUE AS FIRSTLOGIN,
       p.STRIKE_COUNT,
       p.LAST_LOGIN
FROM PERSON p
LEFT JOIN PERSON_PASSWORD pw
       ON pw.PERSON_ID = p.ID
      AND pw.PASSWORD_DATE = (SELECT MAX(PASSWORD_DATE) FROM PERSON_PASSWORD WHERE PERSON_ID = p.ID)
LEFT JOIN PERSON_PREFERENCE pref
       ON pref.PERSON_ID = p.ID AND pref.NAME = N'firstlogin'
WHERE p.USERNAME = N'mirthadmin';
