. .\lib\powershell\IniLibrary.ps1
. .\lib\powershell\Utilities.ps1
#Get-Module .\lib\powershell\CerberusClient.psm1 | Remove-Module
Import-Module -Force -Prefix Cerberus .\lib\powershell\CerberusClient.psm1 #-ArgumentList -AsCustomObject
Import-Module -Force -Prefix RCON .\lib\powershell\PZRconClient.psm1

$Cerberus = @{
    Version              = "0.2.0"
    Homepage             = "http://tools.survivor.network/cerberus"
    ConfigFile           = "$(Get-ScriptDirectory)\cerberus.ini"
    Config               = $null
    ServiceResolution    = 10
    WorkshopPollInterval = 12000
    SurvivorNetAPIKey    = $null
}

$PZServer = @{
    SurvivorNetID    = $null
    ConfigFile       = $null
    Config           = $null
    SVNRevision      = $null
    AppId            = $null
    Path             = $null
    StartCommand     = $null
    Executable       = $null
    StartArgs        = @()
    RestartWorkshop  = $False
    RestartDown      = $False
    RestartInterval  = $False
    WarningIntervals = @(0)
    WarningMessage   = "The server is going down for maintenance {0}"
    SteamPlayerID    = $null

    Operation       = "idle"
    RestartQueued   = $False
    Status          = $null
    WMIObject       = $null
    Process         = $null
}



function Initialize-CerberusConfig {
    $configuration   = Get-IniContent $Cerberus.ConfigFile

    $Cerberus.Config = $configuration[ "Cerberus" ]

    if( $Cerberus.Config.WorkshopPollInterval )
        $Cerberus.WorkshopPollInterval = $Cerberus.Config.WorkshopPollInterval

    if( $Cerberus.Config.ServiceResolution )
        $Cerberus.ServiceResolution = $Cerberus.Config.ServiceResolution

    if( $Cerberus.Config.SurvivorNetAPIKey )
        $Cerberus.SurvivorNetAPIKey = $Cerberus.Config.SurvivorNetAPIKey

    Initialize-PZServer $configuration[ "Project Zomboid Server" ]
    Initialize-RCONClient $configuration[ "Project Zomboid RCON Client" ] @{
        Path       = "$($PZServer.Path)\rcon"
        JavaBinary = "$($PZServer.Path)\jre\bin\java.exe"
        Port       = $PZServer.Config.RCONPort
        Password   = $PZServer.Config.Password
        IP         = "127.0.0.1"
    }
}

function Initialize-RCONClient {
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$options,
        [Parameter(Mandatory=$False,Position=2)]
            [hashtable]$defaults
    )

    if( [string]::IsNullOrWhitespace( $options.Path ) ) {
        Set-RCONClientPath $defaults.Path
    }
    else {
        Set-RCONClientPath $options.Path
    }

    if( [string]::IsNullOrWhitespace( $options.JavaBinary ) ) {
        Set-RCONClientPath $defaults.JavaBinary
    }
    else {
        Set-RCONClientPath $options.JavaBinay
    }

    if( [string]::IsNullOrWhitespace( $options.Port ) ) {
        Set-RCONClientPath $defaults.Port
    }
    else {
        Set-RCONClientPath $options.Port
    }

    if( [string]::IsNullOrWhitespace( $options.Password ) ) {
        Set-RCONClientPath $defaults.Password
    }
    else {
        Set-RCONClientPath $options.Password
    }

    #Test-RCONConfig
}

