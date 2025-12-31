@echo off
setlocal enabledelayedexpansion

::: Version 2.26.12.2025 Test realease
::: (C) 2025 by Borizz.K (borizz.k@gmail.com) - https://github.com/BorizzK

:init

	echo Import Maintenance plans to MS SQL Servers.
	::: List of servers.
	::set "SQL_SERVERS=SQLSERVER1;SQLSERVER2;"
	set "SQL_SERVERS=SERV-1C8CA0;SERV-1C82CA1;SERV-1C82CA2;"
	set "SQL_SERVERS=SERV-1C8CA0"
	set "OnePlan=%~1"
	set "OnePlan=EveryDay_Backup_Template"

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
				set "PG_SQL_SERVERS=!PG_SQL_SERVERS!!SQL_SERVER!;"
			) else (
				set "PG_SQL_SERVERS=!SQL_SERVER!;"
			)
			ping -n 2 !SQL_SERVER!  >nul 2>&1
			sqlcmd -S !SQL_SERVER! -E -l 1 -Q "SELECT 1" >nul 2>&1 && (
				echo Processing server %stoken%: '!P_SQL_SERVER!'
				call :importplans "!SQL_SERVER!"
				echo.>nul
			) || (
				echo Processing server %stoken%: '!P_SQL_SERVER!': the server is unavailable. Skip.
			)
			ping -n 2 127.0.0.1 >nul 2>&1
		) else (
			goto :procserversend
		)
		goto :procservers
	:procserversend

	echo.Servers processed: '%PG_SQL_SERVERS%'
	echo.DTSX files processed: '%DTSXProcessed%'
	echo.
	echo.ATTENTION: YOU MUST CONNECT TO EACH SERVER VIA SMSS, OPEN EACH MAINTENANCE PLAN, AND SAVE IT FOR THE REPORTING TASK TO BE REGISTERED FOR EACH MAINTENANCE PLAN. 
	echo.

:end
goto :exit

