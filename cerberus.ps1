. .\lib\powershell\IniLibrary.ps1
. .\lib\powershell\Utilities.ps1
#Get-Module .\lib\powershell\CerberusClient.psm1 | Remove-Module
Import-Module -Force -Prefix Cerberus .\lib\powershell\CerberusClient.psm1 #-ArgumentList -AsCustomObject
Import-Module -Force -Prefix RCON .\lib\powershell\PZRconClient.psm1

$Cerberus = @{
    Version              = "0.2.0"
    Homepage             = "https://github.com/SurvivorNetwork/Cerberus"
    ConfigFile           = "$(Get-ScriptDirectory)\cerberus.ini"
    Config               = $null
    ServiceResolution    = 10
    WorkshopPollInterval = 120
    WorkshopUpdateTimes  = @{}
    SurvivorNetAPIKey    = $null
    Operations           = New-Object 'System.Collections.Generic.LinkedList[hashtable]'
    Timer                = New-Object System.Diagnostics.Stopwatch
    Alarms               = New-Object System.Collections.ArrayList
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
    WarningIndex     = 0
    WarningIntervals = @(0)
    WarningMessage   = "The server is going down for maintenance {0}"
    SteamPlayerID    = $null

    Status          = $null
    WMIObject       = $null
    Process         = $null
}

function Initialize-Cerberus {
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$options
    )

    $Cerberus.Config = $options[ "Cerberus" ]

    if( $Cerberus.Config.WorkshopPollInterval )
    {
        $Cerberus.WorkshopPollInterval = $Cerberus.Config.WorkshopPollInterval
    }

    if( $Cerberus.Config.ServiceResolution )
    {
        $Cerberus.ServiceResolution = $Cerberus.Config.ServiceResolution
    }

    if( $Cerberus.Config.SurvivorNetAPIKey )
    {
        $Cerberus.SurvivorNetAPIKey = $Cerberus.Config.SurvivorNetAPIKey
    }
}

function Initialize-RCONClient {
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$options,
        [Parameter(Mandatory=$False,Position=2)]
            [hashtable]$defaults
    )

    $options = $options[ "Project Zomboid RCON Client" ]

    if( $options -and ! [string]::IsNullOrWhitespace( $options.Path ) ) {
        Set-RCONClientPath $options.Path
    }
    else {
        Set-RCONClientPath $defaults.Path
    }

    if( $options -and ! [string]::IsNullOrWhitespace( $options.JavaBinary ) ) {
        Set-RCONJavaBinary $options.JavaBinary
    }
    else {
        Set-RCONJavaBinary $defaults.JavaBinary
    }

    if( $options -and ! [string]::IsNullOrWhitespace( $options.Port ) ) {
        Set-RCONPort $options.Port
    }
    else {
        Set-RCONPort $defaults.Port
    }

    if( $options -and ! [string]::IsNullOrWhitespace( $options.Password ) ) {
        Set-RCONPassword $options.Password
    }
    else {
        Set-RCONPassword $defaults.Password
    }

    #Test-RCONConfig
}

