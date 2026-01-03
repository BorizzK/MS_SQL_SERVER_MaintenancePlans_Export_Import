@echo off
setlocal enabledelayedexpansion

::: Version 3.3.1.2026 Test release
::: (C) 2025 by Borizz.K (borizz.k@gmail.com) - https://github.com/BorizzK

:init

	echo %DATE%,%TIME:~0,-3%: Export Maintenance plans from MS SQL Servers.
	::: List of servers.
	::set "SQL_SERVERS=1C-SRV01;"
	set "SQL_SERVERS=SERV-1C8CA0;"
	set "OnePlan=%~1"
	if "%OnePlan%" == "*" set "OnePlan="
	rem set "OnePlan=EveryDay_Backup_Template"

	sqlcmd -? >nul 2>&1
	if %errorlevel% == 9009 (
		echo %DATE%,%TIME:~0,-3%: ERROR: Sqlcmd is missing. Terminating.
		exit /b 1
	)
	bcp -? -? >nul 2>&1
	if %errorlevel% == 9009 (
		echo %DATE%,%TIME:~0,-3%: ERROR: Bcp is missing. Terminating.
		exit /b 2
	)
	net session >nul 2>&1 || (
		echo %DATE%,%TIME:~0,-3%: ERROR: Administrator or system rights required. Terminating.
		exit /b 3
	)
	
	if not defined SQL_SERVERS (
		echo %DATE%,%TIME:~0,-3%: ERROR: SQL SERVERS not defined. Terminating.
		exit /b 4
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
	set "PLAN_DTSID="
	set "P_SQL_SERVER="
	set /a "stoken=0"
	set "EXPORTED_JOBS"

	if not defined TEMP set "TEMP=%SystemRoot%\Temp"
	if not defined TMP  set "TMP=%SystemRoot%\Temp"
	if not exist "%TEMP%\" (
		echo "%TEMP%" | find /i ":\" >nul 2>&1 && md "%TEMP%\" >nul 2>&1
	)
	if not exist "%TMP%\" (
		echo "%TMP%" | find /i ":\" >nul 2>&1 && md "%TMP%\" >nul 2>&1
	)
	set "PSRND=%RANDOM%"
	set "PS_TEMP=%TEMP%\%PSRND%"
	md "%PS_TEMP%" >nul 2>&1

:begin

	echo %DATE%,%TIME:~0,-3%: Input params: '%~1'
	echo %DATE%,%TIME:~0,-3%: Working dir: '%RunPath%'
	echo %DATE%,%TIME:~0,-3%: Root export dir: '%EXPORT_DIR%'
	echo %DATE%,%TIME:~0,-3%: PS temp dir: '%PS_TEMP%'
	echo %DATE%,%TIME:~0,-3%: All .dtsx files will be saved to: '%EXPORT_DIR%'

	:procservers
		set /a "stoken+=1"
		set "P_SQL_SERVER="
		set "SQL_SERVER="
		for /f "tokens=%stoken% delims=;" %%i in ("%SQL_SERVERS%") do set "P_SQL_SERVER=%%~i"
		if defined P_SQL_SERVER (
			set "SQL_SERVER=!P_SQL_SERVER!"
			echo %DATE%,%TIME:~0,-3%: Try to processing server %stoken%: '!SQL_SERVER!'
			if defined PG_SQL_SERVERS (
				echo "!PG_SQL_SERVERS!" | find /i "!P_SQL_SERVER!;" >nul 2>&1 && (
					echo %DATE%,%TIME:~0,-3%: Processing server %stoken%: '!P_SQL_SERVER!' already processed.
					goto :procservers
				)
			)
			if defined PG_SQL_SERVERS (
				set "PG_SQL_SERVERS=!PG_SQL_SERVERS!!SQL_SERVER!;"
			) else (
				set "PG_SQL_SERVERS=!SQL_SERVER!;"
			)
			echo %DATE%,%TIME:~0,-3%: Check connection to server %stoken%: '!SQL_SERVER!'
			ping -n 2 !SQL_SERVER! >nul 2>&1
			sqlcmd -S !SQL_SERVER! -E -l 2 -t 2 -h -1 -Q "SELECT 1" >nul 2>&1 && (
				echo %DATE%,%TIME:~0,-3%: Processing server %stoken%: '!SQL_SERVER!'
				call :ExportSysOperators "!SQL_SERVER!"
				call :exportplans "!SQL_SERVER!"
				call :exportnonplanjobs "!SQL_SERVER!"
				echo.>nul
			) || (
				echo %DATE%,%TIME:~0,-3%: '!SQL_SERVER!': the server is unavailable. Skip.
			)
		) else (
			goto :procserversend
		)
		goto :procservers
	:procserversend

	echo %DATE%,%TIME:~0,-3%: Servers processed: '%PG_SQL_SERVERS%'
	echo %DATE%,%TIME:~0,-3%: DTSX files processed: '%DTSXProcessed%'

:end
goto :exit

:exportplans

	echo %DATE%,%TIME:~0,-3%: Export plans from: '%SQL_SERVER%', to: '%EXPORT_DIR%\%SQL_SERVER%'

	if not exist "%EXPORT_DIR%\%SQL_SERVER%" mkdir "%EXPORT_DIR%\%SQL_SERVER%" >nul 2>&1
	if not exist "%EXPORT_DIR%\%SQL_SERVER%" (
		echo %DATE%,%TIME:~0,-3%: ERROR: '%EXPORT_DIR%\%SQL_SERVER%' not accessible.
		goto :exportplansend
	)

	set "ServerSysOperatorsProcessed=false"

	echo %DATE%,%TIME:~0,-3%: Checking MsDtsServer [SSIS] on %SQL_SERVER%...
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
	::: test
	::: set "UseMsDtsServer=false"

	if /i "%UseMsDtsServer%" == "true" (
		echo %DATE%,%TIME:~0,-3%: Using dtutil [SSIS] [dtutil:%UseMsDtsServer%]...
	) else (
		echo %DATE%,%TIME:~0,-3%: Using sqlcmd/bcp [SQL] [dtutil:%UseMsDtsServer%]...
	)

	for /f "usebackq tokens=*" %%i in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT name FROM dbo.sysssispackages WHERE packagetype=6"`) do (
		set "PLAN_NAME="
		set "PLAN_NAME=%%~i"
		if defined PLAN_NAME (
			call :trim_spaces "!PLAN_NAME!" PLAN_NAME
			set "experrlvl=9"
			if defined OnePlan (
				if /i "%OnePlan%" == "!PLAN_NAME!" (
					echo %DATE%,%TIME:~0,-3%: Only One Plan defined for export: '%OnePlan%'
					call :exportplan
				)
			) else (
				call :exportplan
			)
		) else (
			echo %DATE%,%TIME:~0,-3%: ERROR: 'PLAN_NAME'
		)
	)

:exportplansend
exit /b %experrlvl%
goto :eof

:exportnonplanjobs

	::: Under construction.
	call :ExportNonMaintenancePlanJobs

:exportnonplanjobsend
exit /b %experrlvl%
goto :eof

:exportplan
	echo %DATE%,%TIME:~0,-3%: Processing Plan: '!PLAN_NAME!' from server '%SQL_SERVER%' Begin.
	if /i "%UseMsDtsServer%" == "true" (
		echo %DATE%,%TIME:~0,-3%: Exporting: dtutil: %SQL_SERVER%: '!PLAN_NAME!' to '%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx'
		dtutil /SQL "\Maintenance Plans\!PLAN_NAME!" /SourceServer "%SQL_SERVER%" /ENCRYPT FILE;"%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx";1 /QUIET >"%EXPORT_DIR%\%SQL_SERVER%\dtutil_export_!PLAN_NAME!.log" 2>&1
		set "experrlvl=!errorlevel!"
		echo %DATE%,%TIME:~0,-3%: Export Plan Result code: Dtutil: '!experrlvl!'
	) else (
		echo %DATE%,%TIME:~0,-3%: Exporting: bcp: %SQL_SERVER%: '!PLAN_NAME!' to '%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx'
		bcp "SELECT packagedata FROM msdb.dbo.sysssispackages WHERE name='!PLAN_NAME!'" queryout "%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!_raw.dtsx" -T -S %SQL_SERVER% -n >"%EXPORT_DIR%\%SQL_SERVER%\bcp_export_!PLAN_NAME!.log" 2>&1
		set "experrlvl=!errorlevel!"
		echo %DATE%,%TIME:~0,-3%: Converting: powershell: System.Text.Encoding: '%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!_raw.dtsx' -^> '%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!.dtsx'

			if exist "%RunPath%\0" (
				echo %DATE%,%TIME:~0,-3%: WARNING: 1:'%RunPath%\0' Detected.
				rem rmdir /s /q "%RunPath%\0" >nul 2>&1
			)
			
			call :pwencodingrawdtsx
			set "pwexperrlvl=%errorlevel%"
			rem del /f /q "%EXPORT_DIR%\%SQL_SERVER%\!PLAN_NAME!_raw.dtsx" >nul 2>&1

			if exist "%RunPath%\0" (
				echo %DATE%,%TIME:~0,-3%: WARNING: 2:'%RunPath%\0' Detected.
				rem rmdir /s /q "%RunPath%\0" >nul 2>&1
			)


		echo %DATE%,%TIME:~0,-3%: Export Plan Result code: BCP: '!experrlvl!', PS: '!pwexperrlvl!'
	)
	if "%experrlvl%" == "0" set /a "DTSXProcessed+=1"

	call :ExportPlanJobs
	echo %DATE%,%TIME:~0,-3%: Processing Plan: '!PLAN_NAME!' from server '%SQL_SERVER%' End.

