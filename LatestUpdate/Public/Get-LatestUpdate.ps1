Function Get-LatestUpdate {
    <#
    .SYNOPSIS
        Get the latest Cumulative update for Windows

    .DESCRIPTION
        This script will return the list of Cumulative updates for Windows 10 and Windows Server 2016 from the Microsoft Update Catalog. Optionally download the updates using the -Download parameter.

    .NOTES
        Author: Aaron Parker
        Twitter: @stealthpuppy

        Original script: Copyright Keith Garner, All rights reserved.
        Forked from: https://gist.github.com/keithga/1ad0abd1f7ba6e2f8aff63d94ab03048

    .LINK
        https://support.microsoft.com/en-us/help/4043454

    .PARAMETER WindowsVersion
        Specifiy the Windows version to search for updates. Valid values are Windows10, Windows8, Windows7.

    .PARAMETER Build
        Specify the Windows build number for searching cumulative updates. Supports '17133', '16299', '15063', '14393', '10586', '10240'.

    .PARAMETER SearchString
        Specify a specific search string to change the target update behaviour. The default will only download Cumulative updates for x64.

    .EXAMPLE
        Get-LatestUpdate

        Description:
        Get the latest Cumulative Update for Windows 10 x64

    .EXAMPLE
        Get-LatestUpdate -WindowsVersion Windows10 -SearchString 'Cumulative.*x86'

        Description:
        Enumerate the latest Cumulative Update for Windows 10 x86 (Semi-Annual Channel)

    .EXAMPLE
        Get-LatestUpdate -WindowsVersion Windows10 -Build 14393 -SearchString 'Cumulative.*Server.*x64'
    
        Description:
        Enumerate the latest Cumulative Update for Windows Server 2016

    .EXAMPLE
        Get-LatestUpdate -WindowsVersion Windows8
    
        Description:
        Enumerate the latest Monthly Update for Windows Server 2012 R2 / Windows 8.1 x64

    .EXAMPLE
        Get-LatestUpdate -WindowsVersion Windows8 -SearchString 'Monthly Quality Rollup.*x86'
    
        Description:
        Enumerate the latest Monthly Update for Windows 8.1 x86

    .EXAMPLE
        Get-LatestUpdate -WindowsVersion Windows7 -SearchString 'Monthly Quality Rollup.*x86'
    
        Description:
        Enumerate the latest Monthly Update for Windows 7 x86
    #>
    [CmdletBinding(SupportsShouldProcess = $False)]
    Param(
        [Parameter(Mandatory = $False, HelpMessage = "Select the OS to search for updates")]
        [ValidateSet('Windows10', 'Windows8', 'Windows7')]
        [String] $WindowsVersion = "Windows10"
    )
    DynamicParam {
        #Create the RuntimeDefinedParameterDictionary
        $Dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        If ( $WindowsVersion -eq "Windows10") {
            $args = @{
                Name         = "Build"
                Type         = [String]
                ValidateSet  = @('17133', '16299', '15063', '14393', '10586', '10240')
                HelpMessage  = "Provide a Windows 10 build number"
                DPDictionary = $Dictionary
            }
            New-DynamicParam @args

            $args = @{
                Name         = "SearchString"
                Type         = [String]
                ValidateSet  = @('Cumulative.*x64', 'Cumulative.*Server.*x64', 'Cumulative.*x86')
                HelpMessage  = "Search query string."
                DPDictionary = $Dictionary
            }
            New-DynamicParam @args
        }
        If ( ($WindowsVersion -eq "Windows8") -or ($WindowsVersion -eq "Windows7") ) {
            $args = @{
                Name         = "SearchString"
                Type         = [String]
                ValidateSet  = @('Monthly Quality Rollup.*x64', 'Monthly Quality Rollup.*x86')
                HelpMessage  = "Search query string."
                DPDictionary = $Dictionary
            }
            New-DynamicParam @args
        }
        #return RuntimeDefinedParameterDictionary
        Write-Output $Dictionary
    }
    Begin {
        #Get common parameters, pick out bound parameters not in that set
        Function _temp { [cmdletbinding()] param() }
        $BoundKeys = $PSBoundParameters.keys | Where-Object { (Get-Command _temp | Select-Object -ExpandProperty parameters).Keys -notcontains $_}
        ForEach ($param in $BoundKeys) {
            If (-not ( Get-Variable -name $param -scope 0 -ErrorAction SilentlyContinue ) ) {
                New-Variable -Name $Param -Value $PSBoundParameters.$param
                Write-Verbose "Adding variable for dynamic parameter '$param' with value '$($PSBoundParameters.$param)'"
            }
        }
        
        Switch ( $WindowsVersion ) {
            "Windows10" {
                [String] $StartKB = 'https://support.microsoft.com/app/content/api/content/asset/en-us/4000816'
                If ( $Null -eq $SearchString ) { $SearchString = "Cumulative.*x64" }
            }
            "Windows8" {
                [String] $StartKB = 'https://support.microsoft.com/app/content/api/content/asset/en-us/4010477'
                [String] $Build = 'Monthly Rollup'
                If ( $Null -eq $SearchString ) { $SearchString = 'Monthly Quality Rollup.*x64' }
            }
            "Windows7" {
                [String] $StartKB = 'https://support.microsoft.com/app/content/api/content/asset/en-us/4009472'
                [String] $Build = 'Monthly Rollup'
                If ( $Null -eq $SearchString ) { $SearchString = 'Monthly Quality Rollup.*x64' }
            }
        }
        Write-Verbose "Check updates for $Build $SearchString"
    }
    Process {
        #region Find the KB Article Number
        Write-Verbose "Downloading $StartKB to retrieve the list of updates."
        $kbID = (Invoke-WebRequest -Uri $StartKB).Content |
            ConvertFrom-Json |
            Select-Object -ExpandProperty Links |
            Where-Object level -eq 2 |
            Where-Object text -match $Build |
            # Select-LatestUpdate |
        Select-Object -First 1
        If ( $Null -eq $kbID ) { Write-Warning -Message "kbID is Null. Unable to read from the KB from the JSON." }
        #endregion

        #region get the download link from Windows Update
        $kb = $kbID.articleID
        Write-Verbose "Found ID: KB$($kbID.articleID)"
        $kbObj = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=KB$($kbID.articleID)"

        # Write warnings if we can't read values
        If ( $Null -eq $kbObj ) { Write-Warning -Message "kbObj is Null. Unable to read KB details from the Catalog." }
        If ( $Null -eq $kbObj.InputFields ) { Write-Warning -Message "kbObj.InputFields is Null. Unable to read button details from the Catalog KB page." }
        #endregion

        #region Parse the available KB IDs
        $availableKbIDs = $kbObj.InputFields | 
            Where-Object { $_.Type -eq 'Button' -and $_.Value -eq 'Download' } | 
            Select-Object -ExpandProperty ID
        Write-Verbose "Ids found:"
        ForEach ( $id in $availableKbIDs ) {
            "`t$($id | Out-String)" | Write-Verbose
        }
        #endregion

        #region Invoke-WebRequest on PowerShell Core doesn't return innerText
        # (Same as Invoke-WebRequest -UseBasicParsing on Windows PS)
        If ( Test-PSCore ) {
            Write-Verbose "Using outerHTML. Parsing KB notes"
            $kbIDs = $kbObj.Links | 
                Where-Object ID -match '_link' |
                Where-Object outerHTML -match $SearchString |
                ForEach-Object { $_.Id.Replace('_link', '') } |
                Where-Object { $_ -in $availableKbIDs }
        }
        Else {
            Write-Verbose "innerText found. Parsing KB notes"
            $kbIDs = $kbObj.Links | 
                Where-Object ID -match '_link' |
                Where-Object innerText -match $SearchString |
                ForEach-Object { $_.Id.Replace('_link', '') } |
                Where-Object { $_ -in $availableKbIDs }
        }
        #endregion

        #region Read KB details
        $urls = @()
        ForEach ( $kbID in $kbIDs ) {
            Write-Verbose "Download $kbID"
            $post = @{ size = 0; updateID = $kbID; uidInfo = $kbID } | ConvertTo-Json -Compress
            $postBody = @{ updateIDs = "[$post]" } 
            $urls += Invoke-WebRequest -Uri 'http://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $postBody |
                Select-Object -ExpandProperty Content |
                Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" | 
                ForEach-Object { $_.matches.value }
        }
        #endregion

        #region Select the update names
        If ( Test-PSCore ) {
            # Updated for PowerShell Core
            $notes = ([regex]'(?<note>\d{4}-\d{2}.*\(KB\d{7}\))').match($kbObj.RawContent).Value
        }
        Else {
            # Original code for Windows PowerShell
            $notes = $kbObj.ParsedHtml.body.getElementsByTagName('a') | ForEach-Object InnerText | Where-Object { $_ -match $SearchString }
        }
        #endregion

        #region Build the output array
        [int] $i = 0; $output = @()
        ForEach ( $url in $urls ) {
            $item = New-Object PSObject
            $item | Add-Member -type NoteProperty -Name 'KB' -Value "KB$Kb"
            If ( $notes.Count -eq 1 ) {
                $item | Add-Member -type NoteProperty -Name 'Note' -Value $notes
            }
            Else {
                $item | Add-Member -type NoteProperty -Name 'Note' -Value $notes[$i]
            }
            $item | Add-Member -type NoteProperty -Name 'URL' -Value $url
            $output += $item
            $i = $i + 1
        }
        #endregion
    }
    End {
        # Write the URLs list to the pipeline
        Write-Output $output
    }
}
