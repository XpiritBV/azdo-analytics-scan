[CmdletBinding()]
param
(
    [string] $organization, 
    [string] $AzdoProject = "StouteDag"
)

function Load-BaseUri {
    $baseUri = ""
    # change baseUri
    if ($organization.StartsWith("https://") -and !$organization.StartsWith("https://dev.azure.com")){
        $baseUri = "https://vsrm.dev.azure.com/$Organization/$AzdoProject"
    }
    else {
        # assume on prem url
        $baseUri = $organization
    }
    Write-Host "Using this base url: " $baseUri
    return $baseUri
}
$commitsFrom = "1/12/2019 00:00:00"
$commitsTo = "20/12/2019 00:00:00"

function Get-ConnectedBuildDefinitions {
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [pscustomobject[]] $repositories
    )
    [pscustomobject[]] $results =  @()
    
    Write-Host "Loading build definitions"
    $buildUrl = "$($BaseUri)/_apis/build/definitions"
    $definitions = Invoke-RestMethod -Uri $buildUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 
    Write-Host "Found $($definitions.Count) build definitions"

    $definitions.Value | ForEach-Object {
        $buildUrl = "$($BaseUri)/_apis/build/definitions/$($_.id)"
        $definition = Invoke-RestMethod -Uri $buildUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 

        $added = $false;
        foreach ($repository in $repositories.Values) {
            # We only need the builds that trigger based on our main branch location or use a tfvc mapping to the mainbranch
            # triggers included branches are defined with a "+"
            if ($definition.repository.type -eq "TfsGit")
            {
                if ($definition.repository.id -eq $repository.Id) {
                    Write-Verbose "Found build with link to Git repo: $($definitions.name)"
                    $results += [pscustomobject] @{
                        repository = $repository
                        definition = [pscustomobject] @{ 
                            name = $definition.name 
                            id = $definition.id
                            agentQueue = $definition.queue.name
                            }
                        }
                    $added = $true
                }
            }
            elseif ($definition.repository.type -eq "TfsVersionControl") {                
                Write-Warning "Found a TFVC repository: not supported (yet)"
            }
            else {
                #could be anything else, maybe add later
                Write-Warning "Found a $($definition.repository.type) repository: not supported (yet)"
            }
        }

        if (!$added)
        {
            Write-Host "Found build definition that is NOT linked to any repository: $($definition.name)"
            # add to the list so we still have all builds
            $results += [pscustomobject] @{
                repository = $null
                definition = [pscustomobject] @{ 
                    name = $definition.name 
                    id = $definition.id
                    agentQueue = $definition.queue.name
                    }
                }
        }
    }

    #return list of repository ids with builds
    return $results
}

function Get-ConnectedReleaseDefinitions {
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [pscustomobject[]] $ConnectedBuilds
    )
    [pscustomobject[]] $results = @()

    Write-Host "Loading release definitions"
    $releaseUrl = "$($BaseUri)/_apis/release/definitions?api-version=3.0-preview.3"
    
    $definitions = Invoke-RestMethod -Uri $releaseUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get
    Write-Host "Found $($definitions.Count) release definitions"

    $definitions.Value | ForEach-Object {
        $releaseUrl = "$($BaseUri)/_apis/release/definitions/$($_.Id)?api-version=3.0-preview.3"
        $definition = Invoke-RestMethod -Uri $releaseUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 

        Write-Verbose "Analysing $($_.name) for artifacts referencing to $($ConnectedBuilds.Name)"
        $added = $false;
        foreach ($connectedBuild in $ConnectedBuilds) {
            # Does the release have any artifact that is originated from the connected builds
            # Then we need to change that to        
            $buildAsArtefact = $definition.artifacts | Where-Object {$_.type -eq "Build"}
            
            foreach ($artefact in $buildAsArtefact) {
                if ($artefact.type -eq "Build") {
                    if ($connectedBuild.definition.id -eq $buildAsArtefact.definitionReference.definition.id) {              
                        Write-Verbose "Found $($definition.name)"
                        $results += [pscustomobject]@{
                            ReleaseId = $definition.Id
                            ReleaseName = $definition.Name
                            BuildId = $connectedBuild.definition.id
                            BuildName = $connectedBuild.definition.name
                            }
                        $added = $true
                    }
                    else {
                        Write-Verbose ""
                    }
                }
                else {
                    Write-Verbose "Found unsupported release artefact type $($artefact.type)"
                }
            }
        }
        
        if (!$added) {
            Write-Host "Found a release that we could not link to a build: $($definition.Name)"
            $results += [pscustomobject]@{
                ReleaseId = $definition.Id
                ReleaseName = $definition.Name
                BuildId = $connectedBuild.definition.id
                BuildName = $connectedBuild.definition.name
                }
        }
    }
    return $results
}