:importplans

	echo Import Plans to '%SQL_SERVER%' from dir '%IMPORT_DIR%\%SQL_SERVER%'

	set "ServerSysOperatorsProcessed=false"

	set "dtsxmask=*"
	if defined OnePlan (
		set "dtsxmask=%OnePlan%"
		echo Only one plan defined: !dtsxmask!
	)

	dir /b "%IMPORT_DIR%\%SQL_SERVER%\%dtsxmask%.dtsx" >nul 2>&1 || (
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

	for %%F in ("%IMPORT_DIR%\%SQL_SERVER%\%dtsxmask%.dtsx") do (
		set "PLAN_NAME="
		set "PLAN_DTSID="
		call :readfile "%%~F"
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
	set "EXISTS="
	set "EXISTSSSISDTSID="
	set "EXISTSPLANDTSID="

	echo Processing Plan: Name: '%tempPlanName%', Dtsid: '%tempPlanDTSID%' from file: '%planDTSXFile%'
	set /a "DTSXProcessed+=1"

	for /f "usebackq tokens=*" %%P in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT name FROM dbo.sysssispackages WHERE name='%tempPlanName%'" 2^>nul`) do set "EXISTS=%%~P"
	if defined EXISTS call :trim_spaces "%EXISTS%" EXISTS
	if defined EXISTS if /i "%tempPlanName%" == "%EXISTS%" (
		echo WARNING: Plan already exists: Name: '%tempPlanName%': Existing plan name: '%EXISTS%'. Remove existng plan before import. Skip.
		set "EXISTS="
		goto :processingPlanEnd
	)
	for /f "usebackq tokens=*" %%S in (`sqlcmd -S %SQL_SERVER% -d msdb -E -Q "SET NOCOUNT ON; DECLARE @DTSID NVARCHAR(50)='%tempPlanDTSID%'; SELECT name,'DTSID' AS MatchType FROM dbo.sysssispackages WHERE packagetype=6 AND CAST(packagedata AS VARBINARY(MAX)) LIKE CAST('%%'+@DTSID+'%%' AS VARBINARY(MAX))" 2^>nul ^| find /i "DTSID"`) do set "EXISTS=%%~S"
	if defined EXISTS call :trim_spaces "%EXISTS%" EXISTS
	if defined EXISTS set "EXISTS=%EXISTS:DTSID=%"
	if defined EXISTS (
		echo WARNING: Plan already exists with other name: Dtsid: '%tempPlanDTSID%': Existing plan name: '%EXISTS%'. Remove existng plan before import. Skip.
		set "EXISTS="
		goto :processingPlanEnd
	)

	::: DISABLED DIALOG BLOCK
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
	::: DISABLED DIALOG BLOCK END

	::: IMPORT PLAN

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

			:writetoserverandimport
			:::::::::::::::::::::::::::::::::::::::
			:::	echo Import temporary skipped
			:::	goto :writetoserverandimportend
			:::	goto :importplanend
			:::::::::::::::::::::::::::::::::::::::

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
						sqlcmd -S %SQL_SERVER% -E -d msdb -Q "INSERT INTO msdb.dbo.sysssispackages (id,name,packagetype,packagedata,createdate,folderid,ownersid,packageformat,vermajor,verminor,verbuild,verid) SELECT NEWID(),N'%tempPlanName%',6,BulkColumn,GETDATE(),(SELECT folderid FROM msdb.dbo.sysssispackagefolders WHERE foldername=N'Maintenance Plans'),SUSER_SID(),0,1,0,0,NEWID() FROM OPENROWSET(BULK N'!REMOTE_FILE!', SINGLE_BLOB) AS x" -b >nul
						echo Result: !errorlevel!
						ping -n 5 127.0.0.1 >nul 2>&1
						del /f /q "\\%SQL_SERVER%\C$\Temp\%REMOTE_FILE_NAME%" >nul 2>&1
					) else (
						echo ERROR: Can't copy file to '\\%SQL_SERVER%\C$\Temp\%REMOTE_FILE_NAME%'
					)
				)
			:writetoserverandimportend

			:checkimportedplan
				set "EXISTS="
				set "EXISTSSSISDTSID="
				set "EXISTSPLANDTSID="
				echo Cheking plan '%tempPlanName%' on '%SQL_SERVER%'
				for /f "usebackq delims=" %%P in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT name FROM dbo.sysssispackages WHERE name='%tempPlanName%'" 2^>nul`) do set "EXISTS=%%~P"
				if defined EXISTS call :trim_spaces "%EXISTS%" EXISTS
				for /f "usebackq delims=" %%P in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT id FROM dbo.sysssispackages WHERE name='%tempPlanName%'" 2^>nul`) do set "EXISTSSSISDTSID=%%~P"
				if defined EXISTSSSISDTSID call :trim_spaces "%EXISTSSSISDTSID%" EXISTSSSISDTSID
				for /f "usebackq delims=" %%P in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT id FROM dbo.sysmaintplan_plans WHERE name='%tempPlanName%'" 2^>nul`) do set "EXISTSPLANDTSID=%%~P"
				if defined EXISTSPLANDTSID call :trim_spaces "%EXISTSPLANDTSID%" EXISTSPLANDTSID
				set "planok=false"
				if defined EXISTS (
					if /i "%tempPlanName%" == "%EXISTS%" (
						if /i "%EXISTSSSISDTSID%" == "%EXISTSPLANDTSID%" (
							echo SUCCESS: Import plan '%tempPlanName%': DTSID:[Source]: '%tempPlanDTSID%': DTSID:[dbo.sysssispackages]: '%EXISTSSSISDTSID%':  DTSID:[dbo.sysmaintplan_plans]: '%EXISTSPLANDTSID%'
							set "planok=true"
						) else (
							echo.
							echo.WARNING: Import plan '%tempPlanName%': DTSID:[Source]: '%tempPlanDTSID%': DTSID:[dbo.sysssispackages]: '%EXISTSSSISDTSID%':  DTSID:[dbo.sysmaintplan_plans]: '%EXISTSPLANDTSID%'
							echo.Plan '%tempPlanName%' not correctly registered. Check SQL Server.
							echo.
						)
					)
				)
				if "!planok!" == "false" (
					echo ERROR: Import plan '%tempPlanName%': DTSID[Source]: '%tempPlanDTSID%'
				)
			:checkimportedplanend

		:importplanend

	::: IMPORT PLAN END
	
	::: IMPORT JOBS
		
		::: Under Construction
		call :ImportJobs

	::: IMPORT JOBS END

