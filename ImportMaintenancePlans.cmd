@echo off
setlocal enabledelayedexpansion

::: Version 2.23.12.2025 Test realease
::: (C) 2025 by Borizz.K (borizz.k@gmail.com) - https://github.com/BorizzK

:init

	echo Import Maintenance plans to MS SQL Servers.
	::: List of servers.
	::set "SQL_SERVERS=SQLSERVER1;SQLSERVER2;"
	::set "SQL_SERVERS=%SQL_SERVERS%;%COMPUTERNAME%;"
	set "SQL_SERVERS=%COMPUTERNAME%"

	sqlcmd -? >nul 2>&1
	if %errorlevel% == 9009 (
		echo ERROR: Sqlcmd is missing. Terminating.
		exit /b 1
	)
	bcp -? -? >nul 2>&1
	if %errorlevel% == 9009 (
		echo ERROR: Bcp is missing. Terminating.
		exit /b 2
	)
	net session >nul 2>&1 || (
		echo ERROR: Administrator or system rights required. Terminating.
		exit /b 3
	)

:var
	set "errlvl=0"
	set "RunPath=%~dp0"
	set "RunPath=%RunPath:~0,-1%"
	set "IMPORT_DIR=D:\SERVER\SQL"
	if not exist "%IMPORT_DIR%" set "IMPORT_DIR=D:\SERVER\SQL_SRV"
	if not exist "%IMPORT_DIR%" (
		set "IMPORT_DIR=%RunPath%"
	)
	:::if not exist "%IMPORT_DIR%" mkdir "%IMPORT_DIR%"
	if not exist "%IMPORT_DIR%" (
		echo ERROR: Directory '%IMPORT_DIR%' is not accessible. Terminating.
		exit /b 3
	)
	set /a "DTSXProcessed=0"
	set "SQL_SERVER="
	set "PG_SQL_SERVERS="
	set "PLAN_NAME="
	set "PLAN_DTSID="
	set "P_SQL_SERVER="
	set /a "stoken=0"

:begin

	echo Working dir: '%RunPath%'
	echo Root import dir: '%IMPORT_DIR%'
	echo All .dtsx files in '%IMPORT_DIR%' will be impotred.

	:procservers
		set /a "stoken+=1"
		set "P_SQL_SERVER="
		set "SQL_SERVER="
		for /f "tokens=%stoken% delims=; " %%i in ("%SQL_SERVERS%") do set "P_SQL_SERVER=%%~i"
		if defined P_SQL_SERVER (
			set "SQL_SERVER=!P_SQL_SERVER!"
			echo Try to processing server %stoken%: '!SQL_SERVER!'
			if defined PG_SQL_SERVERS (
				echo "!PG_SQL_SERVERS!" | find /i "!P_SQL_SERVER!;" >nul 2>&1 && (
					echo Processing server %stoken%: '!P_SQL_SERVER!' already processed.
					goto :procservers
				)
			)
			if defined PG_SQL_SERVERS (
				set "PG_SQL_SERVERS=!SQL_SERVER!;!PG_SQL_SERVERS!"
			) else (
				set "PG_SQL_SERVERS=!SQL_SERVER!;"
			)
			ping -n 2 !SQL_SERVER!  >nul 2>&1
			sqlcmd -S !SQL_SERVER! -E -l 3 -Q "SELECT 1" >nul 2>&1 && (
				echo Processing server %stoken%: '!P_SQL_SERVER!'
				call :importplans "!SQL_SERVER!"
			) || (
				echo Processing server %stoken%: '!P_SQL_SERVER!': the server is unavailable. Skip.
			)
			ping -n 2 127.0.0.1 >nul 2>&1
			echo Processed list: '!PG_SQL_SERVERS!'
		) else (
			goto :procserversend
		)
		goto :procservers
	:procserversend

	echo Servers processed: '%PG_SQL_SERVERS%'
	echo DTSX files processed: '%DTSXProcessed%'

:end
goto :exit

