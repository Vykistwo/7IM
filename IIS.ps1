adm-user
xyyh72J4KobXTm
#
        function StopIndividualSite($Site) {            
            $SiteStatus = (Get-WebsiteState -Name $Site).value
            if ($SiteStatus -ne "Stopped") {
                $global:LogMessage += "Stopping site $Site"
                Try {
                    Stop-WebSite -Name $Site -ErrorAction Stop
                    Start-Sleep 1
                }
                Catch {
                    $global:LogMessage += "Error stopping site $Site"
                    $issuesCount++;
                    Continue
                }

                $SiteStatus = (Get-WebsiteState -Name $Site).value
                if ($SiteStatus -ne "Stopped") {
                    $global:LogMessage += "`tSite $Site did not stop"
                    $issuesCount++;
                    break
                }
                else {
                    $global:LogMessage += "`tSite $Site stopped"
                }
            }
            else {
                $global:LogMessage += "Site $Site already stopped"
            } 

            return;
        }
