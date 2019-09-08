[CmdletBinding()]
param
(
    [string] $organization, 
    [string] $AzdoProject = "StouteDag"
) 


function Get-ConnectedBuildDefinitions
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [pscustomobject[]] $repositories
    )
    [pscustomobject[]] $results =  @()

    $buildUrl = "$($BaseUri)/_apis/build/definitions"
    $definitions = Invoke-RestMethod -Uri $buildUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 

    $definitions.Value | %{
        $buildUrl = "$($BaseUri)/_apis/build/definitions/$($_.id)"
        $definition = Invoke-RestMethod -Uri $buildUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 

        Write-Verbose "Analysing $($definitions.name) for mappings to $branch or triggers on +$branch"
        $added = $false;
        foreach ($repository in $repositories) {
            #We only need the builds that trigger based on our mainbranch location or use a tfvc mapping to the mainbranch
            #triggers included branches are defined with a "+"
            if ($definition.repository.type -eq "TfsGit")
            {
                if ($definition.repository.id -eq $repository.Id)
                {
                    Write-Verbose "Found build with link to Git repo: $($definitions.name)"
                    $results += [pscustomobject]@{
                        repository = $repository
                        definition = [pscustomobject]@{ 
                            name = $definition.name 
                            id = $definition.id
                            }
                        }
                    }
                    $added = $true
            }
            elseif ($definition.repository.type -eq "TfsVersionControl") {                
                Write-Verbose "Found a TFVC repository: not supported (yet)"
            }
            else {
                #could be anything else, maybe add later
            }
        }

        if (!$added)
        {
            # add to the list so we still have all builds
            $results += [pscustomobject]@{
                repository = $null
                definition = [pscustomobject]@{ 
                    name = $definition.name 
                    id = $definition.id
                    }
                }
        }
    }

    #return list of repository ids with builds
    return $results
}

function Get-ConnectedReleaseDefinitions
{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
        [pscustomobject[]] $ConnectedBuilds
    )
    [pscustomobject[]] $results =  @()

    # change baseUri
    $BaseUri = "https://vsrm.dev.azure.com/$Organization/$AzdoProject"

    $releaseUrl = "$($BaseUri)/_apis/release/definitions?api-version=3.0-preview.3"
    Write-Verbose $releaseUrl
    
    $definitions = Invoke-RestMethod -Uri $releaseUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get

    $definitions.Value | %{
        $releaseUrl = "$($BaseUri)/_apis/release/definitions/$($_.Id)?api-version=3.0-preview.3"
        $definition = Invoke-RestMethod -Uri $releaseUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 

        Write-Verbose "Analysing $($_.name) for artifacts referencing to $($ConnectedBuilds.Name)"
        $added = $false;
        foreach ($connectedBuild in $ConnectedBuilds)
        {
            #does the release have any artifact that is originated from the connected builds
            #then we need to change that to        
            $buildAsArtefact = $definition.artifacts | Where-Object {$_.type -eq "Build"}
            
            foreach ($artefact in $buildAsArtefact)
            {
                if ($artefact.type -eq "Build") {
                    if ($connectedBuild.definition.id -eq $buildAsArtefact.definitionReference.definition.id)  
                    {              
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

                if (!$added) {
                    $results += [pscustomobject]@{
                        ReleaseId = $definition.Id
                        ReleaseName = $definition.Name
                        BuildId = $connectedBuild.definition.id
                        BuildName = $connectedBuild.definition.name
                        }
                }
            }
        }
    }
    return $results
}

function Set-PatToken
{
    if([string]::IsNullOrEmpty($env:PAT))
    {
        throw "No PAT provided."
    } 
    $userpass = ":$($env:PAT)"
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($userpass))
    $env:Token = "Basic $encodedCreds"
}

function Get-AllRepos{
    [CmdletBinding()]
    [OutputType([object])]
    param
    (
       
    )
    [pscustomobject[]] $results =  @()

    #GET https://dev.azure.com/{organization}/{project}/_apis/git/repositories?includeLinks={includeLinks}&includeAllUrls={includeAllUrls}&includeHidden={includeHidden}&api-version=5.1

    $repoUrl = "$($BaseUri)/_apis/git/repositories?includeLinks=true&includeAllUrls=true&includeHidden=true&api-version=5.1"
    Write-Verbose $repoUrl
    
    $repos = Invoke-RestMethod -Uri $repoUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get

    $repos.Value | %{
        $results += [pscustomobject]@{
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
        [pscustomobject[]] $repositories
    )
    [pscustomobject[]] $results =  @()

    foreach ($repository in $repositories) {
        $buildUrl = "$($BaseUri)/_apis/git/repositories/$($repository.Id)/commits?searchCriteria.toDate=8/23/2019&searchCriteria.fromDate=1/1/2019"
        $commits = Invoke-RestMethod -Uri $buildUrl -Headers @{Authorization = $env:Token} -ContentType "application/json" -Method Get 

        $results += [pscustomobject]@{
            repository = $repository
            commitcounts = $commits.count
        }
    }
    #return list of repository ids with builds
    return $results
}

$BaseUri = "https://dev.azure.com/$Organization/$AzdoProject"
Set-PatToken

# load all repos
try {
    $allRepos = Get-AllRepos   
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
Write-Verbose "Commit counts per repo:"
Write-Verbose $(ConvertTo-Json $repoCommitCounts)

# Get all build definitions and the connections to the repos
Write-Verbose "Build definitions:"
$connectedBuildDefinitions = Get-ConnectedBuildDefinitions -Repositories $allRepos
Write-Verbose $(ConvertTo-Json $connectedBuildDefinitions)

# Get all release definitions and the connections to the builds
$connectedReleases = Get-ConnectedReleaseDefinitions $connectedBuildDefinitions
Write-Verbose "Release definitions:"
Write-Verbose $(ConvertTo-Json $connectedReleases)

# load central object:
$data = [pscustomobject]@{
    Repositories = $allRepos
    CommitCounts = $repoCommitCounts
    BuildDefinitions = $connectedBuildDefinitions
    ReleaseDefinitions = $connectedReleases
}
Write-Host $data

# todo: spool the data to an export file