function Initialize-PZServer {
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$options
    )

    $options = $options[ "Project Zomboid Server" ]

    $PZServer.ConfigFile       = $options.ConfigFile
    $PZServer.Config           = $( Get-IniContent $PZServer.ConfigFile )[ "No-Section" ]
    $PZServer.Path             = $options.Path
    $PZServer.StartCommand     = $options.StartCommand
    $PZServer.RestartWorkshop  = $options.RestartOnWorkshopUpdates
    $PZServer.RestartDown      = $options.RestartOnDown

    $PZServer.SteamPlayerID    = $PZServer.Config.ServerPlayerID
    $PZServer.WorkshopItems    = $PZServer.Config.WorkshopItems

    $PZServer.AppId            = Get-Content "$($PZServer.Path)\steam_appid.txt"
    $PZServer.SVNRevision      = Get-Content "$($PZServer.Path)\SVNRevision.txt"

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
        {
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
 
#$PZLatestVersionJSON   = (New-Object Net.WebClient).DownloadString( "http://projectzomboid.com/version_announce" )

function Write-ConsoleHeader {
    #Write-Host $PZLatestVersionJSON
    Get-Content "$(Get-ScriptDirectory)\lib\asciiheader.txt"
    Write-Host `r`n"     SurvivorNet Cerberus v$($Cerberus.Version) by Aniketos   -   $($Cerberus.Homepage)"
    Write-Host `r`n"     Project Zomboid Server SVN Revision: $($PZServer.SVNRevision)"
    Write-Host `r`n

    Write-Host "  Active Configuration (from cerberus.ini):"

    if( $PZServer.RestartWorkshop )
    {
        Write-Host "    * Restart Server on Workshop Item Updates"
        Write-Host "    * Tracking Workshop IDs: $($PZServer.WorkshopItems -join ", ")"
    }
    else
    {
        Write-Host "    * Do not restart server on Workshop item updates"
    }

    if( $PZServer.RestartDown )
    {
        Write-Host "    * Restart server if not running"
    }
    else
    {
        Write-Host "    * Do not restart Server if not running"
    }

    Write-Host "    * Service resolution of $($Cerberus.ServiceResolution) seconds"
    Write-Host "    * Shutdown warnings at (ms prior):"
    Write-Host "          $($PZServer.WarningIntervals -join ", ")"
    Write-Host `r`n

    if( $PZServer.Status -eq "up" )
    {
        Write-Log "Project Zomboid server is running. Siccing Cerberus on PID #$( $PZServer.Process.Id )" "Cyan"
    }
}

function Test-Configuration {
    Write-Log "Running pre-flight checks..." "Cyan"
    $status = 0

    # Check for Cerberus Configuration File
    if( ! ( Test-Path $Cerberus.ConfigFile ) )
    {
        Write-Log "FATAL: cerberus.ini not found" "Red"
        Stop-Preflight 1
    }

    # Check for Server Configuration File
    if( ! ( Test-Path $PZServer.ConfigFile ) )
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

function Add-Alarm {
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$Name,
        [Parameter(Mandatory=$True,Position=2)]
            [int]$SecondsDelay,
        [Parameter(Mandatory=$True,Position=3)]
            [string]$Callback,
        [Parameter(Mandatory=$False,Position=4)]
            [int]$Repeat
    )

    if( ! ( Find-Alarm $Name ) )
    {
        if( ! $Repeat )
        {
            $Repeat = 0
        }

        $Cerberus.Alarms.Add( @{
            Name      = $Name
            Delay     = $SecondsDelay * 1000
            Activate  = $Cerberus.Timer.ElapsedMilliseconds + $SecondsDelay * 1000
            Callback  = $Callback
            Repeat    = $Repeat
        } ) | Out-Null

        #Write-Log "DEBUG: Added alarm $Name in $SecondsDelay seconds. Set to repeat $Repeat times" "Yellow"
    }
    else
    {
        Write-Log "Cannot add alarm ${Name}: Alarm already exists." "Yellow"
    }
}

function Remove-Alarm
{
    Param(
        [Parameter(Mandatory=$False)]
            [int]$Index,
        [Parameter(Mandatory=$False)]
            [hashtable]$Alarm,
        [Parameter(Mandatory=$False,Position=1)]
            [string]$Name
    )

    if( $Index -ne $null )
    {
        $Cerberus.Alarms.RemoveAt( $Index ) | Out-Null
    }
    elseif( $Alarm )
    {
        $Cerberus.Alarms.Remove( $Alarm ) | Out-Null
    }
    elseif( $Name )
    {
        $Cerberus.Alarms.Remove( $( Find-Alarm $Name ) ) | Out-Null
    }
}

function Update-Alarms
{
    $now = $Cerberus.Timer.ElapsedMilliseconds

    For( $i = 0; $i -lt $Cerberus.Alarms.Count; $i++ )
    {
        $alarm = $Cerberus.Alarms[ $i ]
        if( $now -gt $alarm.Activate )
        {
            #Write-Log "DEBUG: Alarm '$($alarm.Name)' triggered" "Yellow"

            $ExecutionContext.InvokeCommand.ExpandString( $alarm.Callback.ToString() ) | Out-Null

            if( $alarm.Repeat -eq 0 )
            {
                Remove-Alarm -Index $i
                $i--
            }
            else
            {
                $alarm.Activate = $now + $alarm.Delay

                if( $alarm.Repeat -gt 0 )
                {
                    $alarm.Repeat--
                }
            }
        }
    }
}

function Find-Alarm
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$Name
    )

    For( $i = 0; $i -lt $Cerberus.Alarms.Count; $i++ )
    {
        $alarm = $Cerberus.Alarms[ $i ]

        if( $alarm.Name -eq $Name )
        {
            return $alarm
        }
    }

    $null
}