:exportplanend
goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:pwencodingrawdtsx
	
	set "pwerrlvl=0"
	
	set "$CCD=%CD%" >nul 2>&1
	cd "%PS_TEMP%" >nul 2>&1
	cd /d "%PS_TEMP%" >nul 2>&1

	echo %DATE%,%TIME:~0,-3%: Execution PS command. Working dir: '%CD%'

	powershell -NoProfile -ExecutionPolicy Bypass -Command ^
		"$ErrorActionPreference='Stop';" ^
		"$timestamp = Get-Date -Format 'dd.MM.yyyy,HH:mm:ss';" ^
		"Write-Host ($timestamp + ': [INFO] Preparing to convert a raw xml file: raw.dtsx');" ^
		"if(-not $env:EXPORT_DIR -or -not $env:SQL_SERVER -or -not $env:PLAN_NAME) {" ^
		"    throw ($timestamp + ': [ERROR] Missing env vars: EXPORT_DIR, SQL_SERVER, PLAN_NAME');" ^
		"}" ^
		"$rawFile = Join-Path -Path $env:EXPORT_DIR -ChildPath $env:SQL_SERVER | Join-Path -ChildPath ($env:PLAN_NAME + '_raw.dtsx');" ^
		"$outFile = Join-Path -Path $env:EXPORT_DIR -ChildPath $env:SQL_SERVER | Join-Path -ChildPath ($env:PLAN_NAME + '.dtsx');" ^
		"if($rawFile -match '(^|\\|/)0(\\|/)') {" ^
		"    throw ($timestamp + ': [ERROR] Suspicious rawFile path (contains ''0''): ' + $rawFile);" ^
		"}" ^
		"if($outFile -match '(^|\\|/)0(\\|/)') {" ^
		"    throw ($timestamp + ': [ERROR] Suspicious outFile path (contains ''0''): ' + $outFile);" ^
		"}" ^
		"if(-not (Test-Path $rawFile -PathType Leaf)) {" ^
		"    throw ($timestamp + ': [ERROR] Input file not found: ' + $rawFile);" ^
		"}" ^
		"if((Get-Item $rawFile).Length -eq 0) {" ^
		"    throw ($timestamp + ': [ERROR] Input file is empty: ' + $rawFile);" ^
		"}" ^
		"$outDir = Split-Path $outFile -Parent;" ^
		"if(-not (Test-Path $outDir -PathType Container)) {" ^
		"    throw ($timestamp + ': [ERROR] Output directory does not exist: ' + $outDir);" ^
		"}" ^
		"$timestamp = Get-Date -Format 'dd.MM.yyyy,HH:mm:ss';" ^
		"Write-Host ($timestamp + ': [INFO] Processing: ' + $rawFile);" ^
		"try {" ^
		"    $bytes = [System.IO.File]::ReadAllBytes($rawFile);" ^
		"    if($bytes.Length -ge 2 -and $bytes[0]-eq 0xFF -and $bytes[1]-eq 0xFE) {" ^
		"        $text = [System.Text.Encoding]::Unicode.GetString($bytes);" ^
		"    } elseif($bytes.Length -ge 2 -and $bytes[0]-eq 0xFE -and $bytes[1]-eq 0xFF) {" ^
		"        $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes);" ^
		"    } else {" ^
		"        $text = [System.Text.Encoding]::UTF8.GetString($bytes);" ^
		"    }" ^
		"    $match = [Regex]::Match($text, '<\?xml');" ^
		"    if(-not $match.Success) {" ^
		"        throw ($timestamp + ': [ERROR] XML declaration not found in: ' + $rawFile);" ^
		"    }" ^
		"    $outText = $text.Substring($match.Index);" ^
		"    [System.IO.File]::WriteAllText($outFile, $outText, [System.Text.Encoding]::UTF8);" ^
		"    $timestamp = Get-Date -Format 'dd.MM.yyyy,HH:mm:ss';" ^
		"    Write-Host ($timestamp + ': [SUCCESS] Processed: ' + $outFile);" ^
		"} catch {" ^
		"    $timestamp = Get-Date -Format 'dd.MM.yyyy,HH:mm:ss';" ^
		"    throw ($timestamp + ': [ERROR] Operation failed: ' + $_.Exception.Message);" ^
		"}"

	set "pwerrlvl=%errorlevel%"
	
	cd "%$CCD%" >nul 2>&1
	cd /d "%$CCD%" >nul 2>&1

