

$username = "svc_monitoring"
$password = ""
$environment = "https://customer.workspaceoneaccess.com"
$syslogenvironment = "syslog.customer.internal:8000"
$PSEmailServer = "smtp.server.local"


function Sent-Alert() {	
     Param (
        [parameter(Mandatory = $true)]
        $senthost,
        $sentservice,
		$sentstatus
    ) 	
		
		############ If you want to send to syslog uncomment this:
		<#
		$SyslogHeader = @{Authorization = "Splunk GUID-GUID-GUID-GUID"}
		$fields = @{field1 = 00000}
		$eventdata = @{Server = "$senthost"}
		$eventdata += @{Service = $sentservice}
		$eventdata += @{Status = $sentstatus}

		$event = @{
		index		= "index_name_here"
		event 		= $eventdata
		sourcetype	= "json"
		source		= "source_name_here"
		fields      = $fields
		} | ConvertTo-Json
		
		$sendAlert = Invoke-WebRequest -Method Post -Uri $syslogenvironment  -Body $event -Headers $Header 		
		#>
		
		############## If you want to send to smtp uncomment this:
		##Send-MailMessage -From ws1accessmonitor@customer.com -To email_dl@customer.com -Subject "WS1Access Monitor - host:$senthost service:$sentservice status:$sentstatus"
}



### Get Access Token ###
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("Accept", "application/json; charset=utf-8")

$body = "{`n    `"username`": `"$username`",`n    `"password`": `"$password`",`n    `"issueToken`": `"true`"`n}"

try {
	$ServicePoint = [System.Net.ServicePointManager]::FindServicePoint($environment) 
	$response = Invoke-WebRequest "$environment/SAAS/API/1.0/REST/auth/system/login" -Method 'POST' -Headers $headers -Body $body -Proxy "http://proxy.jpmchase.net:10443" 
	$ServicePoint.CloseConnectionGroup("")
} catch {
	#Write-Output "Auth API Call Failed"
	Sent-Alert("None") ("Authn") ("API Call Failed")
}

if ($response.StatusCode -ne "200"){
	#Write-Output "Auth call failed with non-200"
	Sent-Alert("None") ("Authn") ("API Call Failed Non-200")
	break
}

$responsedata = $response | ConvertFrom-Json
$accessToken = $responsedata.sessionToken
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer $accessToken")



### Get all connector services ###

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Accept", "application/json, text/plain, */*")
$headers.Add("Authorization", "Bearer $accessToken")
$headers.Add("Content-Type", "application/vnd.vmware.horizon.manager.enterprise.authmethod.config.summary.list+json;charset=UTF-8")

try {
	$ServicePoint = [System.Net.ServicePointManager]::FindServicePoint($environment)
	$response1 = Invoke-WebRequest "$environment/SAAS/jersey/manager/api/enterpriseservices" -Method 'GET' -Headers $headers  -Proxy "http://proxy.jpmchase.net:10443" 
	$ServicePoint.CloseConnectionGroup("")
} catch {
	#Write-Output "Get all Connector services API Call Failed"
	Sent-Alert("None") ("All Connector") ("API Call Failed")
}

if ($response1.StatusCode -ne "200"){
	#Write-Output "Get all Connector services failed with non-200"
	Sent-Alert("None") ("All Connector") ("API Call Failed Non-200")
	break
}




$responsedata1 = $response1 | ConvertFrom-Json
$allconservices = $responsedata1.items

$x = 0
$y = $allconservices.length

### loop through all Connectors and Services returned to check health ###

while($x -lt $y){
	
	$conservice = $allconservices[$x]
	$x++
	$hostname = $conservice.hostname
	$servicetype = $conservice.servicetype
	$enterpriseServiceUUID = $conservice.enterpriseServiceUUID

	
	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$headers.Add("Accept", "application/json, text/plain, */*")
	$headers.Add("Content-Type", "application/vnd.vmware.horizon.manager.enterprise.authmethod.config.summary.list+json;charset=UTF-8")
	$headers.Add("Authorization", "Bearer $accessToken")
	
	try {
		$ServicePoint = [System.Net.ServicePointManager]::FindServicePoint($environment)
		$response2 = Invoke-WebRequest "$environment/SAAS/jersey/manager/api/enterpriseservices/$enterpriseServiceUUID/health" -Method 'GET' -Headers $headers  -Proxy "http://proxy.jpmchase.net:10443"
		$ServicePoint.CloseConnectionGroup("")
	} catch {
		#Write-Host "Get $hostname $servicetype API Call Failed" -ForegroundColor Red
		Sent-Alert($hostname) ($servicetype) ("API Call Failed")
		continue
	}

	if ($response2.StatusCode -ne "200"){
		#Write-Host "Get $hostname $servicetype API Call Failed Non-200" -ForegroundColor Red
		Sent-Alert($hostname) ($servicetype) ("API Call Failed Non-200")
		continue
		
	}

	$responsedata2 = $response2 | ConvertFrom-Json
	$responsedata2allOk = $responsedata2.AllOk

	if ($responsedata2allOk -ne $true){
		#Write-Host "Get $hostname $servicetype is in a bad state" -ForegroundColor Red
		Sent-Alert($hostname) ($servicetype) ("Bad")
		continue
	}
	if ($responsedata2allOk -eq $true){
		#Write-Host "Get $hostname $servicetype is in a good state" -ForegroundColor Green
		Sent-Alert($hostname) ($servicetype) ("Good")
		continue
	}

}