function Send-ShutdownWarning
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [int]$WarningIndex
    )

    $secondsRemaining = $PZServer.WarningIntervals[ $WarningIndex ] / 1000;

    if( $secondsRemaining -gt 60 )
    {
        $timeString = "in $([math]::floor( $secondsRemaining / 60 )) minutes"
    }
    elseif( $secondsRemaining -lt 60 )
    {
        $timeString = "NOW!"
    }
    else
    {
        $timeString = "in $secondsRemaining seconds"
    }
    
    Write-Log ">RCON Server message: $($PZServer.WarningMessage -f $timeString)" "Blue"
    $res = Send-RCONServerMessage $($PZServer.WarningMessage -f $timeString)

    if( $res.Status -eq 0 )
    {
        #Write-Log "RCON> Server message success." "Blue"
        $PZServer.WarningIndex++
    }
    else
    {
        Write-Log "RCON> Server message FAILED($($res.Status)): `"$($res.Response)`"!" "Red"
        Stop-Operation -2

        #TODO: This is a terribly hacky way to remove the relevant alarms
        For( $i = 0; $i -lt $Cerberus.Alarms.Count; $i++ )
        {
            $alarm = $Cerberus.Alarms[ $i ]

            if( $alarm.Name.Contains( "ShutdownWarning" ) )
            {
                Remove-Alarm -Index $i
                $i--
            }
        }
    }
}

function Start-WarningSequence
{
    Reset-WarningSequence
    $warningDuration = $PZServer.WarningIntervals[ 0 ] / 1000

    # Schedule warning messages
    For( $i = 1; $i -lt $PZServer.WarningIntervals.Length; $i++ )
    {
        Add-Alarm "ShutdownWarning-$i" $($warningDuration - ( $PZServer.WarningIntervals[ $i ] / 1000 )) "`$(Send-ShutdownWarning $i)"
    }

    Send-ShutdownWarning 0
}

function Test-WarningSequenceComplete
{
    $PZServer.WarningIndex -eq $PZServer.WarningIntervals.Length
}

function Reset-WarningSequence
{
    $PZServer.WarningIndex = 0
}

function New-Operation
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$Callback,
        [Parameter(Mandatory=$True,Position=2)]
            [string]$TestComplete,
        [Parameter(Mandatory=$False,Position=3)]
            [string]$StartMessage,
        [Parameter(Mandatory=$False,Position=4)]
            [string]$CompleteMessage,
        [Parameter(Mandatory=$False,Position=5)]
            [string]$Color
    )

    $Operation = @{
        Started         = $False
        Callback        = $Callback
        Complete        = $TestComplete
        StartMessage    = "Starting '$Callback' Operation..."
        CompleteMessage = "'$Callback' Operation Complete."
        Color           = "Yellow"
    }

    if( $StartMessage )
    {
        $Operation.StartMessage = $StartMessage
    }

    if( $CompleteMessage )
    {
        $Operation.CompleteMessage = $CompleteMessage
    }

    if( $Color )
    {
        $Operation.Color = $Color
    }

    $Operation
}

