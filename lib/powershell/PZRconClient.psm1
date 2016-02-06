$JavaBinary         = ""
$JavaRconClientPath = ""
$ServerRconPort     = 27015
$ServerRconPassword = ""
$ServerIPv4         = "127.0.0.1"

function Set-ServerIP
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$ServerIPv4
    )

    $script:ServerIPv4 = $ServerIPv4
}

function Get-ServerIP
{
    $ServerIPv4
}

function Set-JavaBinary
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$JavaBinary
    )

    $script:JavaBinary = $JavaBinary
}

function Get-JavaBinary
{
    $JavaBinary
}

function Set-ClientPath
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$RconClientPath
    )

    $script:JavaRconClientPath = $RconClientPath
}

function Get-ClientPath
{
    $JavaRconClientPath
}

function Set-Port
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$RconPort
    )

    $script:ServerRconPort = $RconPort
}

function Get-Port
{
    $ServerRconPort
}

function Set-Password
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$RconPassword
    )

    $script:ServerRconPassword = $RconPassword
}

function Send-Command
{
    <#
        .SYNOPSIS

        The synopsis goes here. This can be one line, or many.
        .DESCRIPTION

        The description is usually a longer, more detailed explanation of what the script or function does. Take as many lines as you need.
        .PARAMETER computername

        Here, the dotted keyword is followed by a single parameter name. Don't precede that with a hyphen. The following lines describe the purpose of the parameter:
        .PARAMETER filePath

        Provide a PARAMETER section for each parameter that your script or function accepts.
        .EXAMPLE

        There's no need to number your examples.
        .EXAMPLE
        PowerShell will number them for you when it displays your help text to a user.
    #>
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$ConsoleCommand
    )

    #Write-Host '& '$JavaBinary' -cp "'$JavaRconClientPath'/lib/*;'$JavaRconClientPath'" zombie.rcon.Main -a '$ServerIPv4' -p '$ServerRconPort' -w '$ServerRconPassword' """'$($ConsoleCommand)'"""'
    $response = & $JavaBinary -cp "$JavaRconClientPath/lib/*;$JavaRconClientPath" zombie.rcon.Main -a $ServerIPv4 -p $ServerRconPort -w $ServerRconPassword """$($ConsoleCommand)"""
    #Account for exit conditions:
    #1 "[RCON] Authentication failed."
    #1 "[RCON] Timed out authenticating."
    #0 "[RCON] Finished."
    #0 "[RCON] Timed out executing command."
    #0 "[RCON] (SteamCondenserException message)"
    #1 "[RCON] (SteamCondenserException message)"
    #0 "Unkown command (command) [RCON] Finished"

    #? "[RCON] Cannot resolve -p: -p"

    $result = @{
        "Status" = 0;
        "Response" = "$response"
    }

    #Write-Host $result.Response

    if( $result.Response.Contains( "Unkown command" ) )
    {
        $result.Status = -1
    }
    elseif( $result.Response.Contains( "[RCON] Finished" ) )
    {
        $result.Status = 0
    }
    else
    {
        $result.Status = 1
    }

    $result
}

function Send-ServerMessage
{
    $message = $args.Replace("`"","")
    $result = Send-Command "servermsg $message"
    #"Message sent."

    if( ( $result.Status -eq 0 ) -and ( ! $result.Response.Contains( "Message sent." ) ) )
    {
        $result.Status = 2
    }

    $result
}

function Send-Quit
{
    $result = Send-Command quit

    if( ( $result.Status -eq 0 ) -and ( ! $result.Response.Contains( "Quit" ) ) )
    {
        $result.Status = 2
    }

    $result
}

function Send-SaveWorld
{
    $result = Send-Command save
    #"World saved"

    if( ( $result.Status -eq 0 ) -and ( ! $result.Response.Contains( "World saved" ) ) )
    {
        $result.Status = 2
    }

    $result
}

function Send-ShowOptions
{
    Send-Command showoptions
    #Parse this
}

#Export-ModuleMember ShowOptions