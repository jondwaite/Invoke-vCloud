## Invoke-vCloud.psm1 - Wrapper for Invoke-RestMethod for consuming VMware vCloud Director API

# Main function to interact with the vCloud Director REST API from within PowerShell
# Note: Does not require PowerCLI, but without it you'll need to specify a valid x-vcloud-authorization token to authenticate
# against the vCloud API.

Function Invoke-vCloud(
[Parameter(Mandatory=$true)][uri]$URI,      # We must specify the API endpoint
[string]$ContentType,                       # Optional ContentType for returned XML
[string]$Method = 'GET',                    # HTTP verb to use (default 'GET')
[string]$ApiVersion,                        # vCloud Director API version
[string]$Body,                              # Any body document to be submitted to the API
[int]$Timeout = 40,                         # Timeout in seconds to wait for API response (by default)
[boolean]$WaitForTask = $false,             # Should we wait for task completion if reponse includes a task href?
[string]$vCloudToken                        # If not already authenticated using Connect-CIServer (PowerCLI) allow us to specify a token
)
{
<#
.SYNOPSIS
Provides a wrapper for Invoke-RestMethod for vCloud Director API calls
.DESCRIPTION
Invoke-vCloud provides an easy to use interface to the vCloud Director
API and provides sensible defaults for many parameters. It wraps the native
PowerShell Invoke-RestMethod cmdlet.
.PARAMETER URI
A mandatory parameter which provides the API URI to be accessed.
.PARAMETER ContentType
An optional parameter which provides the ContentType of any submitted data.
.PARAMETER Method
An optional parameter to specify the HTML verb to be used (GET, PUT, POST or
DELETE). Defaults to 'GET' if not specified.
.PARAMETER ApiVersion
An optional parameter to specify the API version to be used for the call.
If not specified a request will be made to https://<host>/api/versions and
the highest non-deprecated version returned used.
.PARAMETER Body
An optional parameter which specifies XML body to be submitted to the API
(usually for a PUT or POST action).
.PARAMETER Timeout
An optional parameter which specifies the time (in seconds) to wait for an API
call to complete. Defaults to 40 seconds if not specified.
.PARAMETER WaitForTask
If the API call we submit results in a Task object indicating an asynchronous
vCloud task, should we wait for this to complete before returning? Defaults to
$false.
.PARAMETER vCloudToken
An alternative method of passing a session token to Invoke-vCloud if there is
no current PowerCLI session established to a vCloud endpoint. The session must
have already been established and be still valid (not timed-out). The value
supplied is copied to the 'x-vcloud-authorization' header value in API calls.
.OUTPUTS
An XML document returned from the vCloud API (if not waiting for task), or a
success/failure indication if waiting for a task to complete.
.EXAMPLE
Returns list of Organizations to which my current vCloud Session has access
> $orgs = Invoke-vCloud -URI https://my.cloud.com/api/org
> $orgs.InnerXML
<?xml version="1.0" encoding="UTF-8"?>
<OrgList xmlns="http://www.vmware.com/vcloud/v1.5" href="https://my.cloud.com/api/org/" type="application/vnd.vmware.vcloud.orgList+xml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.vmware.com/vcloud/v1.5 http://my.cloud.com/api/v1.5/schema/master.xsd">
    <Org href="https://my.cloud.com/api/org/6f14c081-3728-4918-a5cc-bb756452f485" name="MyDemoOrg" type="application/vnd.vmware.vcloud.org+xml" />
</OrgList>
.NOTES
You must either have an existing PowerCLI connection to vCloud Director
(Connect-CIServer) in your current PowerShell session, or provide a valid token
(using the -vCloudToken parameter) in order to authenticate against the API for
calls to suceed.
#>
    $mySessionID = ($Global:DefaultCIServers | Where-Object { $_.Name -eq $URI.Host }).SessionID
    if (!$mySessionID) {                    # If we didn't find an existing PowerCLI session for our URI
        if ($vCloudToken) {                 # But we have been passed a x-vcloud-authorization token, use that
            $mySessionID = $vCloudToken
        } else {                            # Otherwise we have no authentication mechanism available so quit
            Write-Error ("No existing session found and no vCloudToken specified, cannot authenticate, exiting.")
            Return
        }
    } # $mySessionID not set

    # Determine which API version we should use if none is specified:
    if (!$ApiVersion) {
        $ApiUri = "https://$($URI.Host)/api/versions"
        $Headers = @{"Accept"='application/*+xml'}
        Try {
            [xml]$r = Invoke-RestMethod -Method Get -Uri $ApiUri -Headers $Headers -TimeoutSec $Timeout
        } Catch {
            Write-Warning ("Invoke-vCloud Exception finding API versions: $($_.Exception.Message)")
            if ( $_.Exception.ItemName ) { Write-Warning ("Failed Item: $($_.Exception.ItemName)") }
            Return
        }
        $ApiVersion = (($r.SupportedVersions.VersionInfo | Where-Object { $_.deprecated -eq $False }) | Measure-Object -Property Version -Maximum).Maximum.ToString() + ".0"

        Write-Host ("Using API version: $($ApiVersion)")
    }
    
    # If ContentType or Body are not specified, remove the variable definitions so they won't get passed to Invoke-RestMethod:
    if (!$ContentType) { Remove-Variable ContentType }
    if (!$Body) { Remove-Variable Body }

    # Configure HTTP headers for this request:
    $Headers = @{ "x-vcloud-authorization" = $mySessionID; "Accept" = 'application/*+xml;version=' + $ApiVersion }

    # Submit API request:
    Try {
        [xml]$response = Invoke-RestMethod -Method $Method -Uri $URI -Headers $Headers -Body $Body -ContentType $ContentType -TimeoutSec $Timeout
    }
    Catch {                                 # Something went wrong, so return error information and exit:
        Write-Warning ("Invoke-vCloud Exception: $($_.Exception.Message)")
        if ( $_.Exception.ItemName ) { Write-Warning ("Failed Item: $($_.Exception.ItemName)") }
        Return
    }

    if ($WaitForTask) {                     # If we've requested to wait for the task to complete
        if ($response.Task.href) {          # and we have a task href in the document returned

            Write-Host ("Task submitted successfully, waiting for result")
            Write-Host ("q=queued, P=pre-running, .=Task Running:")

            while($timeout -gt 0) {
                $taskxml = Invoke-RestMethod -Uri $response.Task.href -Method 'Get' -Headers $Headers -TimeoutSec 5        # Get/refresh our task status
                switch ($taskxml.Task.status) {
                    "success" { Write-Host " "; Write-Host "Task completed successfully"; return $true; break }
                    "running" { Write-Host -NoNewline "." }
                    "error" { Write-Host " "; Write-Warning "Error running task"; return $false; break }
                    "canceled" { Write-Host " "; Write-Warning "Task was cancelled"; return $false; break }
                    "aborted" { Write-Host " "; Write-Warning "Task was aborted"; return $false; break }
                    "queued" { Write-Host -NoNewline "q" }
                    "preRunning" { Write-Host -NoNewline "P" }
                } # switch on current task status
                $timeout -= 1                                           # Decrease our timeout
                Start-Sleep -s 1                                        # Pause 1 second
            } # Timeout expired
            Write-Warning "Task timeout reached (task may still be in progress)"
            return $false
        } else {
            Write-Warning 'Wait for task requested, but no task returned by vCloud API'
        }
    } # WaitForTask

    # Return API response to caller
    Return $response

} # Invoke-vCloud Function end

# Export function from module
Export-ModuleMember -Function Invoke-vCloud