function Set-PatToken {
    if([string]::IsNullOrEmpty($env:PAT))
    {
        throw "No PAT provided."
    } 
    $userpass = ":$($env:PAT)"
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($userpass))
    $env:Token = "Basic $encodedCreds"
}

function Get-AllRepos {
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
       
    )

    $results = New-Object PSObject 
    $results | Add-Member -NotePropertyName Count -NotePropertyValue 0
    $results | Add-Member -NotePropertyName Values -NotePropertyValue @()

    Write-Host "Loading repositories"
    $repoUrl = "$($BaseUri)/_apis/git/repositories?includeLinks=true&includeAllUrls=true&includeHidden=true&api-version=5.1"
    
    $repos = Invoke-RestMethod -Uri $repoUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get
    $results.Count = $repos.count
    
    $repos.Value | ForEach-Object {
        $results.Values += [pscustomobject]@{
            Id = $_.id
            Name = $_.name
            }
    }

    return $results
}

function GetCommits{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [pscustomobject] $repositories
    )
    [pscustomobject[]] $results =  @()

    Write-Host "Loading commits"
    foreach ($repository in $repositories.Values) {
        $buildUrl = "$($BaseUri)/_apis/git/repositories/$($repository.Id)/commits?searchCriteria.toDate=$($commitsTo)&searchCriteria.fromDate=$($commitsFrom)"
        $commits = Invoke-RestMethod -Uri $buildUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 

        $results += [pscustomobject] @{
            repository = $repository
            commitcounts = $commits.count
            commitsFrom = $commitsFrom
            commitsTo = $commitsTo
        }
    }
    #return list of repository ids with builds
    return $results
}

Set-PatToken
$BaseUri = Load-BaseUri

# load all repos
try {
    $allRepos = Get-AllRepos
    Write-Host "Found $($allRepos.Count) repositories"
}
catch {
    $ErrorMessage = $_.Exception.Message
    $FailedItem = $_.Exception.ItemName
    # error occured in first call, exit now
    Write-Error "An error occured in loading the repositories. $ErrorMessage $FailedItem"
    return
}

# load the number of commits from all repos
$repoCommitCounts = GetCommits $allRepos
#Write-Verbose $(ConvertTo-Json $repoCommitCounts)

# Get all build definitions and the connections to the repos
Write-Host "Build definitions:"
$connectedBuildDefinitions = Get-ConnectedBuildDefinitions -Repositories $allRepos
Write-Host "Found $($connectedBuildDefinitions.Count) connected build definitions"
#Write-Verbose $(ConvertTo-Json $connectedBuildDefinitions)

# Get all release definitions and the connections to the builds
$connectedReleases = Get-ConnectedReleaseDefinitions $connectedBuildDefinitions
Write-Host "Release definitions:"
Write-Host "Found $($connectedReleases.Count) connected release definitions"
#Write-Verbose $(ConvertTo-Json $connectedReleases)

# load central object:
$data = [pscustomobject]@{
    Repositories = $allRepos
    CommitCounts = $repoCommitCounts
    BuildDefinitions = $connectedBuildDefinitions
    #ReleaseDefinitions = $connectedReleases
}
# spool the data to an export file
$dataPath = ".\Data.json"
Write-Host "Saving the data to $dataPath"
$data | ConvertTo-Json -depth 100 | Out-File $dataPath