#Add an operation to the END of the queue
function Add-Operation
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$Operation
    )

    $Cerberus.Operations.AddLast( $Operation ) | Out-Null
}

#Add an operation to the FRONT of the queue to be activated immediately
function Push-Operation
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$Operation
    )

    $Cerberus.Operations.AddFirst( $Operation ) | Out-Null
}

function Get-ActiveOperation
{
    $Operation = $Cerberus.Operations.First

    if( ! $Operation )
    {
        #@{
        #    Callback = "Idle"
        #    Started = $True
        #    Complete = '$False'
        #}
        $null
    }
    else
    {
        $Operation.Value
    }
}

function Start-Operation
{   
    Param(
        [Parameter(Mandatory=$False,Position=1)]
            [hashtable]$Operation
    )

    if( ! $Operation )
    {
        $Operation = Get-ActiveOperation
    }

    if( $Operation -and ( $( Test-OperationStarted $Operation ) -eq $False ) )
    {
        Write-Log $Operation.StartMessage $Operation.Color
        $Operation.Started = $True
        & $Operation.Callback
    }
}

function Stop-Operation
{
    Param(
        [Parameter(Mandatory=$False,Position=1)]
            [int]$ExitCode
    )

    if( ! $ExitCode )
    {
        $ExitCode = 0
    }

    $Operation = Get-ActiveOperation
    $Cerberus.Operations.RemoveFirst()

    if( $ExitCode -eq 0 )
    {
        Write-Log $Operation.CompleteMessage $Operation.Color
    }
    elseif( $ExitCode -lt 0 )
    {
        Write-Log "'$($Operation.Callback)' Operation ABORTED!" "Red"

        #TODO: Better cascading error response for Operations
        if( $ExitCode -lt -1 )
        {
            Stop-Operation $($ExitCode + 1)
        }
    }
    else
    {
        Write-Log "'$($Operation.Callback)' operation exited with code $ExitCode" "Red"
    }
}

function Reset-Operation
{
    Param(
        [Parameter(Mandatory=$False,Position=1)]
            [hashtable]$Operation
    )

    if( ! $Operation )
    {
        $Operation = Get-ActiveOperation
    }

    if( $Operation )
    {
        $Operation.Started = $False
    }
}

function Update-ActiveOperation
{
    $Operation = Get-ActiveOperation
    if( Test-OperationStarted $Operation ) {
        if( Test-OperationComplete $Operation )
        {
            Stop-Operation 0
            Start-Operation
        }
    }
    else
    {
        Start-Operation
    }
}

function Test-OperationComplete
{
    Param(
        [Parameter(Mandatory=$False,Position=1)]
            [hashtable]$Operation
    )

    if( ! $Operation )
    {
        $Operation = Get-ActiveOperation
    }

    if( $Operation )
    {
        $result = $ExecutionContext.InvokeCommand.ExpandString( $Operation.Complete )
        #Write-Log "DEBUG: Testing '$($Operation.Callback)' Operation Complete ($($Operation.Complete)): $($result -eq $True)"
        $result -eq $True
    }
    else
    {
        $False
    }
}

function Test-OperationStarted
{
    Param(
        [Parameter(Mandatory=$False,Position=1)]
            [hashtable]$Operation
    )

    if( ! $Operation )
    {
        $Operation = Get-ActiveOperation
    }

    if( $Operation )
    {
        $Operation.Started -eq $True
    }
    else
    {
        $False
    }
}

function Test-OperationIs
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [hashtable]$Operation
    )

    $Operation -eq $( Get-ActiveOperation )
}

