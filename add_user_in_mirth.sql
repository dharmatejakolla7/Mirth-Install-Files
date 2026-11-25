-- Creates the Mirth user 'mirthadmin' with password 'mirthadmin', or resets it if it already exists.
-- Also sets firstlogin=false so the Administrator does not show the "customize your account" dialog.
-- Run against MIRTHDB, e.g.: sqlcmd -S .\SQLEXPRESS -d MIRTHDB -E -b -i add_user_in_mirth.sql
--
-- @PasswordHash is 'mirthadmin' in Mirth 4.5's default format: base64(8-byte salt + PBKDF2-HMAC-SHA256,
-- 600000 iterations, 32 bytes). Changing the password means generating a new hash; it cannot be typed in.
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Username     nvarchar(40)  = N'mirthadmin';
DECLARE @PasswordHash nvarchar(255) = N'ybAypOMdNWZq7V5vuPgSbdrc7hBp+rOB5DqNm+9j10whHpfNH0Qc6A==';
DECLARE @UserId       int;

BEGIN TRANSACTION;

SELECT @UserId = ID FROM PERSON WITH (UPDLOCK, HOLDLOCK) WHERE USERNAME = @Username;

IF @UserId IS NULL
BEGIN
    INSERT INTO PERSON (USERNAME, FIRSTNAME, LASTNAME, ORGANIZATION, EMAIL, STRIKE_COUNT, LOGGED_IN, USERCONSENT)
    VALUES (@Username, N'mirth', N'admin', N'admin', N'admin@mail.com', 0, 0, 0);
    SET @UserId = SCOPE_IDENTITY();
END
ELSE
BEGIN
    UPDATE PERSON
    SET STRIKE_COUNT = 0, LAST_STRIKE_TIME = NULL, GRACE_PERIOD_START = NULL
    WHERE ID = @UserId;
END

DELETE FROM PERSON_PASSWORD WHERE PERSON_ID = @UserId;
INSERT INTO PERSON_PASSWORD (PERSON_ID, PASSWORD, PASSWORD_DATE) VALUES (@UserId, @PasswordHash, GETDATE());

DELETE FROM PERSON_PREFERENCE WHERE PERSON_ID = @UserId AND NAME = N'firstlogin';
INSERT INTO PERSON_PREFERENCE (PERSON_ID, NAME, VALUE) VALUES (@UserId, N'firstlogin', N'false');

COMMIT TRANSACTION;

SELECT @UserId AS ID, @Username AS USERNAME;
