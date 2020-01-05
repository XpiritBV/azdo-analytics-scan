function Install-Dependencies {

    # verify dependent modules are loaded
    $DependentModules = 'PSGraph' #, 'az'
    $Installed = Import-Module $DependentModules -PassThru -ErrorAction SilentlyContinue | Where-Object { $_.name -In $DependentModules }
    $missing = $DependentModules | Where-Object { $_ -notin $Installed.name }
    if ($missing) {
        Write-host "    [+] Module dependencies not found [$missing]. Attempting to install." -ForegroundColor Green
        Install-Module $missing -Force -AllowClobber -Confirm:$false -Scope CurrentUser
        Import-Module $missing
    }

    # Install GraphViz from the Chocolatey repo
    if(!(Get-Package GraphViz)){
        Register-PackageSource -Name Chocolatey -ProviderName Chocolatey -Location http://chocolatey.org/api/v2/ -ErrorAction SilentlyContinue -Verbose
        Find-Package graphviz | Install-Package -ForceBootstrap -Verbose
    }
}

# Install-Dependencies

function Visualize {
    $DarkMode = $false
    $ShowGraph = $true
    $OutputFormat = "png"

    if ($DarkMode) {
        Write-Verbose "`'Dark mode`' is enabled."
        $GraphColor = 'Black'
        $SubGraphColor = 'White'
        $GraphFontColor = 'White'
        $EdgeColor = 'White'
        $EdgeFontColor = 'White'
        $NodeColor = 'White'
        $NodeFontColor = 'White'
    }
    else {
        $GraphColor = 'White'
        $SubGraphColor = 'Black'
        $GraphFontColor = 'Black'
        $EdgeColor = 'Black'
        $EdgeFontColor = 'Black'
        $NodeColor = 'Black'
        $NodeFontColor = 'Black'
    }

    #region graph-generation
    Write-Verbose "Starting topology graph generation"
    # rankdir = "LR" #Left to Right
    # rankdir = "TB" #Top to Bottom 
    $Graph = Graph 'Topology' @{overlap = 'false'; splines = 'true' ; rankdir = 'LR'; color = $GraphColor; bgcolor = $GraphColor; fontcolor = $GraphFontColor;  } {
        
        edge @{color = $EdgeColor; fontcolor = $EdgeFontColor }
        node @{color = $NodeColor ; fontcolor = $NodeFontColor }

        SubGraph "SubGraph1" @{label = "SubGraph1_Label"; labelloc = 'b'; penwidth = "1"; fontname = "Courier New" ; color = $SubGraphColor } {
            
            # connectors
            Edge -From "A" `
                -to "B1" `
                -Attributes @{
                arrowhead = 'box';
                style     = 'dotted';
                label     = ' Contains'
                penwidth  = "1"
                fontname  = "Courier New"
            }
            
            Edge -From "B1" `
                -to "C" `
                -Attributes @{
                arrowhead = 'box';
                style     = 'dotted';
                label     = ' Contains'
                penwidth  = "1"
                fontname  = "Courier New"
            }

            Edge -From "B2" `
                -to "C" `
                -Attributes @{
                arrowhead = 'box';
                style     = 'dotted';
                label     = ' Contains'
                penwidth  = "1"
                fontname  = "Courier New"
            }

            Edge -From "C" `
                -to "D" `
                -Attributes @{
                arrowhead = 'box';
                style     = 'dotted';
                label     = ' Contains'
                penwidth  = "1"
                fontname  = "Courier New"
            }

            # basic nodes
            Get-ImageNode -Name "A" -Rows "A"
            Get-ImageNode -Name "B1" -Rows "B1"
            Get-ImageNode -Name "B2" -Rows "B2"
            Get-ImageNode -Name "C" -Rows "C"
            Get-ImageNode -Name "D" -Rows "D"
        }
    }
    
    Export-PSGraph -Source $Graph -ShowGraph:$ShowGraph -OutputFormat $OutputFormat -OutVariable Graph

    Write-Verbose "Graph Exported to path: $($Graph.fullname)"
}

function Get-ImageNode {
    param(
        [string[]]$Rows,
        [string]$Type,
        [String]$Name,
        [String]$Label,
        [String]$Style = 'Filled',
        [String]$Shape = 'none',
        [String]$FillColor = 'White'
    )

    node $Name -Attributes @{
        Label     = $Name; 
        shape     = "rect";
        #style     = $styles[$Type] ; 
        #fillcolor = $Colors[$Type];
        penwidth = "1";
        fontname = "Courier New";
    }
}


Visualize -Verbose