function Stop-Server
{
    if( Test-ServerIs "up" )
    {
        if( ! ( Test-WarningSequenceComplete ) )
        {
            Reset-Operation
            Push-Operation $(New-Operation 'Start-WarningSequence' '$(Test-WarningSequenceComplete)' 'Shutdown warning sequence initiated...' 'Shutdown warning sequence complete.')
        }
        else
        {
            Reset-WarningSequence
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
                    Stop-Operation -1
                }
            }
            else
            {
                Write-Log "RCON> Map data save FAILED($($res.Status)): `"$($res.Response)`"!" "Red"
                Stop-Operation -1
            }
        }
    }
    else
    {
        Write-Log "Cannot stop server: server not running" "Yellow"
    }
}

function Start-Server
{
    if( Test-ServerIs "down" )
    {
        #Write-Log "Starting server..." "Cyan"

        if( $PZServer.StartArgs.Length -gt 0 )
        {
            Start-Process -WorkingDirectory $PZServer.Path -FilePath $PZServer.Executable -ArgumentList $PZServer.StartArgs
        }
        else
        {
            Start-Process -WorkingDirectory $PZServer.Path -FilePath $PZServer.Executable
        }
    }
    else
    {
        Write-Log "Cannot start server: server is already running" "Yellow"
    }
}

function Restart-Server
{
    Add-Operation $(New-Operation 'Stop-Server' '$(Test-ServerIs "down")' 'Stopping server...' 'Server stopped.')
    Add-Operation $(New-Operation 'Start-Server' '$(Test-ServerIs "up")' 'Starting server...' 'Server started.')
}

function Start-WorkshopWatchdog
{
    Add-Alarm "PollWorkshopUpdates" $Cerberus.WorkshopPollInterval '$(Update-WorkshopStatus)' -1
    $Cerberus.WorkshopUpdateTimes = Get-CerberusWorkshopUpdateTimes $PZServer.WorkshopItems
}

function Stop-WorkshopWatchdog
{
    Remove-Alarm "PollWorkshopUpdates"
    Write-Log "Workshop Watchdog stopped." "Cyan"
}

function Update-WorkshopStatus
{
    $updateTimes = Get-CerberusWorkshopUpdateTimes $PZServer.WorkshopItems

    foreach( $workshopID in $PZServer.WorkshopItems )
    {
        if( $updateTimes[ $workshopID ] -gt $Cerberus.WorkshopUpdateTimes[ $workshopID ] )
        {
            Write-Log "Workshop item #$workshopID has been updated!" "Yellow"
            Stop-WorkshopWatchdog
            Restart-Server
            Add-Operation $(New-Operation 'Start-WorkshopWatchdog' '$($(Find-Alarm "PollWorkshopUpdates") -ne $null)' 'Restarting Workshop Watchdog...' 'Workshop Watchdog unleashed!' 'Cyan')
        }
    }
}

function Get-ServerStatus
{
    $PZServer.Status
}

function Update-ServerStatus
{
    if( ( $PZServer.Status -eq "down" ) -or ( $PZServer.Status -eq $null ) )
    {
        $PZServer.WMIObject = $null
        $PZServer.Process   = $null

        Find-ServerProcess
    }

    if( $PZServer.Process -ne $null )
    {
        $PZServer.Process.Refresh()

        if( $PZServer.Process.HasExited )
        {
            $PZServer.Status = "down"
        }
        else
        {
            $PZServer.Status = "up"
        }
    }
    else
    {
        $PZServer.Status = "down"
    }
}

function Test-ServerIs
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$Status
    )

    $Status -eq $( Get-ServerStatus )
}

function Find-ServerWMIObject
{
    Get-WmiObject Win32_Process | Where-Object { $_.ExecutablePath -match "$([regex]::escape($PZServer.Path))" }
}

function Get-ServerWMIObject
{
    if( $PZServer.WMIObject -eq $null )
    {
        $PZServer.WMIObject = Find-ServerWMIObject
    }

    $PZServer.WMIObject
}

function Find-ServerProcess
{
    $WMIObject = Get-ServerWMIObject

    if( $WMIObject -ne $null )
    {
        $PZServer.Process = Get-Process -id $WMIObject.ProcessId
    }

    $null
}

function Get-ServerProcess
{
    if( $PZServer.Process -eq $null )
    {
        $PZServer.Process = Find-ServerProcess
    }

    $PZServer.Process
}

# Main Controller Body
try
{
    $configuration = Get-IniContent $Cerberus.ConfigFile

    # Initialization routines
    Initialize-Cerberus $configuration # Initialize Cerberus controller
    Initialize-PZServer $configuration # Initialize PZServer process interface
    Initialize-RCONClient $configuration @{ # Initialize RCON communication
        Path       = "$($PZServer.Path)\rcon"
        JavaBinary = "$($PZServer.Path)\jre\bin\java.exe"
        Port       = $PZServer.Config.RCONPort
        Password   = $PZServer.Config.RCONPassword
        IP         = "127.0.0.1"
    }

    # Startup routines
    Write-ConsoleHeader # Print an informational header
    Test-Configuration  # Run preflights to make sure Cerberus doesn't blow up for obvious reasons

    #  - Autostart server
    if( Test-ServerIs "down" )
    {
        Add-Operation $(New-Operation 'Start-Server' '$(Test-ServerIs "up")' 'Starting server...' 'Server started.')
    }

    #  - Start WorkshopItem watchdog
    if( $PZServer.RestartWorkshop )
    {
        Add-Operation $(New-Operation 'Start-WorkshopWatchdog' '$($(Find-Alarm "PollWorkshopUpdates") -ne $null)' 'Sarting Workshop Watchdog...' 'Workshop Watchdog unleashed!' 'Cyan')
    }

    #  - Start the Cerberus clock
    $Cerberus.Timer.Start()

    #DEBUG restart alarm
    #Add-Alarm 'Debug-TestRestart' 5 '$(Restart-Server)'
    #Add-Alarm 'DebugTestWorkshopUpdate' 10 '$($Cerberus.WorkshopUpdateTimes["498441420"] = 0)'

    # Main Service Loop
    while( $true )
    {
        #$op = Get-ActiveOperation
        #if( ! $op )
        #{
        #    Write-Log "DEBUG: Idle Operation Cycle @$($Cerberus.Timer.ElapsedMilliseconds)" "Yellow"
        #}
        #else
        #{
        #    Write-Log "DEBUG: $($op.Callback) Operation Cycle @$($Cerberus.Timer.ElapsedMilliseconds)" "Yellow"
        #}

        Update-ServerStatus    #Update server status based on Server Process
        Update-ActiveOperation #Update the Operation stack (Cerberus' "state")
        Update-Alarms          #Process time-based functionality

        if( Test-ServerIs "down" )
        {
            $Operation = Get-ActiveOperation

            if( $Operation -eq $null )
            {
                Write-Log "The server stopped unexpectedly" "Red"

                if( $PZServer.RestartDown )
                {
                    Add-Operation $(New-Operation 'Start-Server' '$(Test-ServerIs "up")' 'Starting server...' 'Server started.')
                }
            }
            else
            {
                Switch( $Operation.Callback )
                {
                    "Start-WarningSequence" {
                        Write-Log "The server stopped unexpectedly" "Red"
                        Stop-Operation -2
                        #TODO: Need to determine if we're in a restart sequence
                    }
                }
            }
        }

        Start-Sleep -s $Cerberus.ServiceResolution #Wait ServiceResolution seconds before performing the next iteration
    }
}
finally
{
    Write-Log "Cerberus Re-leashed ='(" "Cyan"

    Remove-Module CerberusClient
    Remove-Module PZRconClient

    Write-Log "Cerberus communication modules detached from PowerShell environment." "Cyan"
}