:pwencodingrawdtsxend
exit /b %pwerrlvl%

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

	:ExportPlanJobs
		set "subplans="
		set "subplansdescrs="
		set "subplanssids="
		call :CreatePlanJobSchedulesExportTSQL
	:ExportPlanJobsEnd
	goto :eof

	:CreatePlanJobSchedulesExportTSQL
		set "subplans="
		set "subplansdescrs="
		set "subplanssids="
		call :GetSubPlans "%PLAN_NAME%" "%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.dtsx"
		echo %DATE%,%TIME:~0,-3%: Plan: '%planname%': Subplans: '%subplans%': Sids: '%subplanssids%', Descrs: '%subplansdescrs%'
		call :GeneratePlanJobTSQLFile
	:CreatePlanJobSchedulesExportTSQLEnd
	goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

	:GetSubPlans
		set "planname=%~1"
		set "dtsxname=%~2"
		set "subplans="
		set "subplansdescrs="
		set "subplanssids="
		if not exist "%dtsxname%" (
			echo %DATE%,%TIME:~0,-3%: Get SubPlans: Plan: '%planname%', DTSX: Not found '%dtsxname%'. Skip.
			goto :GetSubPlansEnd
		)
		echo %DATE%,%TIME:~0,-3%: Get SubPlans: Plan: '%planname%', DTSX: '%dtsxname%'

		set "xmltype="
		set /a "xmltypenum=0"
		findstr /c:"\<\?xml version=" "%dtsxname%" >nul 2>&1 && (
			findstr /r /c:"<DTS:Executable .*DTS:refId=.*DTS:CreationName=.*DTS:DTSID=.*DTS:ExecutableType=.*DTS:ObjectName=.*DTS:PackageType=.*DTS:ProtectionLevel=.*>" "%dtsxname%" >nul 2>&1 && ( 
				set "xmltype=bcp"
				set /a "xmltypenum+=1"
			)
			findstr /r /c:"<DTS:Executable .*DTS:refId=.*DTS:CreationName=.*DTS:Description=.*DTS:Disabled=.*DTS:DTSID=.*DTS:ExecutableType=.*DTS:FailParentOnFailure=.*DTS:LocaleID=.*DTS:ObjectName=.*>" "%dtsxname%" >nul 2>&1 && (
				set "xmltype=bcp"
				set /a "xmltypenum+=1"
			) || (
				set "xmltype=dtutil"
			)
		)
		
		if "%xmltype%" == "bcp" (
			echo %DATE%,%TIME:~0,-3%: Get SubPlans: Plan: '%planname%', DTSX: '%dtsxname%': Type: BCP: Type#: '%xmltypenum%'
			goto :GetSubPlansBCPXML
		)
		if "%xmltype%" == "dtutil" (
			echo %DATE%,%TIME:~0,-3%: Get SubPlans: Plan: '%planname%', DTSX: '%dtsxname%': Type: DTUTIL: Type#: '%xmltypenum%'
			goto :GetSubPlansDTUTILXML
		)
		
		echo %DATE%,%TIME:~0,-3%: No XML type defined. Skip Get Subplans configuration.
		goto :GetSubPlansEnd

		:GetSubPlansDTUTILXML
			set "tmpline="
			set "subplanpkg="
			set "subplandescr="
			set "subplansid="
			set "subplan="
			set "inBlock="
			set "sLine="
			set /a "sbnum=0"

			echo %DATE%,%TIME:~0,-3%: Get SubPlans: [DTUTIL.XML]: Plan: '%planname%', DTSX: '%dtsxname%'
			set /a "sbnum=0"
			for /f "usebackq tokens=*" %%# in ("%dtsxname%") do (
				set "tmpline=%%#"
				if defined tmpline set "defline=!tmpline!"
				if defined tmpline set "tmpline=!tmpline:<=!"
				if defined tmpline set "tmpline=!tmpline:>=!"
				if defined tmpline set "tmpline=!tmpline:&=!"
				if defined tmpline set "tmpline=!tmpline:(=!"
				if defined tmpline set "tmpline=!tmpline:)=!"
				if defined tmpline call :GetSubplanDTUTILXML
			)

		:GetSubPlansDTUTILXMLEnd
		goto :GetSubPlansEnd
		
		:GetSubPlansBCPXML
			
			set "tmpline="
			set "subplanpkg="
			set "subplandescr="
			set "subplansid="
			set "subplan="
			set "inBlock="
			set "sLine="
			set /a "sbnum=0"
	
			echo %DATE%,%TIME:~0,-3%: Get SubPlans: [BCP.XML]: Plan: '%planname%', DTSX: '%dtsxname%'
			for /f "tokens=2 delims=<>" %%i in ('findstr /r /c:"<DTS:Executable .*DTS:refId=.*DTS:CreationName=.*DTS:Description=.*DTS:Disabled=.*DTS:DTSID=.*DTS:ExecutableType=.*DTS:FailParentOnFailure=.*DTS:LocaleID=.*DTS:ObjectName=.*>" "%dtsxname%"') do (
				set "sLine=%%~i" >nul 2>&1
				set /a "sbnum=!sbnum!+1"
				if defined sLine (
					echo %DATE%,%TIME:~0,-3%: Get SubPlans: [BCP.XML]: Processing subplan [!sbnum!] 
					call :GetSubplanBCPXML !sLine!
				)
			)
		:GetSubPlansBCPXMLEnd
		goto :GetSubPlansEnd

	:GetSubPlansEnd
	goto :eof

	:GetSubplanDTUTILXML

		if defined tmpline set "tmpline=%tmpline:!=%"
		if not defined tmpline goto :processDTUTILXMLLineEnd
		
		if defined inBlock goto :skiprefidDTUTILXML
			:: 1. Search for a string that contains DTS:refId="Package\***"
			echo %tmpline% | findstr /i /r "DTS:refId=\"Package\\.*\"" >nul 2>&1 || goto :skiprefidDTUTILXML
			:: 2. Exclude the string where there is a next \ after Package\*** - DTS:refId="Package\***\"
			echo %tmpline% | findstr /i /r "DTS:refId=\"Package\\.*\\.*\"" >nul 2>&1 && goto :skiprefidDTUTILXML
			:: 3.  Exclude the string where there is a next . after Package\*** - DTS:refId="Package\***."
			echo %tmpline% | findstr /i /r "DTS:refId=\"Package\\.*\..*\"" >nul 2>&1 && goto :skiprefidDTUTILXML
			for /f "tokens=2 delims==" %%i in ("%tmpline%") do if not defined subplanpkg set "subplanpkg=%%~i"
			if defined subplanpkg (
				set "inBlock=1"
				set /a "sbnum=!sbnum!+1"
				echo %DATE%,%TIME:~0,-3%: Get SubPlans: Processing subplan [!sbnum!] 
				echo %DATE%,%TIME:~0,-3%: [DTUTIL.XML]: Get Subplan package variables begin.
				goto :processDTUTILXMLLineEnd
			)
		:skiprefidDTUTILXML		

		if defined inBlock (
			echo "%tmpline%" | find /i "DTS:Variables" >nul 2>&1 && (
				echo %DATE%,%TIME:~0,-3%: [DTUTIL.XML]: Get Subplan variables end.
				set "inBlock="
				goto :processDTUTILXMLLineResults
				
			)
			echo %tmpline% | find /i "DTS:Description=" >nul 2>&1 && (
				if not defined subplandescr for /f "tokens=2 delims==" %%i in ("%tmpline%") do set "subplandescr=%%~i"
			)
			echo %tmpline% | find /i "DTS:DTSID=" >nul 2>&1 && (
				if not defined subplansid for /f "tokens=2 delims==" %%i in ("%tmpline%") do set "subplansid=%%~i"
			)
			echo %tmpline% | find /i "DTS:ObjectName=" >nul 2>&1 && (
				if not defined subplan for /f "tokens=2 delims==" %%i in ("%tmpline%") do set "subplan=%%~i"
			)
		)
		goto :processDTUTILXMLLineEnd

		:processDTUTILXMLLineResults
		call :SetSubplanResults

		:processDTUTILXMLLineEnd

	:GetSubplanDTUTILXMLEnd
	goto :eof
	
	:GetSubplanBCPXML

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
		
		echo %DATE%,%TIME:~0,-3%: [BCP.XML]: Get Subplan variables begin.

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

		echo %DATE%,%TIME:~0,-3%: [BCP.XML]: Get Subplan variables end.

		call :SetSubplanResults

	:GetSubplanBCPXMLEnd
	goto :eof

	:SetSubplanResults

		if defined subplanpkg if defined subplandescr if defined subplansid if defined subplan (
			if /i "%subplanpkg:package\=%" == "%subplan%" (
				echo %DATE%,%TIME:~0,-3%: Set Subplan results: '%subplanpkg%':'%subplandescr%':'%subplansid%':'%subplan%'
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
				echo %DATE%,%TIME:~0,-3%: WARNING: The subplans of '%planname%' may contain errors. Check plan and subplans configuration in SQL server.
			)
		)

		set "tmpline="
		set "subplanpkg="
		set "subplandescr="
		set "subplansid="
		set "subplan="

	:SetSubplanResultsEnd
	goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:ExportNonMaintenancePlanJobs
	
	echo %DATE%,%TIME:~0,-3%: Processing JOBS not associated with any maintenance plans.
	echo %DATE%,%TIME:~0,-3%: Processing JOBS not associated with any maintenance plans end.

	echo %DATE%,%TIME:~0,-3%: Exported JOBS Summary: '%EXPORTED_JOBS%'

:ExportNonMaintenancePlanJobsEnd
goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:GeneratePlanJobTSQLFile
:PlanJOBsTsqlExportbegin

	echo %DATE%,%TIME:~0,-3%: Processing JOBS for plan: '%PLAN_NAME%' Begin.

	set "ExportPath=%EXPORT_DIR%\%SQL_SERVER%"
	set "PLANEXPORTED_JOBS="

	call :ExportPlanJOBStoTSQL

	if defined EXPORTED_JOBS (
		set "EXPORTED_JOBS=%EXPORTED_JOBS%%PLANEXPORTED_JOBS%"
	) else (
		set "EXPORTED_JOBS=%PLANEXPORTED_JOBS%"
	)

	echo %DATE%,%TIME:~0,-3%: Exported JOBS for plan: '%PLAN_NAME%: Summary: '%PLANEXPORTED_JOBS%'
	echo %DATE%,%TIME:~0,-3%: Processing JOBS for plan: '%PLAN_NAME%' End.

:PlanJOBsTsqlExportEnd
goto :eof

:ExportSysOperators
	if "%ServerSysOperatorsProcessed%" == "true" goto :ExportSysOperatorsEnd
	call :collectAndExportSysOperators
:ExportSysOperatorsEnd
goto :eof

:ExportPlanJOBStoTSQL

	if not defined subplans (
		goto :ExportPlanJOBStoTSQLEnd
	)

	set "jobID="
	set "jobNAME="
	
	set "subplanslist=%subplans:;= %"
	set "subplanssidslist=%subplans:;= %"
	set "tmpsubplan="
	set /a "sptoken=0"
	
	for %%i in (%subplanslist%) do (
		set "tmpsubplan=%%~i"
		set /a "sptoken+=1"
		call :CreateExportPlanJOBTSQL
	)
	
:ExportPlanJOBStoTSQLEnd
goto :eof

:CreateExportPlanJOBTSQL
		echo %DATE%,%TIME:~0,-3%: Processing JOB for plan: '%PLAN_NAME%': Subplan: '%tmpsubplan%' Begin
		call :collectAndExportPlanJobParameters
		echo %DATE%,%TIME:~0,-3%: Processing JOB for plan: '%PLAN_NAME%': Subplan: '%tmpsubplan%' End
:CreateExportPlanJOBTSQL
goto :eof