function Initialize-PZServer {
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$options
    )

    $PZServer.ConfigFile       = $options.ConfigFile
    $PZServer.Config           = $( Get-IniContent $PZServer.ConfigFile )[ "No-Section" ]
    $PZServer.Path             = $options.Path
    $PZServer.StartCommand     = $options.StartCommand
    $PZServer.RestartWorkshop  = $options.RestartOnWorkshopUpdates
    $PZServer.RestartDown      = $options.RestartOnDown

    $PZServer.SteamPlayerID    = $PZServer.Config.ServerPlayerID
    $PZServer.WorkshopItems    = $PZServer.Config.WorkshopItems

    $PZServer.AppId            = Get-Content $PZServer.Path\steam_appid.txt
    $PZServer.SVNRevision      = Get-Content $PZServer.Path\SVNRevision.txt

    # Start command Pre-Processing
    $startArgs = $PZServer.StartCommand.split( " " )
    $PZServer.Executable       = $startArgs[0]
    if( $startArgs.Length > 1 )
    {
        $PZServer.StartArgs    = $startArgs[ 1..$startArgs.Length ]
    }

    # Warning message
    if( ! [string]::IsNullOrWhitespace( $options.WarningMessage ) )
    {
        $PZServer.WarningMessage = $options.WarningMessage

        if( ! [string]::IsNullOrWhitespace( $options.WarningIntervals ) )
            # Convert comma-delimited string of seconds to integer array of milliseconds
            $PZServer.WarningIntervals = $options.WarningIntervals.Split(",")

            For( $i = 0; $i -lt $PZServer.WarningIntervals.Length; $i++ )
            {
                [int]$PZServer.WarningIntervals[ $i ] = [convert]::ToInt32( $PZServer.WarningIntervals[ $i ], 10 ) * 1000
            }
        }
    }

    # Workshop Item update tracking
    if( $PZServer.RestartWorkshop )
    {
        if( [string]::IsNullOrWhitespace( $PZServer.WorkshopItems ) )
        {
            $PZServer.WorkshopItems = @()
        }
        else
        {
            $PZServer.WorkshopItems = $PZServer.WorkshopItems.Split(",")
        }
    }

    # Restart at interval
    if( ! [string]::IsNullOrWhitespace( $options.RestartInterval ) )
    {
        $PZServer.RestartInterval = [convert]::ToInt32( $options.RestartOnInterval ) * 1000
    }
    else
    {
        $PZServer.RestartInterval = $False
    }

    Update-ServerStatus
}

$CerberusVersion       = 0.1
$CerberusURL           = "http://zeekshaven.net"
$CerberusConfigFile    = "$(Get-ScriptDirectory)\cerberus.ini"
$CycleInterval         = 10
 
#$PZLatestVersionJSON   = (New-Object Net.WebClient).DownloadString( "http://projectzomboid.com/version_announce" )
 
$CerberusConfig        = Get-IniContent $CerberusConfigFile
$ServerConfigFile      = $CerberusConfig[ "Project Zomboid Server" ][ "ConfigFile" ]
$ServerStartCommand    = $CerberusConfig[ "Project Zomboid Server" ][ "StartCommand" ]
$CerberusPollWorkshop  = $CerberusConfig[ "Project Zomboid Server" ][ "RestartOnWorkshopUpdates" ]
$RestartOnCrash        = $CerberusConfig[ "Project Zomboid Server" ][ "RestartOnCrash" ]
$CerberusPollInterval  = $CerberusConfig[ "Cerberus" ][ "WorkshopPollInterval" ]
$ServerWarningInterval = $CerberusConfig[ "Project Zomboid Server" ][ "ShutdownWarningInterval" ]
$ServerWarning         = $CerberusConfig[ "Project Zomboid Server" ][ "ShutdownWarning" ]

$ServerConfig          = Get-IniContent $ServerConfigFile
$ServerPath            = $CerberusConfig[ "Project Zomboid Server" ][ "Path" ]
$ServerPlayerId        = $ServerConfig[ "No-Section" ][ "ServerPlayerID" ]
$ServerAppId           = Get-Content $ServerPath\steam_appid.txt
$ServerSvnRevision     = Get-Content $ServerPath\SVNRevision.txt
$ServerWorkshopItems   = $ServerConfig[ "No-Section" ][ "WorkshopItems" ]

$ServerExecutable = $null
$ServerStartArgs = @()
$ShutdownWarningIndex = $ServerWarningInterval.Length
$ShutdownTimer = $null
$ServerWMIObject = $null
$ServerProcess = $null
$ServerStatus = $null
$Operation = "idle"
$Restart = $False

function Initialize-Cerberus {
    #Controller Initialization
    #  - Steam Workshop Item IDs
    if( [string]::IsNullOrWhitespace( $ServerWorkshopItems ) )
    {
        $script:ServerWorkshopItems = @()
    }
    else
    {
        $script:ServerWorkshopItems = $ServerWorkshopItems.Split(",")
    }

    #  - Shutdown Warning Intervals
    if( [string]::IsNullOrWhitespace( $ServerWarningInterval ) )
    {
        $script:ServerWarningInterval = @(0)
    }
    else
    {
        $script:ServerWarningInterval = $ServerWarningInterval.Split(",")

        For( $i = 0; $i -lt $ServerWarningInterval.Length; $i++ )
        {
            [int]$script:ServerWarningInterval[ $i ] = [convert]::ToInt32( $ServerWarningInterval[ $i ], 10 ) * 1000
        }
    }

    #  - Server Start Command Pre-Processing
    $startArgs = $ServerStartCommand.split( " " )
    $script:ServerExecutable = $startArgs[0]
    if( $startArgs.Length > 1 )
    {
        $script:ServerStartArgs = $startArgs[ 1..$startArgs.Length ]
    }

    #  - Get Current Server Status
    Update-ServerStatus

    #Cerberus Web-Client Initialization
    
    #PZ RCON-Client Initialization
    Set-RCONJavaBinary "$ServerPath\jre\bin\java.exe"
    Set-RCONClientPath "$ServerPath\rcon"
    Set-RCONPort $ServerConfig[ "No-Section" ][ "RCONPort" ]
    Set-RCONPassword $ServerConfig[ "No-Section" ][ "RCONPassword" ]
}  