:processingPlanEnd
goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:ImportJobs

	set "subplans="
	set "subplansdescrs="
	set "subplanssids="

	call :GetSubPlans "%tempPlanName%" "%planDTSXFile%"

	call :ImportJobFromTSQL 

:ImportJobsEnd
goto :eof

:ImportJobFromTSQL

	call :ImportSysOps

	set "curSubplan="
	set "curSubplanDescr="
	set "curSubplanSid="

	set /a token=0
	:subplanscycle
		set /a "token+=1"
		set "curSubplan="
		set "curSubplanSid="
		for /f "tokens=%token% delims=;" %%i in ("%subplans%") do set "curSubplan=%%~i"
		for /f "tokens=%token% delims=;" %%i in ("%subplansdescrs%") do set "curSubplanDescr=%%~i"
		for /f "tokens=%token% delims=;" %%i in ("%subplanssids%") do set "curSubplanSid=%%~i"
		if defined curSubplan (
			echo Processing subplan: !token!: '!curSubplan!':'!curSubplanDescr!':'!curSubplanSid!'
			call :ProcessingImportJobForSubPlan
		) else (
			goto :subplanscycleend
		)
		goto :subplanscycle
	:subplanscycleend

:ImportJobFromTSQLEnd
goto :eof

:ImportSysOps
	if "%ServerSysOperatorsProcessed%" == "true" goto :ImportSysOpsEnd
	if exist "%IMPORT_DIR%\%SQL_SERVER%\SysOperators.sql" (
		echo Processing sysoperators TSQL file: '%IMPORT_DIR%\%SQL_SERVER%\SysOperators.sql'
		sqlcmd -S %SQL_SERVER% -E -d msdb -i "%IMPORT_DIR%\%SQL_SERVER%\SysOperators.sql" -b >nul
		set "ServerSysOperatorsProcessed=true"
	)
	
:ImportSysOpsEnd
goto :eof

:ProcessingImportJobForSubPlan

	set "job_id="
	set "schedule_id="

	echo Processing jobs plan: '%tempPlanName%':'%tempPlanDTSID%': Subplan: '%curSubplan%':'%curSubplanDescr%':'%curSubplanSid%'
	set "exf=false"
	if exist "%IMPORT_DIR%\%SQL_SERVER%\%tempPlanName%.%curSubplan%.sql" (
		 set "exf=true"
	) else (
		echo Job TSQL file: '%IMPORT_DIR%\%SQL_SERVER%\%tempPlanName%.%curSubplan%.sql': Not Exist: Skip.
		goto :ProcessingImportJobForSubPlanEnd
	)
	echo Job TSQL file: '%IMPORT_DIR%\%SQL_SERVER%\%tempPlanName%.%curSubplan%.sql': Exist: '%exf%'
	sqlcmd -S %SQL_SERVER% -E -d msdb -v SRVR="%SQL_SERVER%" -i "%IMPORT_DIR%\%SQL_SERVER%\%tempPlanName%.%curSubplan%.sql" -b >nul
	set "sqlerrlvl=%errorlevel%"
	echo Job TSQL file: Import result: %sqlerrlvl%
	if not "%sqlerrlvl%" == "0" (
		echo ERROR: Job TSQL file: Import. Skip processing subplan: '%curSubplan%':'%curSubplanSid%' link.
		goto :ProcessingImportJobForSubPlanEnd
	)

	::: First Remove {} from %tempPlanDTSID% and %curSubplanSid% HERE
	set "tempPlanDTSID=%tempPlanDTSID:{=%" 
	set "tempPlanDTSID=%tempPlanDTSID:}=%"
	set "curSubplanSid=%curSubplanSid:{=%"
	set "curSubplanSid=%curSubplanSid:}=%"

	:setjobid
		for /f "usebackq tokens=1" %%# in (`sqlcmd -S %SQL_SERVER% -E -h -1 -s "¶" -w 65535 -y 0 -Y 0 -Q "SET NOCOUNT ON; SELECT job_id FROM msdb.dbo.sysjobs WHERE name=N'%tempPlanName%.%curSubplan%'" 2^>nul`) do (
			set "job_id=%%~#"
			if defined job_id call :trim_spaces "!job_id!" job_id
		)
	:setjobidend
	if not defined job_id (
		echo ERROR: Job '%tempPlanName%.%curSubplan%' not registered on SQL Server: %SQL_SERVER%. Skip processing subplan: '%curSubplan%':'%curSubplanSid%' link.
		goto :ProcessingImportJobForSubPlanEnd
	)
	:setscheduleids
		for /f "usebackq tokens=1" %%# in (`sqlcmd -S %SQL_SERVER% -E -h -1 -s "¶" -w 65535 -y 0 -Y 0 -Q "SET NOCOUNT ON; SELECT schedule_id FROM msdb.dbo.sysjobschedules WHERE job_id='%job_id%' ORDER BY schedule_id" 2^>nul`) do (	
			set "schedule_id=%%~#"
			if defined schedule_id call :trim_spaces "!schedule_id!" schedule_id
			if defined schedule_id (
				goto :setscheduleidsend
			)
		)
	:setscheduleidsend
	if not defined schedule_id (
		echo ERROR: Job '%tempPlanName%.%curSubplan%' no Schedules for job registered on SQL Server: %SQL_SERVER%. Skip processing subplan: '%curSubplan%':'%curSubplanSid%' link.
		goto :ProcessingImportJobForSubPlanEnd
	)

	if defined job_id if defined schedule_id call :LinkPlanSubplanShedule