:collectAndExportSysOperators

	::: Collect sysoperators

		:ProcSysOperators

			echo %DATE%,%TIME:~0,-3%: First, let's perform a one-time processing of msdb.dbo.sysoperators records.
			echo %DATE%,%TIME:~0,-3%: Sysoperators exporting to file: '%EXPORT_DIR%\%SQL_SERVER%\SysOperators.sql'
			if not exist "%EXPORT_DIR%\%SQL_SERVER%" mkdir "%EXPORT_DIR%\%SQL_SERVER%" >nul 2>&1
			if exist "%EXPORT_DIR%\%SQL_SERVER%\SysOperators.sql" del /f /q "%EXPORT_DIR%\%SQL_SERVER%\SysOperators.sql" >nul 2>&1
			set "SysOpsSqlHeader=false"

			::: msdb.dbo.sysoperators
			set "name="
			set "enabled="
			set "email_address="
			set "pager_address="
			set "weekday_pager_start_time="
			set "weekday_pager_end_time="
			set "saturday_pager_start_time="
			set "saturday_pager_end_time="
			set "sunday_pager_start_time="
			set "sunday_pager_end_time="
			set "pager_days="
			set "netsend_address="
			set "category_id="
			
			::: msdb.dbo.syscategories - Operator is category_class = 3; category_id = 99;
			set "category_name="

			set "msdb.dbo.sysoperators="
			
			::: Test delims - ¶
			for /f "usebackq tokens=*" %%# in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT name, enabled, email_address, pager_address, weekday_pager_start_time, weekday_pager_end_time, saturday_pager_start_time, saturday_pager_end_time, sunday_pager_start_time, sunday_pager_end_time, pager_days, netsend_address, category_id FROM msdb.dbo.sysoperators" 2^>nul`) do (
				set "msdb.dbo.sysoperators=%%~#¶"
				set "msdb.dbo.sysoperators=!msdb.dbo.sysoperators:"=❦!"
				set "name="
				set "enabled="
				set "email_address="
				set "pager_address="
				set "weekday_pager_start_time="
				set "weekday_pager_end_time="
				set "saturday_pager_start_time="
				set "saturday_pager_end_time="
				set "sunday_pager_start_time="
				set "sunday_pager_end_time="
				set "pager_days="
				set "netsend_address="
				set "category_id="
				for /f "usebackq tokens=1-13 delims=¶" %%a in (`echo "!msdb.dbo.sysoperators!"`) do (
					set "name=%%~a"
					set "enabled=%%~b"
					set "email_address=%%~c"
					set "pager_address=%%~d"
					set "weekday_pager_start_time=%%~e"
					set "weekday_pager_end_time=%%~f"
					set "saturday_pager_start_time=%%~g"
					set "saturday_pager_end_time=%%~h"
					set "sunday_pager_start_time=%%~i"
					set "sunday_pager_end_time=%%~j"
					set "pager_days=%%~k"
					set "netsend_address=%%~l"
					set "category_id=%%~m"
				)

				call :trim_spaces "!name!" name
				call :trim_spaces "!enabled!" enabled
				call :trim_spaces "!email_address!" email_address
				call :trim_spaces "!pager_address!" pager_address
				call :trim_spaces "!weekday_pager_start_time!" weekday_pager_start_time
				call :trim_spaces "!weekday_pager_end_time!" weekday_pager_end_time
				call :trim_spaces "!saturday_pager_start_time!" saturday_pager_start_time
				call :trim_spaces "!saturday_pager_end_time!" saturday_pager_end_time
				call :trim_spaces "!sunday_pager_start_time!" sunday_pager_start_time
				call :trim_spaces "!sunday_pager_end_time!" sunday_pager_end_time
				call :trim_spaces "!pager_days!" pager_days
				call :trim_spaces "!netsend_address!" netsend_address
				call :trim_spaces "!category_id!" category_id
				
				set "category_name=[Uncategorized]"
				if defined name if defined category_id (
					for /f "usebackq tokens=1 delims=¶" %%a in (`
						sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT name FROM msdb.dbo.syscategories WHERE category_id=!category_id! AND category_class=3"
					`) do (
						set "category_name=%%~a"
						call :trim_spaces "!category_name!" category_name
					)			
				)
				if defined name (
					echo %DATE%,%TIME:~0,-3%: Sysoperator: '!name!', Mail: '!email_address!', Enabled: '!enabled!': Cat.Id: '!category_id!': Cat.Name: '!category_name!': Pager: '!pager_address!': NetSend: '!netsend_address!'
					if /i "!SysOpsSqlHeader!" == "false" (
						call :GenerateSysOpsTSQLFile :SysOpsSqlHeader >"%EXPORT_DIR%\%SQL_SERVER%\SysOperators.sql"
						set "SysOpsSqlHeader=true"
					)
					call :GenerateSysOpsTSQLFile :SysOpsSql >>"%EXPORT_DIR%\%SQL_SERVER%\SysOperators.sql"
				)
			)
			if defined name (
				set "ServerSysOperatorsProcessed=true"
			) else (
				echo No SysOperators defined.
				goto :ProcSysOperatorsEnd
			)
			
		:ProcSysOperatorsEnd

		set "name="
		set "enabled="
		set "email_address="
		set "pager_address="
		set "weekday_pager_start_time="
		set "weekday_pager_end_time="
		set "saturday_pager_start_time="
		set "saturday_pager_end_time="
		set "sunday_pager_start_time="
		set "sunday_pager_end_time="
		set "pager_days="
		set "netsend_address="
		set "category_id="

		set "category_name="

		set "msdb.dbo.sysoperators="

:collectAndExportSysOperatorsEnd
goto :eof

:GenerateSysOpsTSQLFile

	if /i not "%~1" == ":SysOpsSqlHeader" (
		if /i not "%~1" == ":SysOpsSql" (
			goto :GenerateSysOpsTSQLFileEnd
		)
	)
	goto %~1

	:SysOpsSqlHeader
		echo.SET NOCOUNT ON;
		echo.GO
	:SysOpsSqlHeaderEnd
	goto :GenerateSysOpsTSQLFileEnd

	:SysOpsSql
		echo.
		echo.IF NOT EXISTS (
		echo.	SELECT 1 
		echo.	FROM msdb.dbo.sysoperators 
		echo.	WHERE name = N'%name%'
		echo.)
		echo.BEGIN
		echo.PRINT 'Add operator: %name%, e-mail: %email_address%';
		echo.EXEC msdb.dbo.sp_add_operator @name=N'%name%', 
		echo.		@enabled=%enabled%, 
		if defined email_address (
		echo.		@email_address=N'%email_address%', 
		)
		if defined pager_address (
		echo.		@pager_address=N'%pager_address%', 
		)
		echo.		@weekday_pager_start_time=%weekday_pager_start_time%, 
		echo.		@weekday_pager_end_time=%weekday_pager_end_time%, 
		echo.		@saturday_pager_start_time=%saturday_pager_start_time%, 
		echo.		@saturday_pager_end_time=%saturday_pager_end_time%, 
		echo.		@sunday_pager_start_time=%sunday_pager_start_time%, 
		echo.		@sunday_pager_end_time=%sunday_pager_end_time%, 
		echo.		@pager_days=%pager_days%, 
		if defined netsend_address (
		echo.		@netsend_address=N'%netsend_address%', 
		)
		echo.		@category_name=N'%category_name%'
		echo.END
		echo.ELSE
		echo.	BEGIN
		echo.	PRINT 'Operator already exists: %name%';
		echo.END
		echo.GO
	:SysOpsSqlEnd
	goto :GenerateSysOpsTSQLFileEnd

:GenerateSysOpsTSQLFileEnd
goto :eof