:importplans

	echo Import Plans to '%SQL_SERVER%' from dir '%IMPORT_DIR%\%SQL_SERVER%'

	dir /b "%IMPORT_DIR%\%SQL_SERVER%\*.dtsx" >nul 2>&1 || (
		echo No DTSX files in '%IMPORT_DIR%\%SQL_SERVER%' - Skip.
		goto :importplansend
	)

	echo Checking MsDtsServer [SSIS] on %SQL_SERVER%...
	set "MsDtsServer="
	set "UseMsDtsServer=false"
	set "experrlvl=8"
	for /f "tokens=2 delims=: " %%m in ('sc \\%SQL_SERVER% query ^| find /i "SERVICE_NAME:" ^| find /i "MsDtsServer" 2^>nul') do set "MsDtsServer=%%~m"
	if defined MsDtsServer (
		sc \\%SQL_SERVER% query "%MsDtsServer%" 2>nul | find /i "STATE" | find /i ":" >nul 2>&1 && (
			sc \\%SQL_SERVER% config "%MsDtsServer%" start= demand >nul 2>&1
			sc \\%SQL_SERVER% start "%MsDtsServer%" >nul 2>&1
			set "experrlvl=!errorlevel!"
			if "!experrlvl!" == "0" set "UseMsDtsServer=true"
			if "!experrlvl!" == "1056" set "UseMsDtsServer=true"
		)
	)
	dtutil /? 2>nul | find "Server" >nul 2>&1 || set "UseMsDtsServer=false"
	if /i "%UseMsDtsServer%" == "true" (
		echo Using dtutil [SSIS] [dtutil:%UseMsDtsServer%]...
	) else (
		echo Using sqlcmd/bcp [SQL] [dtutil:%UseMsDtsServer%]...
	)

	for %%F in ("%IMPORT_DIR%\%SQL_SERVER%\*.dtsx") do (
		set "PLAN_NAME="
		set "PLAN_DTSID="
		call :readfile "%%~F"
		set /a "DTSXProcessed+=1"
		if defined PLAN_NAME (
			call :processingPlan "!PLAN_NAME!" "!PLAN_DTSID!" "%%~F"
		)
	)

:importplansend
goto :eof

:readfile

	set "PLAN_NAME="
	set "PLAN_DTSID="
	set "FILE=%~1"
	set "LINE="

	echo Processing file '%FILE%'

	for /f "tokens=*" %%i in ('type "%FILE%" 2^>nul ^| find /i "DTS:ObjectName" ') do (
		set "LINE=%%i"
		if defined LINE goto :got_line
	)
	:got_line

	echo "%LINE%" | find /i "DTS:DTSID" 2>nul | find /i "DTS:ObjectName" >nul 2>&1 && (
		rem If first line full header of XML (exported with sqlcmd/bcp) - parse as one line
		call :readfileSQL
	) || (
		rem Find and parse DTS:ObjectName (in header)
		call :readfileSSIS "%FILE%"
	)

:readfileend
goto :eof

:readfileSSIS

	echo Reading: 'SSIS' plan dtsid and name.
	set "PLAN_NAME="
	set "PLAN_DTSID="
	for /f "tokens=2 delims==" %%i in ('type "%~1" 2^>nul ^| find /i "DTS:DTSID"') do (
		if not defined PLAN_DTSID set "PLAN_DTSID=%%~i"
	)
	for /f "tokens=2 delims==" %%i in ('type "%~1" 2^>nul ^| find /i "DTS:ObjectName"') do (
		if not defined PLAN_NAME set "PLAN_NAME=%%~i"
	)

:readfileSSISend
goto :eof

:readfileSQL

	echo Reading: 'SQL' plan dtsid and name.
	set "PLAN_DTSID="
	set "PLAN_NAME="

	set /a "token=0"
	set "dLine="
	set "nLine="
	:parse_line_SQL
		set "pLine="
		set /a "token+=1"
		for /f "tokens=%token% delims= " %%i in ("%LINE%") do set "pLine=%%~i"
		if not defined pLine goto :parse_line_SQL_end
		set "pLine=%pLine:<=%">nul 2>&1
		set "pLine=%pLine:>=%">nul 2>&1
		set "pLine=%pLine:"=%">nul 2>&1
		if defined pLine (
			echo "%pLine%" | find /i "DTS:DTSID=" >nul 2>&1 && (
				if not defined dLine for /f "tokens=2 delims==" %%L in ("%pLine%") do set "dLine=%%~L"
			)
			echo "%pLine%" | find /i "DTS:ObjectName=" >nul 2>&1 && (
				if not defined nLine for /f "tokens=2 delims==" %%L in ("%pLine%") do set "nLine=%%~L"
			)
			if defined dLine if defined nLine goto :parse_line_SQL_end
		)
		goto :parse_line_SQL
	:parse_line_SQL_end
	
	if not defined nLine goto :readfileSQLend
	set "PLAN_DTSID=%dLine%"
	set "PLAN_NAME=%nLine%"
		