function Write-ConsoleHeader {
    #Write-Host $PZLatestVersionJSON
    Get-Content "$(Get-ScriptDirectory)\lib\asciiheader.txt"
    Write-Host `r`n"     SurvivorNet Cerberus v$CerberusVersion by Aniketos   -   $CerberusURL"
    Write-Host `r`n"     Project Zomboid server App ID: $ServerAppId   -   SVN Revision: $ServerSvnRevision"
    Write-Host `r`n

    Write-Host "  Active Configuration (from cerberus.ini):"

    if( $CerberusPollWorkshop )
    {
        Write-Host "    * Restart Server on Workshop Item Updates"
        Write-Host "    * Tracking Workshop IDs: $($ServerWorkshopItems -join ", ")"
    }
    else
    {
        Write-Host "    * Do not restart server on Workshop item updates"
    }

    if( $RestartOnCrash )
    {
        Write-Host "    * Restart server if not running"
    }
    else
    {
        Write-Host "    * Do not restart Server if not running"
    }

    Write-Host "    * Service resolution of $CycleInterval seconds"
    Write-Host "    * Shutdown warnings at (ms prior):"
    Write-Host "          $($ServerWarningInterval -join ", ")"

    #For( $i = 0; $i -lt $ServerWarningInterval.Length; $i++ )
    #{
    #    Write-Host "        $($i): $($ServerWarningInterval[ $i ] / 1000)"
    #}

    Write-Host `r`n

    if( $ServerStatus -eq "up" )
    {
        Write-Log "Project Zomboid server is running. Siccing Cerberus on process #$( $ServerProcess.Id )" "Cyan"
    }
}

function Test-Configuration {
    Write-Log "Running pre-flight checks..." "Cyan"
    $status = 0

    # Check for Cerberus Configuration File
    if( ! ( Test-Path $CerberusConfigFile ) )
    {
        Write-Log "FATAL: cerberus.ini not found" "Red"
        Stop-Preflight 1
    }

    # Check for Server Configuration File
    if( ! ( Test-Path $ServerConfigFile ) )
    {
        Write-Log "FATAL: servertest.ini not found" "Red"
        Stop-Preflight 2
    }

    # Check for Java Binary
    if( ! ( Get-RCONJavaBinary | Test-Path ) )
    {
        Write-Log "FATAL: No Java binary at $( Get-RCONJavaBinary )" "Red"
        Stop-Preflight 3
    }

    # Check for PZ RCON client .class
    if( ! ( Get-RCONClientPath | Test-Path ) )
    {
        Write-Log "FATAL: The PZ RCON Client is not at $( Get-RCONClientPath )" "Red"
        Stop-Preflight 4
    }

    # RCON Server Test
    $rconRes = Send-RCONCommand "showoptions"

    if( $rconRes.Contains( "Connection refused" ) )
    {
        Write-Log "WARNING: The RCON client cannot connect to your game server. This may indicate a problem if your server is running." "Yellow"
    }
    elseif( $rconRes.Contains( "Cannot resolve -p" ) )
    {
        Write-Log "FATAL: The RCON client cannot resolve configured port '$(Get-RCONPort)'" "Red"
        Stop-Preflight 5
    }
    elseif( $rconRes.Contains( "null" ) )
    {
        Write-Log "FATAL: The RCON client produced a 'null' response. Configured RCON server IP '$(Get-RCONServerIp)' may be incorrect. If the game-server is running on the same machine as Cerberus, use 127.0.0.1"
        Stop-Preflight 6
    }
    elseif( $rconRes.Contains( "Authentication failed" ) )
    {
        Write-Log "FATAL: RCON Authentication failed. Make sure '$ServerConfigFile' sets a valid RCON Password" "Red"
        Stop-Preflight 7
    }

    Stop-Preflight $status
}

function Stop-Preflight {
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [int]$statusCode
    )

    if( $statusCode -eq 0 )
    {
        Write-Log "PASSED pre-flight: Let slip the hounds of UPTIME!!" "Green"
    }
    else
    {
        Write-Log "FAILED pre-flight ($statusCode): Check your Cerberus configuration" "Red"
        exit
    }
}

