## Invoke-vCloud.psm1 - Wrapper for Invoke-RestMethod for consuming VMware vCloud Director API

# Main function to interact with the vCloud Director REST API from within PowerShell
# Note: Does not require PowerCLI, but without it you'll need to specify a valid x-vcloud-authorization 
# or JWT token to authenticate against the vCloud API.

Function Invoke-vCloud(
    [Parameter(Mandatory=$true)][uri]$URI,      # We must specify the API endpoint
    [string]$ContentType,                       # Optional ContentType for returned XML
    [string]$Method = 'GET',                    # HTTP verb to use (default 'GET')
    [Parameter(Mandatory=$true)][string]$ApiVersion,  # vCloud Director API version (e.g. '34.0')
    [string]$Body,                              # Any body document to be submitted to the API
    [int]$APITimeout = 30,                      # Timeout in seconds to wait for API response (by default)
    [int]$TaskTimeout = 300,                    # Timeout in seconds to wait for a VCD task to complete
    [switch]$WaitForTask,                       # Should we wait for task completion if reponse includes a task href?
    [string]$vCloudToken,                       # If not already authenticated using Connect-CIServer (PowerCLI) allow us to specify a token
    [string]$vCloudJWT,                         # Allow use of JWT token instead of x-vcloud-authorization token
    [switch]$skipCertificateCheck               # Ignore the SSL certificate presented by the endpoint - Requires PS 7.0+
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
An required parameter to specify the API version to be used for the call. If
API version is not known use Get-vCloudAPIVersion to determine this for the
endpoint first.
.PARAMETER Body
An optional parameter which specifies XML body to be submitted to the API
(usually for a PUT or POST action).
.PARAMETER APITimeout
An optional parameter which specifies the time (in seconds) to wait for an API
call to complete. Defaults to 40 seconds if not specified. Note that this is
the time for the API to respond and NOT for a task to complete (see 
the TaskTimeout parameter for that).
.PARAMETER TaskTimeout
An optional parameter which specifies the time (in seconds) to wait for a
Cloud Director task to finish. Tasks can be long-running, especially when
deploying new VMs/vApps so set this value appropriately if the task is
expected to take a long time.
.PARAMETER WaitForTask
If the API call we submit results in a Task object indicating an asynchronous
vCloud task, should we wait for this to complete before returning? Defaults to
$false.
.PARAMETER vCloudToken
An alternative method of passing a session token to Invoke-vCloud if there is
no current PowerCLI session established to a vCloud endpoint. The session must
have already been established and be still valid (not timed-out). The value
supplied is copied to the 'x-vcloud-authorization' header value in API calls.
.PARAMETER vCloudJWT
Another alternative method of passing a session token to Invoke-vCloud using
a Java Web Token (JWT) from an existing session. The session must have already
been established and be still valid (not timed-out). The value supplied is
copied to the 'X-VMWARE-VCLOUD-ACCESS-TOKEN' header value in API calls.
.PARAMETER skipCertificateCheck
A switch that allows ignoring invalid SSL certificates from the API endpoint.
Should not be used in production environments. Note that the
-SkipCertificateCheck option for Invoke-RestMethod is only supported in
PowerShell versions 6.0 and higher, attempting to use this flag in lower
versions of PowerShell will result in an error.
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

# Build authentication header based on current session or supplied token:

    $mySessionId = ($Global:DefaultCIServers | Where-Object { $_.Name -eq $URI.Host }).SessionId

    if ($mySessionId) {                     # Found a matching session - Connect-CIServer has been used:
        $Headers = @{'x-vcloud-authorization'=$mySessionId}
    } else {                                # No connected session found, see if we have a token:
        if ($vCloudToken) {
            $Headers = @{'x-vcloud-authorization'=$vCloudToken}
        } elseif ($vCloudJWT) {
            $Headers = @{'X-VMWARE-VCLOUD-ACCESS-TOKEN'=$vCloudJWT}
        } else {
            Write-Error ("No existing Connect-CIServer session found and no vCloudToken or vCloudJWT token specified.")
            Write-Error ("Cannot authenticate to the vCloud API, exiting.")
            Return
        }
    }

    # Configure HTTP headers for this request:
    $Headers.Add("Accept","application/*+xml;version=$($ApiVersion)")

    # Build parameters hash to be passed to Invoke-RestMethod
    $InvokeParams = @{
        Method = $Method
        Uri = $URI
        Headers = $Headers
        TimeoutSec = $APITimeout
    }

    # Handle optional parameters and add to hash where defined:
    if ($ContentType)          { $InvokeParams.ContentType          = $ContentType }
    if ($Body)                 { $InvokeParams.Body                 = $Body }
    if ($skipCertificateCheck) { $InvokeParams.SkipCertificateCheck = $true }

    # Submit API request:
    Try {
        [xml]$response = Invoke-RestMethod @InvokeParams
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

            while($TaskTimeout -gt 0) {
                $taskxml = Invoke-RestMethod -Uri $response.Task.href -Method 'Get' -Headers $Headers -TimeoutSec $APITimeout  # Get/refresh our task status
                switch ($taskxml.Task.status) {
                    "success" { Write-Host " "; Write-Host "Task completed successfully"; return $true; break }
                    "running" { Write-Host -NoNewline "." }
                    "error" { Write-Host " "; Write-Warning "Error running task"; return $false; break }
                    "canceled" { Write-Host " "; Write-Warning "Task was cancelled"; return $false; break }
                    "aborted" { Write-Host " "; Write-Warning "Task was aborted"; return $false; break }
                    "queued" { Write-Host -NoNewline "q" }
                    "preRunning" { Write-Host -NoNewline "P" }
                } # switch on current task status
                $TaskTimeout -= 5                                       # Decrease our Task timeout
                Start-Sleep -s 5                                        # Pause 5 seconds
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

Function Get-vCloudAPIVersion(
    [Parameter(Mandatory=$true)][uri]$URI,      # API Endpoint to check the version for
    [int]$APITimeout = 30,                      # Optional timeout in seconds to wait for API response
    [switch]$skipCertificateCheck               # Ignore SSL errors (defaults to False)
)
{
<#
.SYNOPSIS
Gets the highest supported API version for the specified vCloud endpoint
.DESCRIPTION
Get-vCloudAPIVersion provides an easy method to determine the highest
non-deprecated API version for the URI specified. The format of API versions
in vCloud Director is a string value (e.g. '33.0') even though all
currently valid values appear to be floats.
.PARAMETER URI
A mandatory parameter which provides the API URI to be accessed.
.PARAMETER APITimeout
An optional parameter which specifies the time in seconds to wait for a
response from the API version call. If this time is exceeded a timeout
error is returned. Defaults to 30 seconds.
.PARAMETER skipCertificateCheck
A switch that allows ignoring invalid SSL certificates from the API endpoint.
Should not be used in production environments. Note that the
-SkipCertificateCheck switch for Invoke-RestMethod is only supported in
PowerShell versions 6.0 and higher, attempting to use this flag in lower
versions of PowerShell will result in an error.
.OUTPUTS
A string containing the highest supported API version for the specified
URI.
.EXAMPLE
Returns the highest supported API version for the specified URI:
PS /> Get-vCloudAPIVersion -URI https://my.cloud.com/

33.0
.NOTES
No existing session is required to the specified URI as the request for
API versions supported by the endpoint does not require authentication.
#>

    $InvokeParams = @{
        Method = 'Get'
        Uri = "https://$($URI.Host)/api/versions"
        Headers = @{'Accept'='application/*+xml'}
        TimeoutSec = $APITimeout
    }
    if ($skipCertificateCheck) {
        $InvokeParams.SkipCertificateCheck = $true
    }

    Try { [xml]$r = Invoke-RestMethod @InvokeParams }
    Catch {
        Write-Warning ("Invoke-vCloud Exception finding API versions: $($_.Exception.Message)")
        if ( $_.Exception.ItemName ) { Write-Warning ("Failed Item: $($_.Exception.ItemName)") }
        Return "Error determining highest supported API version."
    }
    Return (($r.SupportedVersions.VersionInfo | Where-Object { $_.deprecated -eq $False }) | Measure-Object -Property Version -Maximum).Maximum.ToString() + ".0"
}

# Export function from module
Export-ModuleMember -Function Invoke-vCloud
Export-ModuleMember -Function Get-vCloudAPIVersion