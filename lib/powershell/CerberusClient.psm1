Add-Type -AssemblyName System.Web

$PZServerIP               = 127.0.0.1
$PZServerRconPort         = 27015
$PZServerRconPassword     = ""
$PZServerRoot             = ""
$PZRconClientRoot         = ""
$PZServerConfigFile       = ""
$PZServerCerberusID       = ""
$PZServerWorkshopIDs      = @()
$PZServerWorkshopUpdates  = @{}

$CerberusAPIKey           = ""
$CerberusVersion          = 0.1
$CerberusServer           = "cerberus.survivor.network:8080/api"
$CerberusQueryInterval    = 120000

$PSVersion = 1.0
if( $PSVersionTable.PSVersion ) {
    $PSVersion = $PSVersionTable.PSVersion
}

$UserAgent = "CerberusShell/$CerberusVersion WindowsPowerShell/$PSVersion"

function Get-WorkshopUpdateTimes
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [int[]]$ids
    )

    Invoke-WebAPI 'WorkshopUpdateTimes' @{
        ids = $ids
    }
}

function Invoke-WebAPI
{
    Param(
        [Parameter(Mandatory=$True,Position=1)]
            [string]$Endpoint,

        [Parameter(Mandatory=$False,Position=2)]
            [hashtable]$Data,

        [Parameter(Mandatory=$False,Position=3)]
            [string]$Method
    )

    if( !$Method ) {
        $Method = "Get"
    }

    $Endpoint = "http://$CerberusServer/$Endpoint"

    if( $Method -eq "Get" ) {
        $parameters = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    
        if( $CerberusAPIKey ) {
            $parameters.Set( 'APIKey', $CerberusAPIKey )
        }

        if( $PZServerCerberusID ) {
            $parameters.Set( 'ServerID', $PZServerCerberusID )
        }

        foreach ( $d in $Data.GetEnumerator() ) {
            if( $d.Value -is [system.array] ) {
                foreach( $value in $d.Value ) {
                    $parameters.Add( $d.Name, $value )
                }
            }
            else {
                $parameters.Add( $d.Name, $d.Value )
            }
        }

        $Endpoint = "$($Endpoint)?$($parameters.ToString())"

        $response = Invoke-RestMethod -Uri "$Endpoint" -UserAgent $UserAgent
    }
    else {
        $response = Invoke-RestMethod -Uri "http://$CerberusServer/$Endpoint" -UserAgent $UserAgent -Body $Data
    }

    #$response | Out-String | Write-Host 
    #$response.content | Out-String | Write-Host

    #Write-Host "Cerberus API Call Success"
    if( $response.status -eq 0 ) {
        if( $response.control.interval -gt $CerberusQueryInterval ) {
            $CerberusQueryInterval = $response.control.interval
        }

        $content = @{}
        $response.content.psobject.properties | ForEach {
            $content[$_.Name] = $_.Value
        }

        $content
    }
    else {
        Write-Host "The Cerberus server responded with error code $response.status"
        Write-Host $data
    }

    #if( $response.StatusCode -eq 200 ) {
    #    Write-Host Converting...
        #$data = ConvertFrom-Json $response.Content
    #    Write-Host $data

        #if( $data[ "control" ][ "max_interval" ] -gt $CerberusMinQueryInterval )
        #{
        #    $CerberusMinQueryInterval = 
        #}
    #    Write-Host "Cerberus API Call sucess"

    #    if( $data[ "status" ] -eq 0 ) {
    #        $data[ "content" ]
    #    }
    #    else {
    #        Write-Host "The Cerberus server responded with error code $($data[ "status" ])"
    #        Write-Host $data
    #    }
    #}
    #else
    #{
    #    Write-Host "The Cerberus API call responded with an unexpected HTTP status code: $($response.StatusCode)"
    #}
}