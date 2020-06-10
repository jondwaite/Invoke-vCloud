# Invoke-vCloud
PowerShell module to make API calls to vCloud Director easier

**NOTE:** Previous versions of Invoke-vCloud assumed a common base API version. This was fine, but as these older versions become deprecated in newer releases this can cause issues. Old code that relies on this behaviour should be updated to first retrieve the highest supported API version with [Get-vCloudAPIVersion](#Get-vCloudAPIVersion-cmdlet) and use the returned value in any requests to [Invoke-vCloud](#Invoke-vCloud-cmdlet) specifying the `-ApiVersion` parameter. The only alternative to this would be to make a request to get the highest supported API version before every API interaction which is very inefficient.

Invoke-vCloud contains 2 PowerShell cmdlets to make it easier to interact with VMware Cloud Director (VCD) environments. These can be used by both Service Providers (SPs) and Customers when interacting with the vCloud API.

Each cmdlet is detailed in the sections below.

## Invoke-vCloud cmdlet

Invoke vCloud requires an existing connection to a VMware Cloud Director API endpoint. This can automatically be retrieved if the connection is from VMware PowerCLI (`Connect-CIServer`) or can be manually provided using the `vCloudToken` or `vCloudJWT` parameters.

| Parameter | Mandatory | Type | Default | Description |
| --------- | --------- | ---- | ------- | ----------- |
| URI       | Yes       | URI  | -       | The URI for the API call. (e.g. https://my.cloud.com/api/org) |
| ContentType | No      | String | -     | Optional ContentType for the API body text |
| Method    | No        | String | Get   | API method type to be called |
| ApiVersion | Yes      | String | -     | API version to be used, see [Get-vCloudAPIVersion cmdlet](#Get-vCloudAPIVersion-cmdlet) below |
| Body      | No        | String | -     | The body text to be submitted to the API |
| APITimeout | No       | Integer | 30   | The time (in seconds) for the API to respond |
| TaskTimeout | No      | Integer | 300  | The time (in seconds) for an API task to complete if `WaitforTask` is specified and the task is successfully submitted |
| WaitforTask | No      | Switch | -     | If this switch is specified and the API request results in a long-running operation (e.g. deploy a new VM) then Invoke-vCloud will wait for task completion before returning a true/false result for success/failure. |
| vCloudToken | No      | String | -     | Specifies a token to be used in the `x-vcloud-authorization` header to API requests for connections which don't already exist (using `Connect-CSIServer`) |
| vCloudJWT   | No      | String | -     | Specifies a Java Web Token (JWT) to be used in the `X-VMWARE-VCLOUD-ACCESS-TOKEN` header to API requests for connections which don't already exist (using `Connect-CIServer`) |
| Accept    | No        | String | application/*+xml | Override the 'Accept' HTML header submitted with an API request. The default (`application/*+xml`) works for most cases.
| skipCertificateCheck | No | Switch | - | If this switch is specified then no SSL certificate check will be conducted on the API endpoint. This can be useful if working against development/test VCD instances which aren't using trusted SSL certificates. Note that this parameter is only supported in PowerShell version 6.0 up |

### Example

```PowerShell
PS /> Invoke-vCloud -URI https://my.cloud.com/api/org -ApiVersion '34.0'


xml                                             OrgList
---                                             -------
version="1.0" encoding="UTF-8" standalone="yes" OrgList

PS /> (Invoke-vCloud -URI https://chc.ccldev.co.nz/api/org -ApiVersion '34.0').OrgList.Org.href

https://my.cloud.com/api/org/a6f8e9f1-a10c-4254-b666-21e1099eff79
```

## Get-vCloudAPIVersion cmdlet

Get-vCloudAPIVersion retrieves the highest supported API version from the specified VMware Cloud Director API endpoint and returns this as a string. This can then be used in subsequent calls to [Invoke-vCloud](##Invoke-vCloud)

| Parameter | Mandatory | Type | Default | Description |
| --------- | --------- | ---- | ------- | ----------- |
| URI       | Yes       | URI  | -       | The URI of the API endpoint (e.g. https://my.cloud.com/) |
| APITimeout | No       | Integer | 30   | The time (in seconds) for the API to respond |
| skipCertificateCheck | No | Switch | - | If this switch is specified then no SSL certificate check will be conducted on the API endpoint. This can be useful if working against development/test VCD instances which aren't using trusted SSL certificates. Note that this parameter is only supported in PowerShell version 6.0 up |

### Example

```PowerShell
Get-vCloudAPIVersion -URI 'https://my.cloud.com'

34.0
```

Recent API versions are shown in the table below:

## VMware Cloud Director API Versions

| API Version | VMware Cloud Director Version | Released  |
| ----------- | ----------------------------- | --------  |
| 27.0        | vCloud Director 8.2           | February 2017 |
| 29.0        | vCloud Director 9.0           | September 2017 |
| 30.0        | vCloud Director 9.1           | March 2018 |
| 31.0        | vCloud Director 9.5           | October 2018 |
| 32.0        | vCloud Director 9.7           | March 2019 |
| 33.0        | vCloud Director 10.0          | September 2019 |
| 34.0        | VMware Cloud Director 10.1    | April 2020 |