function Write-Log ($string, $color) {
    if ($color -eq $null) { $color = "White" }
    if (Test-Path ".\logs") {} else { new-item ".\logs" -type directory | out-null }
    Write-Host "  [$(Get-Date -Format 'hh:mm:ss')] $string" -Foreground $color
    "[$(get-date -Format 'hh:mm, dd/MM')] $($string)" | Out-File .\logs\$(Get-Date -Format dd-MM-yyyy).log -Append -Encoding ASCII 
}

function Send-ShutdownWarning
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [int]$millisecondsRemaining
    )

    $secondsRemaining = $millisecondsRemaining / 1000;

    if( $secondsRemaining -gt 60 )
    {
        $timeString = "in $($secondsRemaining / 60) minutes"
    }
    elseif( $secondsRemaining -le 10 )
    {
        $timeString = "NOW!"
    }
    else
    {
        $timeString = "in $secondsRemaining seconds"
    }
    
    Write-Log ">RCON Server message: $($ServerWarning -f $timeString)" "Blue"
    $res = Send-RCONServerMessage $($ServerWarning -f $timeString)

    if( $res.Status -eq 0 )
    {
        #Write-Log "RCON> Server message success." "Blue"
    }
    else
    {
        Write-Log "RCON> Server message FAILED($($res.Status)): `"$($res.Response)`"!" "Red"
        Write-Log "Aborting $Operation operation!" "Red"

        $script:Operation = "idle"
    }
}

function Start-WarningSequence
{
    Write-Log "Server shutdown warning sequence initiated." "Cyan"
    Send-ShutdownWarning $ServerWarningInterval[ 0 ]
    $script:ShutdownWarningIndex = 1

    if( $ShutdownTimer -eq $null )
    {
        $script:ShutdownTimer = [System.Diagnostics.Stopwatch]::StartNew()
    }
    else
    {
        $ShutdownTimer.Restart();
    }
}

function Stop-Server
{
    if( $ServerStatus -eq "up" )
    {
        if( $Operation -eq "idle" )
        {
            $script:Operation = "server-stop"

            Write-Log "Server shutdown commencing." "Cyan"
            Write-Log ">RCON Saving map data..." "Blue"
            $res = Send-RCONSaveWorld

            if( $res.Status -eq 0 )
            {
                Write-Log "RCON> Map data saved succesfully." "Blue"
                Write-Log ">RCON 'Quit' server..." "Blue"
                
                $res = Send-RCONQuit

                if( $res.Status -eq 0 )
                {
                    Write-Log "RCON> Server 'Quit' successful." "Blue"
                }
                else
                {
                    Write-Log "RCON> Server 'Quit' FAILED($($res.Status)): `"$($res.Response)`"!" "Red"
                    Write-Log "Aborting $Operation operation!" "Red"

                    $script:Operation = "idle"
                }
            }
            else
            {
                Write-Log "RCON> Map data save FAILED($($res.Status)): `"$($res.Response)`"!" "Red"
                Write-Log "Aborting $Operation operation!" "Red"

                $script:Operation = "idle"
            }
        }
        else
        {
            Write-Log "Cannot stop server: Operation in progress ($Operation)" "Yellow"
        }
    }
    else
    {
        Write-Log "Cannot stop server: server is not running" "Yellow"
    }
}

function Start-Server
{
    if( $ServerStatus -eq "down" )
    {
        if( $Operation -eq "idle" )
        {
            $script:Operation = "server-start"

            Write-Log "Starting server..." "Cyan"

            if( $ServerStartArgs.Length -gt 0 )
            {
                Start-Process -WorkingDirectory $ServerPath -FilePath $ServerExecutable -ArgumentList $ServerStartArgs
            }
            else
            {
                Start-Process -WorkingDirectory $ServerPath -FilePath $ServerExecutable
            }
        }
        else
        {
            Write-Log "Cannot start server: Operation in progress ($Operation)" "Yellow"
        }
    }
    else
    {
        Write-Log "Cannot start server: server is already running" "Yellow"
    }
}

function Restart-Server
{
    Param(
        [Parameter(Mandatory=$False,Position=1)]
            [switch]$WarningSequence
    )

    if( $Operation -eq "idle" )
    {
        $script:Restart = $True

        if( Get-ServerStatus -eq "up" )
        {
            if( $WarningSequence )
            {
                $script:Operation = "restart-warning"

                Start-WarningSequence
            }
            else
            {
                Stop-Server
            }
        }
        else
        {
            Start-Server
        }
    }
    else
    {
        Write-Log "Cannot restart server: Operation in progress ($Operation)" "Yellow"
    }
}

function Get-ServerStatus
{
    $ServerStatus
}

function Update-ServerStatus
{
    if( ( $ServerStatus -eq "down" ) -or ( $ServerStatus -eq $null ) )
    {
        $script:ServerWMIObject = $null
        $script:ServerProcess = $null

        Find-ServerProcess
    }

    if( ! ( $ServerProcess -eq $null ) )
    {
        $ServerProcess.Refresh()

        if( $ServerProcess.HasExited )
        {
            $script:ServerStatus = "down"
        }
        else
        {
            $script:ServerStatus = "up"
        }
    }
    else
    {
        $script:ServerStatus = "down"
    }
}

function Find-ServerWMIObject
{
    Get-WmiObject Win32_Process | Where-Object { $_.ExecutablePath -match "$([regex]::escape($ServerPath))" }
}

function Get-ServerWMIObject
{
    if( $ServerWMIObject -eq $null )
    {
        $script:ServerWMIObject = Find-ServerWMIObject
    }

    $ServerWMIObject
}

function Find-ServerProcess
{
    $WMIObject = Get-ServerWMIObject

    if( ! ( $WMIObject -eq $null ) )
    {
        $script:ServerProcess = Get-Process -id $WMIObject.ProcessId
    }

    $null
}

function Get-ServerProcess
{
    if( $ServerProcess -eq $null )
    {
        $script:ServerProcess = Find-ServerProcess
    }

    $ServerProcess
}

try
{
    Initialize-Cerberus # Initialize Cerberus environment & communication utilities
    Write-ConsoleHeader # Print an informational header
    Test-Configuration  # Run preflights to make sure Cerberus doesn't blow up for obvious reasons

    if( $ServerStatus -eq "down" )
    {
        Start-Server
    }

    # Main Service Loop
    while( $true )
    {
        Update-ServerStatus

        switch( $Operation )
        {
            "idle" {
                # Restart on down
                if( ( $ServerStatus -eq "down" ) -and $RestartOnCrash )
                {
                    Write-Log "Server stopped unexpectedly." "Yellow"
                    Start-Server
                }

                # Workshop Updates
                if( $CerberusPollWorkshop )
                {
                    if( !$workshopPollTimer )
                    {
                        $workshopPollTimer = [System.Diagnostics.Stopwatch]::StartNew()
                        $workshopItemUpdates = Get-CerberusWorkshopUpdateTimes $ServerWorkshopItems
                        Write-Log "Workshop watchdog set loose." "Cyan"
                    }

                    if( $workshopPollTimer.ElapsedMilliseconds -gt $CerberusPollInterval )
                    {
                        #Write-Log "Polling for workshop updates."
                        $updateTimes = Get-CerberusWorkshopUpdateTimes $ServerWorkshopItems

                        foreach( $workshopID in $ServerWorkshopItems )
                        {
                            if( $updateTimes[ $workshopID ] -gt $workshopItemUpdates[ $workshopID ] )
                            {
                                Write-Log "Workshop item #$workshopID has been updated!" "Yellow"
                                $FakeUpdateTimer.Reset()

                                Restart-Server -WarningSequence
                            }
                        }

                        $workshopPollTimer.Restart()
                    }
                }
            }

            "server-start" {
                if( $ServerStatus -eq "up" )
                {
                    Write-Log "Server started." "Cyan"

                    $script:Restart = $False
                    $script:Operation = "idle"
                }
            }

            "server-stop" {
                if( $ServerStatus -eq "down" )
                {
                    Write-Log "Server stopped." "Cyan"
                    $script:Operation = "idle"

                    if( $Restart )
                    {
                        Start-Server
                    }
                }
            }

            "restart-warning" {
                # Shutdown Sequence
                if( $ShutdownWarningIndex -lt $ServerWarningInterval.Length )
                {
                    if( $ServerWarningInterval[0] - $ShutdownTimer.ElapsedMilliseconds -lt $($ServerWarningInterval[ $ShutdownWarningIndex ]) )
                    {
                        Send-ShutdownWarning $ServerWarningInterval[ $script:ShutdownWarningIndex++ ]
                    }
                }
                else
                {
                    $script:Operation = "idle"

                    Restart-Server
                }
            }
        }

        Start-Sleep -s $CycleInterval
    }
}
finally
{
    Write-Log "Cerberus Re-leashed ='(" "Cyan"

    Remove-Module CerberusClient
    Remove-Module PZRconClient

    Write-Log "Cerberus client modules detached from PowerShell environment." "Cyan"
}