:collectAndExportPlanJobParameters

	::: Get Job Data to VARIABLES (Variables will be declared later in the :VAR block)
	
	set "T-SQLDATE=%DATE%"
	set "T-SQLTIME=%TIME:~0,-3%"

	echo %DATE%,%TIME:~0,-3%: Collect JOB params for: '%PLAN_NAME%.%tmpsubplan%' and Generate TSQL File: '%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql'

	::: Collect Job params and call :GenerateTSQLFile :JobHeader
		::: msdb.dbo.sysjobs
			set "job_id="
			set "originating_server_id="
			set "name="
			set "enabled="
			set "description="
			set "start_step_id="
			set "category_id="
			set "owner_sid="
			set "notify_level_eventlog="
			set "notify_level_email="
			set "notify_level_netsend="
			set "notify_level_page="
			set "notify_email_operator_id="
			set "notify_netsend_operator_id="
			set "notify_page_operator_id="
			set "delete_level="
			set "date_created="
			set "date_modified="
			set "version_number="

		::: msdb.dbo.sysoperators
			set "notify_email_operator_name="

		::: Test delims - ¶
			set "msdb.dbo.sysjobs="
			for /f "usebackq tokens=*" %%# in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT job_id, originating_server_id, name, enabled, description, start_step_id, category_id, owner_sid, notify_level_eventlog, notify_level_email, notify_level_netsend, notify_level_page, notify_email_operator_id, notify_netsend_operator_id, notify_page_operator_id, delete_level, date_created, date_modified, version_number FROM msdb.dbo.sysjobs WHERE name=N'%PLAN_NAME%.%tmpsubplan%'" 2^>nul`) do (
				set "msdb.dbo.sysjobs=%%~#¶"
				set "msdb.dbo.sysjobs=!msdb.dbo.sysjobs:"=❦!"
			)
			for /f "usebackq tokens=1-8 delims=¶" %%a in (`echo "%msdb.dbo.sysjobs%"`) do (
				set "job_id=%%~a"
				set "originating_server_id=%%~b"
				set "name=%%~c"
				set "enabled=%%~d"
				set "description=%%~e"
				set "start_step_id=%%~f"
				set "category_id=%%~g"
				set "owner_sid=%%~h"
			)
			for /f "usebackq tokens=9-16 delims=¶" %%a in (`echo "%msdb.dbo.sysjobs%"`) do (
				set "notify_level_eventlog=%%~a"
				set "notify_level_email=%%~b"
				set "notify_level_netsend=%%~c"
				set "notify_level_page=%%~d"
				set "notify_email_operator_id=%%~e"
				set "notify_netsend_operator_id=%%~f"
				set "notify_page_operator_id=%%~g"
				set "delete_level=%%~h"
			)
			for /f "usebackq tokens=17-19 delims=¶" %%a in (`echo "%msdb.dbo.sysjobs%"`) do (
				set "date_created=%%~a"
				set "date_modified=%%~b"
				set "version_number=%%~c"
			)

			call :trim_spaces "!job_id!" job_id
			call :trim_spaces "!originating_server_id!" originating_server_id
			call :trim_spaces "!name!" name
			call :trim_spaces "!enabled!" enabled
			call :trim_spaces "!description!" description
			call :trim_spaces "!start_step_id!" start_step_id
			call :trim_spaces "!category_id!" category_id
			call :trim_spaces "!owner_sid!" owner_sid
			call :trim_spaces "!notify_level_eventlog!" notify_level_eventlog
			call :trim_spaces "!notify_level_email!" notify_level_email
			call :trim_spaces "!notify_level_netsend!" notify_level_netsend
			call :trim_spaces "!notify_level_page!" notify_level_page
			call :trim_spaces "!notify_email_operator_id!" notify_email_operator_id
			call :trim_spaces "!notify_netsend_operator_id!" notify_netsend_operator_id
			call :trim_spaces "!notify_page_operator_id!" notify_page_operator_id
			call :trim_spaces "!delete_level!" delete_level
			call :trim_spaces "!date_created!" date_created
			call :trim_spaces "!date_modified!" date_modified
			call :trim_spaces "!version_number!" version_number

			::: Get owner_login_name by owner_sid
			set "owner_login_name="
			for /f "usebackq tokens=*" %%a in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT name FROM sys.server_principals WHERE sid=!owner_sid!" 2^>nul`) do (
				set "owner_login_name=%%~a"
				call :trim_spaces "!owner_login_name!" owner_login_name
			)
			
			::: Get category_name and category_type by category_id
			set "category_name=Database Maintenance"
			set "category_type=1"
			set "category_type_str=LOCAL"
			for /f "usebackq tokens=1,2 delims=¶" %%a in (`
				sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT name, category_type FROM msdb.dbo.syscategories WHERE category_id=!category_id! AND category_class=1"
			`) do (
				set "category_name=%%~a"
				set "category_type=%%~b"
				call :trim_spaces "!category_name!" category_name
				call :trim_spaces "!category_type!" category_type
				if "!category_type!"=="1" set "category_type_str=LOCAL"
				if "!category_type!"=="2" set "category_type_str=MULTI-SERVER"
				if "!category_type!"=="3" set "category_type_str=NONE"
				if "!category_type!"=="" set "category_type_str=NONE"
			)

			set "notify_email_operator_name="
			if not "%notify_email_operator_id%" == "0" (
				for /f "usebackq delims=" %%O in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT name FROM msdb.dbo.sysoperators WHERE id=%notify_email_operator_id%"`) do (
					set "notify_email_operator_name=%%O"
					call :trim_spaces "!notify_email_operator_name!" notify_email_operator_name
				)			
			)
			set "jobID=!job_id!"
			set "jobNAME=!name!"
			echo %DATE%,%TIME:~0,-3%: Job: '!jobID!', Name: '!jobNAME!', Version: '!version_number!', Category: '!category_name!':'!category_type!':'!category_type_str!', Owner Login Name: '!owner_login_name!'
			if defined notify_email_operator_name (
				echo %DATE%,%TIME:~0,-3%: Job: '!jobID!', Email operator Id: '%notify_email_operator_id%', Email operator Name: '%notify_email_operator_name%'
			)
		call :GenerateTSQLFile :JobHeader>"%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql" 2>&1

	::: Collect Job Steps and call :GenerateTSQLFile :JobSteps
		::: msdb.dbo.sysjobsteps
		::: set "job_id=" defined in Job params
			set "step_id="
			set "step_name="
			set "subsystem="
			set "command="
			set "flags="
			set "additional_parameters="
			set "cmdexec_success_code="
			set "on_success_action="
			set "on_success_step_id="
			set "on_fail_action="
			set "on_fail_step_id="
			set "server="
			set "database_name="
			set "database_user_name="
			set "retry_attempts="
			set "retry_interval="
			set "os_run_priority="
			set "output_file_name="
			set "proxy_id="
			set "step_uid="

		::: Test delims- ¶
			set "msdb.dbo.sysjobsteps="
			for /f "usebackq tokens=*" %%# in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT job_id, step_id, step_name, subsystem, command, flags, additional_parameters, cmdexec_success_code, on_success_action, on_success_step_id, on_fail_action, on_fail_step_id, server, database_name, database_user_name, retry_attempts, retry_interval, os_run_priority, output_file_name, proxy_id, step_uid FROM msdb.dbo.sysjobsteps WHERE job_id='%jobID%' ORDER BY step_name" 2^>nul`) do (
				set "msdb.dbo.sysjobsteps=%%~#¶"
				set "msdb.dbo.sysjobsteps=!msdb.dbo.sysjobsteps:"=❦!"
				set "step_id="
				set "step_name="
				set "subsystem="
				set "command="
				set "flags="
				set "additional_parameters="
				set "cmdexec_success_code="
				set "on_success_action="
				set "on_success_step_id="
				set "on_fail_action="
				set "on_fail_step_id="
				set "server="
				set "database_name="
				set "database_user_name="
				set "retry_attempts="
				set "retry_interval="
				set "os_run_priority="
				set "output_file_name="
				set "proxy_id="
				set "step_uid="
				for /f "tokens=2-9 delims=¶" %%a in ("!msdb.dbo.sysjobsteps!") do (
					set "step_id=%%~a"
					set "step_name=%%~b"
					set "subsystem=%%~c"
					set "command=%%~d"
					set "flags=%%~e"
					set "additional_parameters=%%~f"
					set "cmdexec_success_code=%%~g"
					set "on_success_action=%%~h"
				)
				for /f "tokens=10-17 delims=¶" %%a in ("!msdb.dbo.sysjobsteps!") do (
					set "on_success_step_id=%%~a"
					set "on_fail_action=%%~b"
					set "on_fail_step_id=%%~c"
					set "server=%%~d"
					set "database_name=%%~e"
					set "database_user_name=%%~f"
					set "retry_attempts=%%~g"
					set "retry_interval=%%~h"
				)
				for /f "tokens=18-21 delims=¶" %%a in ("!msdb.dbo.sysjobsteps!") do (
					set "os_run_priority=%%~a"
					set "output_file_name=%%~b"
					set "proxy_id=%%~c"
					set "step_uid=%%~d"
				)

				call :trim_spaces "!step_id!" step_id
				call :trim_spaces "!step_name!" step_name
				call :trim_spaces "!subsystem!" subsystem
				call :trim_spaces "!command!" command
				call :trim_spaces "!flags!" flags
				call :trim_spaces "!additional_parameters!" additional_parameters
				call :trim_spaces "!cmdexec_success_code!" cmdexec_success_code
				call :trim_spaces "!on_success_action!" on_success_action
				call :trim_spaces "!on_success_step_id!" on_success_step_id
				call :trim_spaces "!on_fail_action!" on_fail_action
				call :trim_spaces "!on_fail_step_id!" on_fail_step_id
				call :trim_spaces "!server!" server
				call :trim_spaces "!database_name!" database_name
				call :trim_spaces "!database_user_name!" database_user_name
				call :trim_spaces "!retry_attempts!" retry_attempts
				call :trim_spaces "!retry_interval!" retry_interval
				call :trim_spaces "!os_run_priority!" os_run_priority
				call :trim_spaces "!output_file_name!" output_file_name
				call :trim_spaces "!proxy_id!" proxy_id
				call :trim_spaces "!step_uid!" step_uid

				echo %DATE%,%TIME:~0,-3%: Job: '!job_id!': StepID: '!step_id!': StepUID:'!step_uid!': StepNAME:'!step_name!': SubSYS:'!subsystem!': Flags:'!flags!'
				echo %DATE%,%TIME:~0,-3%: Job: '!job_id!': StepID: '!step_id!': Command: '!command!'

				call :GenerateTSQLFile :JobSteps >>"%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql" 2>&1
				call :GenerateTSQLFile :JobStartStep >>"%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql" 2>&1
			)

	::: Collect Job Schedules and call :GenerateTSQLFile :JobSchedules

		::: msdb.dbo.sysjobschedules
			set "schedule_id="
			set "job_id="
			set "next_run_date="
			set "next_run_time="

		::: msdb.dbo.sysschedules
			set "schedule_id="
			set "schedule_uid="
			set "originating_server_id="
			set "name="
			set "owner_sid="
			set "enabled="
			set "freq_type="
			set "freq_interval="
			set "freq_subday_type="
			set "freq_subday_interval="
			set "freq_relative_interval="
			set "freq_recurrence_factor="
			set "active_start_date="
			set "active_end_date="
			set "active_start_time="
			set "active_end_time="
			set "date_created="
			set "date_modified="
			set "version_number="

		set "msdb.dbo.sysjobschedules="
		for /f "usebackq tokens=*" %%# in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT schedule_id, job_id, next_run_date, next_run_time FROM msdb.dbo.sysjobschedules WHERE job_id='!jobID!' ORDER BY schedule_id"`) do (
			set "msdb.dbo.sysjobschedules=%%~#¶"
			set "msdb.dbo.sysjobschedules=!msdb.dbo.sysjobschedules:"=❦!"
			set "schedule_id="
			set "job_id="
			set "next_run_date="
			set "next_run_time="
			set "schedule_id="
			set "schedule_uid="
			set "originating_server_id="
			set "name="
			set "owner_sid="
			set "enabled="
			set "freq_type="
			set "freq_interval="
			set "freq_subday_type="
			set "freq_subday_interval="
			set "freq_relative_interval="
			set "freq_recurrence_factor="
			set "active_start_date="
			set "active_end_date="
			set "active_start_time="
			set "active_end_time="
			set "date_created="
			set "date_modified="
			set "version_number="

			for /f "tokens=1-4 delims=¶" %%a in ("!msdb.dbo.sysjobschedules!") do (
				set "schedule_id=%%~a"
				set "job_id=%%~b"
				set "next_run_date=%%~c"
				set "next_run_time=%%~d"

				call :trim_spaces "!schedule_id!" schedule_id
				call :trim_spaces "!job_id!" job_id
				call :trim_spaces "!next_run_date!" next_run_date
				call :trim_spaces "!next_run_time!" next_run_time

				echo %DATE%,%TIME:~0,-3%: Job: '!job_id!': Schedule_id: '!schedule_id!': NextRun: '!next_run_date!, !next_run_time!'

				rem Get schedule params for schedule_id
				set "msdb.dbo.sysschedules="
				for /f "usebackq tokens=*" %%S in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT schedule_id, schedule_uid, originating_server_id, name, owner_sid, enabled, freq_type, freq_interval, freq_subday_type, freq_subday_interval, freq_relative_interval, freq_recurrence_factor, active_start_date, active_end_date, active_start_time, active_end_time, date_created, date_modified, version_number FROM msdb.dbo.sysschedules WHERE schedule_id='!schedule_id!'"`) do (
					set "msdb.dbo.sysschedules=%%~S¶"
					set "msdb.dbo.sysschedules=!msdb.dbo.sysschedules:"=❦!"
					for /f "tokens=1-8 delims=¶" %%i in ("!msdb.dbo.sysschedules!") do (
						rem set "schedule_id=%%~i" Defined earlier
						set "schedule_uid=%%~j"
						set "originating_server_id=%%~k"
						set "name=%%~l"
						set "owner_sid=%%~m"
						set "enabled=%%~n"
						set "freq_type=%%~o"
						set "freq_interval=%%~p"
					)
					for /f "tokens=9-16 delims=¶" %%i in ("!msdb.dbo.sysschedules!") do (
						set "freq_subday_type=%%~i"
						set "freq_subday_interval=%%~j"
						set "freq_relative_interval=%%~k"
						set "freq_recurrence_factor=%%~l"
						set "active_start_date=%%~m"
						set "active_end_date=%%~n"
						set "active_start_time=%%~o"
						set "active_end_time=%%~p"
					)
					for /f "tokens=17-19 delims=¶" %%i in ("!msdb.dbo.sysschedules!") do (
						set "date_created=%%~i"
						set "date_modified=%%~j"
						set "version_number=%%~k"
					)

					call :trim_spaces "!schedule_uid!" schedule_uid
					call :trim_spaces "!originating_server_id!" originating_server_id
					call :trim_spaces "!name!" name
					call :trim_spaces "!owner_sid!" owner_sid
					call :trim_spaces "!enabled!" enabled
					call :trim_spaces "!freq_type!" freq_type
					call :trim_spaces "!freq_interval!" freq_interval
					call :trim_spaces "!freq_subday_type!" freq_subday_type
					call :trim_spaces "!freq_subday_interval!" freq_subday_interval
					call :trim_spaces "!freq_relative_interval!" freq_relative_interval
					call :trim_spaces "!freq_recurrence_factor!" freq_recurrence_factor
					call :trim_spaces "!active_start_date!" active_start_date
					call :trim_spaces "!active_end_date!" active_end_date
					call :trim_spaces "!active_start_time!" active_start_time
					call :trim_spaces "!active_end_time!" active_end_time
					call :trim_spaces "!date_created!" date_created
					call :trim_spaces "!date_modified!" date_modified
					call :trim_spaces "!version_number!" version_number

					echo %DATE%,%TIME:~0,-3%: Job: '!jobID!': Schedule: '!name!': Enabled: '!enabled!': FreqType: '!freq_type!': FreqInterval: '!freq_interval!'
					call :GenerateTSQLFile :JobSchedules >>"%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql" 2>&1
				)
			)
		)
		
	::: Get job server and call :GenerateTSQLFile :JobFooter
		::: msdb.dbo.sysjobservers
		set "server_name="
		for /f "usebackq tokens=*" %%S in (`sqlcmd -S %SQL_SERVER% -E -h -1 -w 65535 -Q "SET NOCOUNT ON; SELECT s.name FROM msdb.dbo.sysjobservers js JOIN sys.servers s ON s.server_id=js.server_id WHERE js.job_id='!jobID!'"`) do (
			set "tmp_server_name=%%~S"
			set "tmp_server_name=!tmp_server_name:"=❦!"
			call :trim_spaces "!tmp_server_name!" tmp_server_name
			set "server_name=!tmp_server_name!"
			if "%SQL_SERVER%"=="!server_name!" set "server_name=local"
			echo %DATE%,%TIME:~0,-3%: Job: '!jobID!': Server: '!server_name!':'!tmp_server_name!'
		)
		::: Set Job Server before create alerts
		call :GenerateTSQLFile :JobServer >>"%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql" 2>&1

	::: Get job alerts and call :GenerateTSQLFile :JobAlerts
		::: msdb.dbo.sysalerts
		set "id="
		set "name="
		set "event_source="
		set "event_category_id="
		set "event_id="
		set "message_id="
		set "severity="
		set "enabled="
		set "delay_between_responses="
		set "last_occurrence_date="
		set "last_occurrence_time="
		set "last_response_date="
		set "last_response_time="
		set "notification_message="
		set "include_event_description="
		set "database_name="
		set "event_description_keyword="
		set "occurrence_count="
		set "count_reset_date="
		set "count_reset_time="
		set "job_id="
		set "has_notification="
		set "flags="
		set "performance_condition="
		set "category_id="

		::: msdb.dbo.syscategories
		set "category_name="

		::: msdb.dbo.sp_help_alert
		set "wmi_namespace="
		set "wmi_query="
		set "sp_help_alert_flags="
		set "raise_snmp_trap="

		set "msdb.dbo.sysalerts="
		for /f "usebackq tokens=*" %%A in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; SELECT id, name, event_source, event_category_id, event_id, message_id, severity, enabled, delay_between_responses, last_occurrence_date, last_occurrence_time, last_response_date, last_response_time, notification_message, include_event_description, database_name, event_description_keyword, occurrence_count, count_reset_date, count_reset_time, job_id, has_notification, flags, performance_condition, category_id FROM msdb.dbo.sysalerts WHERE job_id='%jobID%'"`) do (
			set "msdb.dbo.sysalerts=%%~A¶"
			set "id="
			set "name="
			set "event_source="
			set "event_category_id="
			set "event_id="
			set "message_id="
			set "severity="
			set "enabled="
			set "delay_between_responses="
			set "last_occurrence_date="
			set "last_occurrence_time="
			set "last_response_date="
			set "last_response_time="
			set "notification_message="
			set "include_event_description="
			set "database_name="
			set "event_description_keyword="
			set "occurrence_count="
			set "count_reset_date="
			set "count_reset_time="
			set "job_id="
			set "has_notification="
			set "flags="
			set "performance_condition="
			set "category_id="
			set "category_name="
			set "wmi_namespace="
			set "wmi_query="
			set "sp_help_alert_flags="
			set "raise_snmp_trap="
			for /f "tokens=1-8 delims=¶" %%a in ("!msdb.dbo.sysalerts!") do (
				set "id=%%~a"
				set "name=%%~b"
				set "event_source=%%~c"
				set "event_category_id=%%~d"
				set "event_id=%%~e"
				set "message_id=%%~f"
				set "severity=%%~g"
				set "enabled=%%~h"
			)
			for /f "tokens=9-16 delims=¶" %%a in ("!msdb.dbo.sysalerts!") do (
				set "delay_between_responses=%%~a"
				set "last_occurrence_date=%%~b"
				set "last_occurrence_time=%%~c"
				set "last_response_date=%%~d"
				set "last_response_time=%%~e"
				set "notification_message=%%~f"
				set "include_event_description=%%~g"
				set "database_name=%%~h"
			)
			for /f "tokens=17-25 delims=¶" %%a in ("!msdb.dbo.sysalerts!") do (
				set "event_description_keyword=%%~a"
				set "occurrence_count=%%~b"
				set "count_reset_date=%%~c"
				set "count_reset_time=%%~d"
				rem set "job_id=%%~e"
				set "has_notification=%%~f"
				set "flags=%%~g"
				set "performance_condition=%%~h"
				set "category_id=%%~i"
			)
			if defined name (
				call :trim_spaces "!id!" id
				call :trim_spaces "!name!" name
				call :trim_spaces "!event_source!" event_source
				call :trim_spaces "!event_category_id!" event_category_id
				call :trim_spaces "!event_id!" event_id
				call :trim_spaces "!message_id!" message_id
				call :trim_spaces "!severity!" severity
				call :trim_spaces "!enabled!" enabled
				call :trim_spaces "!delay_between_responses!" delay_between_responses
				call :trim_spaces "!last_occurrence_date!" last_occurrence_date
				call :trim_spaces "!last_occurrence_time!" last_occurrence_time
				call :trim_spaces "!last_response_date!" last_response_date
				call :trim_spaces "!last_response_time!" last_response_time
				call :trim_spaces "!notification_message!" notification_message
				call :trim_spaces "!include_event_description!" include_event_description
				call :trim_spaces "!database_name!" database_name
				call :trim_spaces "!event_description_keyword!" event_description_keyword
				call :trim_spaces "!occurrence_count!" occurrence_count
				call :trim_spaces "!count_reset_date!" count_reset_date
				call :trim_spaces "!count_reset_time!" count_reset_time
				rem call :trim_spaces "!job_id!" job_id
				call :trim_spaces "!has_notification!" has_notification
				call :trim_spaces "!flags!" flags
				call :trim_spaces "!performance_condition!" performance_condition
				call :trim_spaces "!category_id!" category_id
				
				if defined name (
					for /f "usebackq tokens=*" %%C in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -W -Q "SET NOCOUNT ON; SELECT name FROM msdb.dbo.syscategories WHERE category_id='!category_id!';"`) do (
						set "category_name=%%~C"
						call :trim_spaces "!category_name!" category_name
					)
					for /f "usebackq tokens=1,24,27,28 delims=¶" %%A in (`sqlcmd -S %SQL_SERVER% -E -d msdb -h -1 -s "¶" -w 65535 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_help_alert @name=N'!name!';"`) do (
						rem %%A=alert_name
						rem %%B=flags (можно использовать для raise_snmp_trap)
						rem %%C=wmi_namespace
						rem %%D=wmi_query
						set "sp_help_alert_flags=%%~B"
						set "wmi_namespace=%%~C"
						set "wmi_query=%%~D"
						set "raise_snmp_trap=0"
						call :trim_spaces "!wmi_namespace!" wmi_namespace
						call :trim_spaces "!wmi_query!" wmi_query
						call :trim_spaces "!sp_help_alert_flags!" sp_help_alert_flags
						rem check bit in SNMP (0x01) in flags
						set /a "tmp=0"
						if defined sp_help_alert_flags if not "!sp_help_alert_flags!" == "0" (
							set /a "sp_help_alert_flags=!sp_help_alert_flags!"
							set /a "tmp=!sp_help_alert_flags! & 1"
						)
						if !tmp! NEQ 0 set "raise_snmp_trap=1"
						echo "!wmi_namespace!" | find /i "NULL" >nul 2>&1 && set "wmi_namespace="
						echo "!wmi_query!" | find /i "NULL" >nul 2>&1 && set "wmi_query="

					)
					echo %DATE%,%TIME:~0,-3%: Job: '!jobID!': Alert Id: '!id!': Name: '!name!': Event Source: '!event_source!': Enabled: '!enabled!': Category: '!category_name!': RaiseSNMP: '!raise_snmp_trap!': WMI_NS: '!wmi_namespace!': WMI_Query: '!wmi_query!'
					call :GenerateTSQLFile :JobAlert >>"%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql" 2>&1
				)
			)
		)

		call :GenerateTSQLFile :JobFooter >>"%EXPORT_DIR%\%SQL_SERVER%\%PLAN_NAME%.%tmpsubplan%.sql" 2>&1

		if defined PLANEXPORTED_JOBS (
			set "PLANEXPORTED_JOBS=%PLANEXPORTED_JOBS%%jobID%;"
		) else (
			set "PLANEXPORTED_JOBS=%jobID%;"
		)

