###############################################
# Google Workspace User Management - Suspend
# created by: Drewskinator99
# to view the instructions for this code, visit
# my blog at:
#      https://medium.com/@drewskinator99/google-workspace-disable-inactive-users-with-powershell-and-the-admin-sdk-api-bcd6508e938a
###############################################
$clientIDFilepath = "C:\path\clientID.xml"
$clientSecretFilepath = "C:\path\clientSecret.xml"
$customerIDFilepath = "C:\path\customerID.xml"
# grab secrets and create URL variables
$clientID = Import-Clixml -Path $clientIDFilepath
$clientSecret = Import-Clixml -Path $clientSecretFilepath
$customerID = Import-Clixml -Path $customerIDFilepath
$redirectUrl = "http://localhost/oauth2callback"
$scope = "https://www.googleapis.com/auth/admin.directory.user"
# auth url creation
$authUrl = "https://accounts.google.com/o/oauth2/auth?redirect_uri=$redirectUrl&client_id=$clientID&scope=$scope&approval_prompt=force&access_type=offline&response_type=code"
$authUrl | clip
$authUrl
# Copy this from the browser  #
$responseCode = "<get this from the browser>"
$requestUri = "https://www.googleapis.com/oauth2/v3/token"
# create API request body
$body = "code=$([System.Web.HttpUtility]::UrlEncode($responseCode))&redirect_uri=$([System.Web.HttpUtility]::UrlEncode($redirectUrl))&client_id=$clientID&client_secret=$clientSecret&scope=$scope&grant_type=authorization_code"
# Grab authentication token to access the User API
$token = Invoke-RestMethod -Uri $requestUri -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
#print token
$token

# Initialize Array
$users_array = @()

# Grab all the users with the API
$users = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token.access_token)"} -Uri "https://admin.googleapis.com/admin/directory/v1/users?customer=$customerID"

#populate array for first page of pagination
$users_array += $users.users

# pagination initialization
$users_next_page = $users.nextPageToken

# loop through the users and populate the users array  
while($null -ne $users_next_page){
    # make an API call for reach page
    $users = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($token.access_token)"} -Uri "https://admin.googleapis.com/admin/directory/v1/users?customer=$customerID&pageToken=$($users_next_page)")
    # update the array of users
    $users_array += $users.users
    # move to the next page
    $users_next_page = $users.nextPageToken
}

# create array of all users
$all_users = $users_array

# iterate through the users array and create a "user" object for each index
$createUserObjects = foreach($user in $all_users){
    # needed to make the API request
    $email = $user.primaryemail
    # API request
    $res = Invoke-RestMethod -Headers @{Authorization = "Bearer $($token.access_token)"} -Uri "https://admin.googleapis.com/admin/directory/v1/users/$($user.primaryemail)"
    #store variables for easier reference
    $last_login = $res.lastLoginTime
    $id = $res.id
    # create user object
    [PSCustomObject]@{
        Email = $email
        LastLogin = $last_login
        Suspended = if($res.suspended){$res.suspended}
        orgUnit = $res.orgUnitPath
        ID = $id
    }
}

# OPTIONAL - print grid of user data into a table
# $createUserObjects | Out-GridView

$datetoCheck = (Get-Date).AddDays(-90)
foreach($userobj in $createUserObjects){
    # grab last login from user the object
    $lastlogin = $userobj.LastLogin
    # check to see if the user hasn't signed in for at least 90 days
    if($lastLogin -lt $datetoCheck -and $userobj.orgUnit -notlike "*Service*" -and $lastlogin.Year -gt 1980 ){
        $id = $userobj.ID
        $Email = $userobj.Email
        # update the user to set suspended field
        $Body = @{
            suspended = $True
        }
        # prepare headers and URI
        $Headers = @{Authorization = "Bearer $($token.access_token)"}
        $URI = "https://admin.googleapis.com/admin/directory/v1/users/$id"
        # make API call
        Invoke-RestMethod -Headers $Headers -Uri $URI -Method PUT -Body ($body| ConvertTo-Json)   -ContentType application/json
        # print results
        Write-Output "Suspended user: $Email `n`t who last logged on: $lastlogin`n"        
    }   
}
# End of script