:readfileSQLend
goto :eof

:processingPlan
	set "tempPlanName=%~1"
	set "tempPlanDTSID=%~2"
	set "planDTSXFile=%~3"
	echo Processing Plan: Name: '%tempPlanName%', Dtsid: '%tempPlanDTSID%' from file: '%planDTSXFile%'
	set "EXISTS="
	for /f "usebackq tokens=*" %%P in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT name FROM dbo.sysssispackages WHERE name='%tempPlanName%'" 2^>nul`) do set "EXISTS=%%~P"
	if defined EXISTS call :trim_loop %EXISTS%
	if defined EXISTS if "%tempPlanName%" == "%EXISTS%" (
		echo WARNING: Plan already exists: Name: '%tempPlanName%': Existing plan name: '%EXISTS%'. Remove existng plan before import. Skip.
		set "EXISTS="
		goto :processingPlanEnd
	)
	for /f "usebackq tokens=*" %%S in (`sqlcmd -S %SQL_SERVER% -d msdb -E -Q "SET NOCOUNT ON; DECLARE @DTSID NVARCHAR(50)='%tempPlanDTSID%'; SELECT name,'DTSID' AS MatchType FROM dbo.sysssispackages WHERE packagetype=6 AND CAST(packagedata AS VARBINARY(MAX)) LIKE CAST('%%'+@DTSID+'%%' AS VARBINARY(MAX))" 2^>nul ^| find /i "DTSID"`) do set "EXISTS=%%~S"
	if defined EXISTS (
		set "EXISTS=%EXISTS:DTSID=%"
		call :trim_loop !EXISTS!
	)
	if defined EXISTS (
		echo WARNING: Plan already exists with other name: Dtsid: '%tempPlanDTSID%': Existing plan name: '%EXISTS%'. Remove existng plan before import. Skip.
		set "EXISTS="
		goto :processingPlanEnd
	)
	::: DISABLED BLOCK
	::: 	if defined EXISTS if "%tempPlanName%" == "%EXISTS%" (
	::: 		echo WARNING. Plan already exists: '%tempPlanName%': '%EXISTS%'
	::: 		set "T=%TIME%"
	::: 		set "T=!T::=!"
	::: 		set "T=!T:.=!"
	::: 		set "T=!T:,=!"
	::: 		set "D=%DATE%"
	::: 		set "D=!D::=!"
	::: 		set "D=!D:.=!"
	::: 		set "D=!D:\=!"
	::: 		set "D=!D:/=!"
	::: 		set "D=!D:,=!"
	::: 		set "R=%RANDOM%"
	::: 		set "tempPlanName=%tempPlanName%_!D!_!T!_!R!"
	::: 	)
	::: 	if not defined EXISTS goto :importplan
	::: 	:importplanreq
	::: 		set "USER_CHOICE="
 	::: 		set /p USER_CHOICE=Skip [S] or import with new name [N] '%tempPlanName%'? [S/N]:
	::: 		if /i "%USER_CHOICE%"=="S" (
	::: 			echo Skipping '%~1:%tempPlanName%'
	::: 			goto :processingPlanEnd
	::: 		)
	::: 		if /i "!USER_CHOICE!"=="N" goto :importplanreqend
	::: 		goto :importplanreq
	::: 	:importplanreqend
	::: DISABLED BLOCK END

	::: Import plan

		:importplan
		
			:chekdatasrc
				echo Checking source file...
				type "%planDTSXFile%" | find /i "Data Source=%SQL_SERVER%" >nul 2>&1 && (
					findstr /i "CreatorComputerName=\"%SQL_SERVER%\"" "%planDTSXFile%" >nul 2>&1 && (
						findstr /i "CreatorName=\"%USERNAME%\"" "%planDTSXFile%" >nul 2>&1 && (
							echo Correction values in the source file is not required.
							goto :chekdatasrcend
						)
					)
				)
				if not exist "%planDTSXFile%.bak" copy /y "%planDTSXFile%" "%planDTSXFile%.bak" >nul 2>&1 && echo Making a backup of source file.
				echo Correcting values in the source file...
				powershell -command "$p='%planDTSXFile%'; $c=[IO.File]::ReadAllLines($p,[Text.Encoding]::UTF8); for ($i=0;$i -lt $c.Length;$i++) { if ($c[$i] -match 'DTS:CreatorComputerName=\"') { $c[$i] = ($c[$i] -replace 'DTS:CreatorComputerName=\"[^\"]*\"','DTS:CreatorComputerName=\"%SQL_SERVER%\"') } }; [IO.File]::WriteAllLines($p,$c,[Text.Encoding]::UTF8)" >nul 2>&1
				powershell -command "$p='%planDTSXFile%'; $c=[IO.File]::ReadAllLines($p,[Text.Encoding]::UTF8); for ($i=0;$i -lt $c.Length;$i++) { if ($c[$i] -match 'DTS:CreatorName=\"') { $c[$i] = ($c[$i] -replace 'DTS:CreatorName=\"[^\"]*\"','DTS:CreatorName=\"%USERNAME%\"') } }; [IO.File]::WriteAllLines($p,$c,[Text.Encoding]::UTF8)" >nul 2>&1
				powershell -command "$p='%planDTSXFile%'; $c=[System.Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($p)); $c = $c -replace '(?i)Data Source=[^;]+','Data Source=%SQL_SERVER%'; [IO.File]::WriteAllBytes($p,[System.Text.Encoding]::UTF8.GetBytes($c))" >nul 2>&1
			:chekdatasrcend

			if /i "%UseMsDtsServer%" == "true" (
				echo Import Plan: dtutil: '%tempPlanName%' from file '%planDTSXFile%' to '%SQL_SERVER%'
				dtutil /FILE "%planDTSXFile%" /DestServer "%SQL_SERVER%" /COPY SQL;"\Maintenance Plans\%tempPlanName%" /QUIET >nul 2>&1
				echo Result: !errorlevel!
			) else (
				echo Import Plan: sqlcmd: '%tempPlanName%' from file '%planDTSXFile%' to '%SQL_SERVER%'
				set "REMOTE_FILE_NAME="
				set "REMOTE_FILE="
				for /f %%i in ("%planDTSXFile%") do set "REMOTE_FILE_NAME=%%~ni%%~xi"
				mkdir "\\%SQL_SERVER%\C$\Temp" >nul 2>&1
				copy /y "%planDTSXFile%" "\\%SQL_SERVER%\C$\Temp\!REMOTE_FILE_NAME!" >nul 2>&1
				if exist "\\%SQL_SERVER%\C$\Temp\!REMOTE_FILE_NAME!" (
					set "REMOTE_FILE=C:\Temp\!REMOTE_FILE_NAME!"
					sqlcmd -S %SQL_SERVER% -E -d msdb -Q "INSERT INTO msdb.dbo.sysssispackages (id,name,packagetype,packagedata,createdate,folderid,ownersid,packageformat,vermajor,verminor,verbuild,verid) SELECT NEWID(),N'%tempPlanName%',6,BulkColumn,GETDATE(),(SELECT folderid FROM msdb.dbo.sysssispackagefolders WHERE foldername=N'Maintenance Plans'),SUSER_SID(),0,1,0,0,NEWID() FROM OPENROWSET(BULK N'!REMOTE_FILE!', SINGLE_BLOB) AS x" >nul 2>&1
					echo Result: !errorlevel!
					ping -n 5 127.0.0.1 >nul 2>&1
					del /f /q "\\%SQL_SERVER%\C$\Temp\%REMOTE_FILE_NAME%" >nul 2>&1
				) else (
					echo ERROR: Can't copy file to '\\%SQL_SERVER%\C$\Temp\%REMOTE_FILE_NAME%'
				)
			)

			set "EXISTS="
			echo Cheking plan '%tempPlanName%' on '%SQL_SERVER%'
			for /f "usebackq delims=" %%P in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT name FROM dbo.sysssispackages WHERE name='%tempPlanName%'" 2^>nul`) do set "EXISTS=%%~P"
			if defined EXISTS call :trim_loop %EXISTS%
			set "planok=false"
			if defined EXISTS (
				if "%tempPlanName%" == "!EXISTS!" (
					echo SUCCESS: Import plan '%tempPlanName%'
					set "planok=true"
				)
			)
			if "!planok!" == "false" (
				echo ERROR: Import plan '%tempPlanName%'
			)

		:importplanend

	::: Import plan End

:processingPlanEnd
goto :eof

	:trim_loop
		if defined EXISTS ( if "!EXISTS:~-1!"==" " ( set "EXISTS=!EXISTS:~0,-1!" && goto :trim_loop ) )
	:trim_loop_end
	goto :eof

:exit
@pause
@endlocal && exit /b %errlvl%