:collectAndExportPlanJobParametersEnd
goto :eof

:GenerateTSQLFile

	::: Generate T-SQL for Subplan

	set "OutType=%~1"
	if not "%OutType%" == ":JobHeader" (
		if not "%OutType%" == ":JobSteps" (
			if not "%OutType%" == ":JobStartStep" (
				if not "%OutType%" == ":JobSchedules" (
					if not "%OutType%" == ":JobServer" (
						if not "%OutType%" == ":JobAlert" (
							if not "%OutType%" == ":JobFooter" (
								echo %DATE%,%TIME:~0,-3%: ERROR: GenerateTSQLFile: OutType not defined!
								goto :GenerateTSQLFileEnd
							)
						)
					)
				)
			)
		)
	)

	goto %OutType%
	echo GenerateTSQLFile: CALL PARAMS ERROR
	goto :eof

	::: JOB HEADER [Settings]

		:JobHeader
			echo.SET NOCOUNT ON;
			echo.GO
			echo.
			echo.---USE [msdb]
			echo.---GO
			echo.
			echo./****** Object:  Job [%PLAN_NAME%.%tmpsubplan%]    Script Date: %T-SQLDATE% %T-SQLTIME% ******/
			echo.BEGIN TRANSACTION
			echo.DECLARE @ReturnCode INT
			echo.SELECT @ReturnCode = 0
			echo./****** Object:  JobCategory [%category_name%]    Script Date: %T-SQLDATE% %T-SQLTIME% ******/
			echo.IF NOT EXISTS ^(SELECT name FROM msdb.dbo.syscategories WHERE name=N'%category_name%' AND category_class=1^)
			echo.BEGIN
			echo.EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'%category_type_str%', @name=N'%category_name%'
			echo.IF ^(@@ERROR ^<^> 0 OR @ReturnCode ^<^> 0^) GOTO QuitWithRollback
			echo.
			echo.END
			echo.
			echo.DECLARE @jobId BINARY^(16^)
			echo.EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'%PLAN_NAME%.%tmpsubplan%', 
			echo.		@enabled=%enabled%, 
			echo.		@notify_level_eventlog=%notify_level_eventlog%, 
			echo.		@notify_level_email=%notify_level_email%, 
			echo.		@notify_level_netsend=%notify_level_netsend%, 
			echo.		@notify_level_page=%notify_level_page%, 
			echo.		@delete_level=%delete_level%, 
			echo.		@description=N'%description%', 
			echo.		@category_name=N'%category_name%', 
			if defined notify_email_operator_name (
			echo.		@owner_login_name=N'%owner_login_name%', 
			echo.		@notify_email_operator_name=N'%notify_email_operator_name%', @job_id = @jobId OUTPUT
			) else (
			echo.		@owner_login_name=N'%owner_login_name%', @job_id = @jobId OUTPUT
			)
			echo.IF ^(@@ERROR ^<^> 0 OR @ReturnCode ^<^> 0^) GOTO QuitWithRollback
		:JobHeaderEnd
		goto :GenerateTSQLFileEnd

		set "job_id="
		set "originating_server_id="
		set "name="
		set "enabled="
		set "description="
		set "start_step_id="
		set "category_id="
		set "owner_sid="
		set "notify_level_eventlog="
		set "notify_level_email="
		set "notify_level_netsend="
		set "notify_level_page="
		set "notify_email_operator_id="
		set "notify_netsend_operator_id="
		set "notify_page_operator_id="
		set "delete_level="
		set "date_created="
		set "date_modified="
		set "version_number="

	::: JOB HEADER [Settings] END

	::: JOB STEPS BEGIN

	::: CYCLE JOB STEPS
	
		:JobSteps
			echo./****** Object:  Step [%step_name%]    Script Date: %T-SQLDATE% %T-SQLTIME% ******/
			echo.EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'%step_name%', 
			echo.		@step_id=%step_id%, 
			echo.		@cmdexec_success_code=%cmdexec_success_code%, 
			echo.		@on_success_action=%on_success_action%, 
			echo.		@on_success_step_id=%on_success_step_id%, 
			echo.		@on_fail_action=%on_fail_action%, 
			echo.		@on_fail_step_id=%on_fail_step_id%, 
			echo.		@retry_attempts=%retry_attempts%, 
			echo.		@retry_interval=%retry_interval%, 
			echo.		@os_run_priority=%os_run_priority%, @subsystem=N'%subsystem%', 
			echo.		@command=N'%command%', 
			echo.		@flags=%flags%
			echo.IF ^(@@ERROR ^<^> 0 OR @ReturnCode ^<^> 0^) GOTO QuitWithRollback
		:JobStepsEnd
		goto :GenerateTSQLFileEnd
	
	::: CYCLE JOB STEPS END

	::: JOB START STEP ID

		:JobStartStep
			echo.EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = %start_step_id%
			echo.IF ^(@@ERROR ^<^> 0 OR @ReturnCode ^<^> 0^) GOTO QuitWithRollback
		:JobStartStepEnd
		goto :GenerateTSQLFileEnd

		set "step_id="
		set "step_name="
		set "subsystem="
		set "command="
		set "flags="
		set "additional_parameters="
		set "cmdexec_success_code="
		set "on_success_action="
		set "on_success_step_id="
		set "on_fail_action="
		set "on_fail_step_id="
		set "server="
		set "database_name="
		set "database_user_name="
		set "retry_attempts="
		set "retry_interval="
		set "os_run_priority="
		set "output_file_name="
		set "proxy_id="
		set "step_uid="

	::: JOB START STEP ID END

	::: JOB STEPS END

	::: CYCLE JOB SCHEDULES

		:JobSchedules
			echo.EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'%name%', 
			echo.		@enabled=%enabled%, 
			echo.		@freq_type=%freq_type%, 
			echo.		@freq_interval=%freq_interval%, 
			echo.		@freq_subday_type=%freq_subday_type%, 
			echo.		@freq_subday_interval=%freq_subday_interval%, 
			echo.		@freq_relative_interval=%freq_relative_interval%, 
			echo.		@freq_recurrence_factor=%freq_recurrence_factor%, 
			echo.		@active_start_date=%active_start_date%, 
			echo.		@active_end_date=%active_end_date%, 
			echo.		@active_start_time=%active_start_time%, 
			echo.		@active_end_time=%active_end_time% 
			echo.	----@schedule_uid=N'%schedule_uid%'
			echo.IF ^(@@ERROR ^<^> 0 OR @ReturnCode ^<^> 0^) GOTO QuitWithRollback
		:JobSchedulesEnd
		goto :GenerateTSQLFileEnd

		::: msdb.dbo.sysjobschedules
			set "schedule_id="
			set "job_id="
			set "next_run_date="
			set "next_run_time="

		::: msdb.dbo.sysschedules
			set "schedule_id="
			set "schedule_uid="
			set "originating_server_id="
			set "name="
			set "owner_sid="
			set "enabled="
			set "freq_type="
			set "freq_interval="
			set "freq_subday_type="
			set "freq_subday_interval="
			set "freq_relative_interval="
			set "freq_recurrence_factor="
			set "active_start_date="
			set "active_end_date="
			set "active_start_time="
			set "active_end_time="
			set "date_created="
			set "date_modified="
			set "version_number="

	::: CYCLE JOB SCHEDULES END

	::: JOB SERVER

		:JobServer
			echo.EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'^(%server_name%^)'
			echo.IF ^(@@ERROR ^<^> 0 OR @ReturnCode ^<^> 0^) GOTO QuitWithRollback
		:JobServerEnd
		goto :GenerateTSQLFileEnd

	::: JOB SERVER END

	::: CYCLE JOB ALERTS

		:JobAlert
			echo./****** Object:  Alert [%name%]    Script Date: %T-SQLDATE% %T-SQLTIME% ******/
			echo.EXEC @ReturnCode = msdb.dbo.sp_add_alert @name=N'%name%', 
			echo.		@message_id=%message_id%, 
			echo.		@severity=%severity%, 
			echo.		@enabled=%enabled%, 
			echo.		@delay_between_responses=%delay_between_responses%, 
			if defined include_event_description (
			echo.		@include_event_description_in=%include_event_description%, 
			)
			if defined notification_message (
			echo.		@notification_message=N'%notification_message%', 
			)
			if defined event_description_keyword (
			echo.		@event_description_keyword=N'%event_description_keyword%', 
			)
			if defined category_name (
			echo.		@category_name=N'%category_name%', 
			)
			if defined database_name (
			echo.		@database_name=N'%database_name%', 
			)
			if defined performance_condition (
			echo.		@performance_condition=N'%performance_condition%', 
			)
			if defined raise_snmp_trap if not "%raise_snmp_trap%" == "0" (
			echo.		@raise_snmp_trap=%raise_snmp_trap%, 
			)
			if defined wmi_namespace (
			echo.		@wmi_namespace=N'%wmi_namespace%', 
			)
			if defined wmi_query (
			echo.		@wmi_query=N'%wmi_query%', 
			)
			echo.		@job_id=@jobId
 			echo.IF ^(@@ERROR ^<^> 0 OR @ReturnCode ^<^> 0^) GOTO QuitWithRollback
		:JobAlertEnd
		goto :GenerateTSQLFileEnd

		set "id="
		set "name="
		set "event_source="
		set "event_category_id="
		set "event_id="
		set "message_id="
		set "severity="
		set "enabled="
		set "delay_between_responses="
		set "last_occurrence_date="
		set "last_occurrence_time="
		set "last_response_date="
		set "last_response_time="
		set "notification_message="
		set "include_event_description="
		set "database_name="
		set "event_description_keyword="
		set "occurrence_count="
		set "count_reset_date="
		set "count_reset_time="
		set "job_id="
		set "has_notification="
		set "flags="
		set "performance_condition="
		set "category_id="

	::: CYCLE JOB ALERTS END

	::: JOB FOOTER

		:JobFooter
			echo.COMMIT TRANSACTION
			echo.GOTO EndSave
			echo.QuitWithRollback:
			echo.    IF ^(@@TRANCOUNT ^> 0^) ROLLBACK TRANSACTION
			echo.EndSave:
			echo.
			echo.GO
			echo.
		:JobFooterEnd
		goto :GenerateTSQLFileEnd
		
	::: JOB FOOTER END

:GenerateTSQLFileEnd
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
	if defined str (
		echo "%str%" | findstr "❦.*❦" >nul
		if errorlevel 0 (
			set "str=!str:❦="!"
		)
	)
	if defined str if /i "%str:"=%" == "NULL" set "str="
	endlocal & set "%2=%str%"
	goto :eof

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:exit
@echo "%PS_TEMP%" | find /i "\%PSRND%" >nul 2>&1 && rd /s /q "%PS_TEMP%" >nul 2>&1
@set "PS_TEMP=%TEMP%"
@pause
@endlocal && exit /b %errlvl%
