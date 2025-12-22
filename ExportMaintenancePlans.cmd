@echo off
setlocal enabledelayedexpansion

::: Version 2.22.12.2025 Test realease
::: (C) 2025 by Borizz.K (borizz.k@gmail.com) - https://github.com/BorizzK

:init

	echo Export Maintenance plans from MS SQL Servers.
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
	set "EXPORT_DIR=D:\SERVER\SQL"
	if not exist "%EXPORT_DIR%" set "EXPORT_DIR=D:\SERVER\SQL_SRV"
	if not exist "%EXPORT_DIR%" (
		set "EXPORT_DIR=%RunPath%"
	)
	if not exist "%EXPORT_DIR%" mkdir "%EXPORT_DIR%"
	if not exist "%EXPORT_DIR%" (
		echo ERROR: Directory '%EXPORT_DIR%' is not accessible. Terminating.
		exit /b 3
	)
	set /a "DTSXProcessed=0"
	set "SQL_SERVER="
	set "PG_SQL_SERVERS="
	set "PLAN_NAME="
	set "P_SQL_SERVER="
	set /a "stoken=0"

:begin

	echo Working dir: '%RunPath%'
	echo Root export dir: '%EXPORT_DIR%'
	echo All .dtsx files will be saved to: '%EXPORT_DIR%'

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

			rem ping -n 2 127.0.0.1 | find /i "TTL=" >nul 2>&1 && ()
			sqlcmd -S !SQL_SERVER! -E -l 3 -Q "SELECT 1" >nul 2>&1 && (
				echo Processing server %stoken%: '!SQL_SERVER!'
				call :exportplans "!SQL_SERVER!"
			) || (
				echo Processing server %stoken%: '!SQL_SERVER!': the server is unavailable. Skip.
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

:exportplans

	if not exist "%EXPORT_DIR%\%SQL_SERVER%" mkdir "%EXPORT_DIR%\%SQL_SERVER%" >nul 2>&1
	if not exist "%EXPORT_DIR%\%SQL_SERVER%" (
		echo ERROR: '%EXPORT_DIR%\%SQL_SERVER%' not accessible.
		goto :exportplansend
	)
	echo Checking MsDtsServer (SSIS) on %SQL_SERVER%...
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
	if /i "%UseMsDtsServer%" == "true" (
		echo Using dtutil [SSIS]...
	) else (
		echo Using sqlcmd/bcp [SQL]...
	)
	for /f "tokens=*" %%i in ('sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -Q "SET NOCOUNT ON; SELECT name FROM dbo.sysssispackages WHERE packagetype=6"') do (
		set "PLAN_NAME="
		set "PLAN_NAME=%%~i"
		if defined PLAN_NAME (
			call :trim_loop !PLAN_NAME!
			set "experrlvl=9"
			echo Processing Plan '!PLAN_NAME!' from server '%SQL_SERVER%'
			if /i "%UseMsDtsServer%" == "true" (
				echo Exporting: dtutil: %SQL_SERVER%: '!PLAN_NAME!' to '%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx'
				dtutil /SQL "\Maintenance Plans\!PLAN_NAME!" /SourceServer "%SQL_SERVER%" /ENCRYPT FILE;"%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx";1 /QUIET >nul 2>&1
				set "experrlvl=!errorlevel!"
				echo Result code: !experrlvl!
			) else (
				echo Exporting: bcp: %SQL_SERVER%: '!PLAN_NAME!' to '%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx'
				bcp "SELECT packagedata FROM msdb.dbo.sysssispackages WHERE name='!PLAN_NAME!'" queryout "%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!_raw.dtsx" -T -S %SQL_SERVER% -n >nul 2>&1
				powershell -Command ^
					"$bytes=[System.IO.File]::ReadAllBytes('%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!_raw.dtsx');" ^
					"$xmlStart=[System.Text.Encoding]::UTF8.GetString($bytes).IndexOf('<?xml');" ^
					"[System.IO.File]::WriteAllBytes('%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx',$bytes[$xmlStart..($bytes.Length-1)])"
				set "experrlvl=!errorlevel!"
				echo Result code: !experrlvl!
				del /f /q "%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!_raw.dtsx" >nul 2>&1
			)
			if "!experrlvl!" == "0" set /a "DTSXProcessed+=1"
		) else (
			echo ERROR: 'PLAN_NAME'
		)
	)

:exportplansend
exit /b %experrlvl%
goto :eof

	:trim_loop
		if defined PLAN_NAME if "!PLAN_NAME:~-1!"==" " set "PLAN_NAME=!PLAN_NAME:~0,-1!" && goto :trim_loop
	:trim_loop_end
	goto :eof

:exit
@pause
@endlocal && exit /b %errlvl%