:ProcessingImportJobForSubPlanEnd
goto :eof

:LinkPlanSubplanShedule
	::: subplan_id      subplan_name subplan_description plan_id	     job_id   schedule_id
	::: %curSubplanSid% %curSubplan% %curSubplanDescr%   %tempPlanDTSID% %job_id% %schedule_id%
	echo Linking: [msdb.dbo.sysmaintplan_subplans]: '%curSubplanSid%':'%curSubplan%':'%curSubplanDescr%':'%tempPlanDTSID%':'%job_id%':'%schedule_id%'
	sqlcmd -S %SQL_SERVER% -E -d msdb -b -Q "SET NOCOUNT ON; IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysmaintplan_subplans WHERE subplan_id = '%curSubplanSid%' AND schedule_id = %schedule_id%) INSERT INTO msdb.dbo.sysmaintplan_subplans (subplan_id, subplan_name, subplan_description, plan_id, job_id, schedule_id) VALUES (N'%curSubplanSid%', N'%curSubplan%', N'%curSubplanDescr%', N'%tempPlanDTSID%', N'%job_id%', %schedule_id%);" -b >nul
	if %errorlevel% == 0 (
		echo Linking: Success.
	) else (
		echo Linking: Error.
	)
:LinkPlanSubplanSheduleEnd
goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

	:GetSubPlans
		set "planname=%~1"
		set "dtsxname=%~2"
		set "subplans="
		set "subplansdescrs="
		set "subplanssids="
		set "sLine="
		echo GetSubPlans: Plan: '%planname%', DTSX: '%dtsxname%'
		for /f "tokens=2 delims=<>" %%i in ('type "%dtsxname%" 2^>nul ^| find /i "DTS:Executable DTS:refId=" ^| find /i "Package\" ^| find /i "DTS:CreationName=" ^| find /i "DTS:Description=" ^| find /i "DTS:Disabled=" ^| find /i "DTS:DTSID=" ^| find /i "DTS:ExecutableType=" ^| find /i "DTS:FailParentOnFailure=" ^| find /i "DTS:LocaleID=" ^| find /i "DTS:ObjectName="') do (
			set "sLine=%%~i"
			if defined sLine call :GetSubplan !sLine!
		)

		echo Plan: '%planname%': Subplans: '%subplans%': Sids: '%subplanssids%', Descrs: '%subplansdescrs%'

	:GetSubPlansEnd
	goto :eof
	
	:GetSubplan
		set "tmpline=%*"
		set "tmpline=%tmpline:" ="¶%¶"
		set "subplanpkg="
		set "subplandescr="
		set "subplansid="
		set "subplan="
		set /a "token=0"
		
		::: Under Construction - parse string by symbols and check next 2 symbols
		::set "mainstring="
		:::parse_flow
		::	if "!tmpline:~%token%,1!" == "" goto :parse_flow_end
		::	set /a "sym1=%token%+1"
		::	set /a "sym2=%token%+2"
		::	rem echo Sym: %token%: '!tmpline:~%token%,1!!tmpline:~%sym1%,1!'
		::	set "tmpsyms=!tmpline:~%token%,2!"
		::	if defined tmpsyms set "tmpsyms=%tmpsyms:"=§%
		::	if "%tmpsyms%"=="§% " (
		::		echo FOUND: quote-space at position %token%: '!tmpline:~%token%,2!'
		::	)
		::	set "mainstring=%mainstring%!tmpline:~%token%,1!"
		::	set /a "token+=1"
		::goto :parse_flow
		:::parse_flow_end
		::echo %tmpline% >tmpline.txt
		::echo %mainstring% >mainstring.txt
		::goto :eof
		
		:parse_subplan_line
			set "a="
			set /a "token+=1"
			for /f "tokens=%token% delims=¶" %%i in ("%tmpline%") do set "a=%%~i"
			if not defined a goto :parse_subplan_line_end
			echo %a% | find /i "DTS:refId=" >nul 2>&1 && (
				if not defined subplanpkg for /f "tokens=2 delims==" %%i in ("%a%") do set "subplanpkg=%%~i"
			)
			echo %a% | find /i "DTS:Description=" >nul 2>&1 && (
				if not defined subplandescr for /f "tokens=2 delims==" %%i in ("%a%") do set "subplandescr=%%~i"
			)
			echo %a% | find /i "DTS:DTSID=" >nul 2>&1 && (
				if not defined subplansid for /f "tokens=2 delims==" %%i in ("%a%") do set "subplansid=%%~i"
			)
			echo %a% | find /i "DTS:ObjectName=" >nul 2>&1 && (
				if not defined subplan for /f "tokens=2 delims==" %%i in ("%a%") do set "subplan=%%~i"
			)
			if defined subplanpkg if defined subplandescr if defined subplansid if defined subplan (
				goto :parse_subplan_line_end
			)
			goto :parse_subplan_line
		:parse_subplan_line_end
		
		if defined subplanpkg if defined subplandescr if defined subplansid if defined subplan (
			if /i "%subplanpkg:package\=%" == "%subplan%" (
				echo GetSubplan: '%subplanpkg%':'%subplandescr%':'%subplansid%':'%subplan%'

				if defined subplans (
					set "subplans=!subplans!%subplan%;"
					set "subplansdescrs=!subplansdescrs!%subplandescr%;"
					set "subplanssids=!subplanssids!%subplansid%;"
				) else (
					set "subplans=%subplan%;"
					set "subplansdescrs=%subplandescr%;"
					set "subplanssids=%subplansid%;"
				)
			) else (
				echo WARNING: The subplan '%subplan%' may contain errors. Check plan '%planname%' and subplan configuration in SQL server.
			)
		)
	:GetSubplanEnd
	goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

	:trim_spaces
		setlocal enabledelayedexpansion
		set "str=%~1"
		if not defined str goto :eof
		:trim_cycle_lastspaces
		if defined str (
			if "!str:~-1!"==" " (
				set "str=!str:~0,-1!"
				goto :trim_cycle_lastspaces
			)
		)
		:trim_cycle_leadspaces
		if defined str (
			if "!str:~0,1!"==" " (
				set "str=!str:~1!"
				goto :trim_cycle_leadspaces
			)
		)
	:trim_spaces_end
	if defined str if /i "%str:"=%" == "NULL" set "str="
	endlocal & set "%2=%str%"
	goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:exit
@pause
@endlocal && exit /b %errlvl%
