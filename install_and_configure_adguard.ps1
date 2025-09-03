#on vérifie si firefox est installé, sinon on l'installe, puis on le configure

write-host " ==========================="
write-host " | FIREFOX CONFIGURATOR V1 |"
write-host " ==========================="

#Redémarrer powershell en x64 - correctif de bug avec NSIS. A enlever/commenter si converti en exe avec ps2exe
If (!([Environment]::Is64BitProcess)){
    if([Environment]::Is64BitOperatingSystem){
        Write-Output "Running 32 bit Powershell on 64 bit OS, restarting as 64 bit process..."
        #$arguments = "-NoProfile -ExecutionPolicy ByPass -WindowStyle Hidden -File `"" + $myinvocation.mycommand.definition + "`""
        $arguments = "-NoProfile -ExecutionPolicy ByPass -File `"" + $myinvocation.mycommand.definition + "`""
        $path = (Join-Path $Env:SystemRoot -ChildPath "\sysnative\WindowsPowerShell\v1.0\powershell.exe")
        Start-Process $path -ArgumentList $arguments -wait
        Write-Output "finished x64 version of PS"
        Exit
    }else{
        Write-Output "Running 32 bit Powershell on 32 bit OS"
    }
}

#Auto-élévation du script si lancé en non-admin. A enlever/commenter si converti en exe avec ps2exe
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
 if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
  $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
  Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
  Exit
 }
}

$ErrorActionPreference = "silentlycontinue"

#dns adulte
$DNS0="https://dns.adguard.com/dns-query"
$DNSR0="1.1.1.2"

#dns enfant
$DNS1="https://dns-family.adguard.com/dns-query"
$DNSR1="1.1.1.3"

#dns type
$DNST0="ADULTE"
$DNST1="ENFANT"

#creation variable $scriptDir
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript")
{ $ScriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition }
else
{ $ScriptPath = Split-Path -Parent -Path ([Environment]::GetCommandLineArgs()[0])
if (!$ScriptPath){ $ScriptPath = "." } }

$scriptDir = if (-not $PSScriptRoot) { Split-Path -Parent (Convert-Path ([environment]::GetCommandLineArgs()[0])) } else { $PSScriptRoot }

$configFILE = "$scriptDir\settings.ini"

#création de settings.ini s'il n'existe pas
if (!(Test-Path $configFILE)) {

$ini=@"
[General]
;version du script
version=1.0
;type 0 dns adulte, type 1 dns enfant
type=0

"@

$ini | set-content $configFILE

}

#récupération des paramètres du fichier ini
Get-Content $configFILE | ForEach-Object -Begin {$settings=@{}} -Process {$store = [regex]::split($_,'='); if(($store[0].CompareTo("") -ne 0) -and ($store[0].StartsWith("[") -ne $True) -and ($store[0].StartsWith("#") -ne $True)) {$settings.Add($store[0], $store[1])}}

[string]$version=$settings.Get_Item("version")
[string]$type=$settings.Get_Item("type")

#paramétrage du dns
switch ($type)
{
    "0" { $DNS=$DNS0 ; $DNSR=$DNSR0 ; $DNST=$DNST0 }
    "1" { $DNS=$DNS1 ; $DNSR=$DNSR1 ; $DNST=$DNST1 }
    Default { $DNS=$DNS0 ; $DNSR=$DNSR0 ; $DNST=$DNST0 }
}

#configuration utf8
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False

#récupération du dossier de Firefox
$PATH=(Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -match "firefox" } | Select-Object -Property DisplayName, InstallLocation).InstallLocation

#fonction de téléchargement
function Get-FileFromWeb {
    param (
        # Parameter help description
        [Parameter(Mandatory)]
        [string]$URL,
  
        # Parameter help description
        [Parameter(Mandatory)]
        [string]$File 
    )
    Begin {
        function Show-Progress {
            param (
                # Enter total value
                [Parameter(Mandatory)]
                [Single]$TotalValue,
        
                # Enter current value
                [Parameter(Mandatory)]
                [Single]$CurrentValue,
        
                # Enter custom progresstext
                [Parameter(Mandatory)]
                [string]$ProgressText,
        
                # Enter value suffix
                [Parameter()]
                [string]$ValueSuffix,
        
                # Enter bar lengh suffix
                [Parameter()]
                [int]$BarSize = 40,

                # show complete bar
                [Parameter()]
                [switch]$Complete
            )
            
            # calc %
            $percent = $CurrentValue / $TotalValue
            $percentComplete = $percent * 100
            if ($ValueSuffix) {
                $ValueSuffix = " $ValueSuffix" # add space in front
            }
            if ($psISE) {
                Write-Progress "$ProgressText $CurrentValue$ValueSuffix de $TotalValue$ValueSuffix" -id 0 -percentComplete $percentComplete            
            }
            else {
                # build progressbar with string function
                $curBarSize = $BarSize * $percent
                $progbar = ""
                $progbar = $progbar.PadRight($curBarSize,[char]9608)
                $progbar = $progbar.PadRight($BarSize,[char]9617)
        
                if (!$Complete.IsPresent) {
                    Write-Host -NoNewLine "`r$ProgressText $progbar [ $($CurrentValue.ToString("#.###").PadLeft($TotalValue.ToString("#.###").Length))$ValueSuffix / $($TotalValue.ToString("#.###"))$ValueSuffix ] $($percentComplete.ToString("##0.00").PadLeft(6)) % effectués"
                }
                else {
                    Write-Host -NoNewLine "`r$ProgressText $progbar [ $($TotalValue.ToString("#.###").PadLeft($TotalValue.ToString("#.###").Length))$ValueSuffix / $($TotalValue.ToString("#.###"))$ValueSuffix ] $($percentComplete.ToString("##0.00").PadLeft(6)) % effectués"                    
                }                
            }   
        }
    }
    Process {
        try {
            $storeEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Stop'
        
            # invoke request
            $request = [System.Net.HttpWebRequest]::Create($URL)
            $response = $request.GetResponse()
  
            if ($response.StatusCode -eq 401 -or $response.StatusCode -eq 403 -or $response.StatusCode -eq 404) {
                throw "Remote file either doesn't exist, is unauthorized, or is forbidden for '$URL'."
            }
  
            if($File -match '^\.\\') {
                $File = Join-Path (Get-Location -PSProvider "FileSystem") ($File -Split '^\.')[1]
            }
            
            if($File -and !(Split-Path $File)) {
                $File = Join-Path (Get-Location -PSProvider "FileSystem") $File
            }

            if ($File) {
                $fileDirectory = $([System.IO.Path]::GetDirectoryName($File))
                if (!(Test-Path($fileDirectory))) {
                    [System.IO.Directory]::CreateDirectory($fileDirectory) | Out-Null
                }
            }

            [long]$fullSize = $response.ContentLength
            $fullSizeMB = $fullSize / 1024 / 1024
  
            # define buffer
            [byte[]]$buffer = new-object byte[] 1048576
            [long]$total = [long]$count = 0
  
            # create reader / writer
            $reader = $response.GetResponseStream()
            $writer = new-object System.IO.FileStream $File, "Create"
  
            # start download
            $finalBarCount = 0 #show final bar only one time
            do {
          
                $count = $reader.Read($buffer, 0, $buffer.Length)
          
                $writer.Write($buffer, 0, $count)
              
                $total += $count
                $totalMB = $total / 1024 / 1024
          
                if ($fullSize -gt 0) {
                    Show-Progress -TotalValue $fullSizeMB -CurrentValue $totalMB -ProgressText "Téléchargement: $($File.Name)" -ValueSuffix "MB"
                }

                if ($total -eq $fullSize -and $count -eq 0 -and $finalBarCount -eq 0) {
                    Show-Progress -TotalValue $fullSizeMB -CurrentValue $totalMB -ProgressText "Téléchargement: $($File.Name)" -ValueSuffix "MB" -Complete
                    $finalBarCount++
                    #Write-Host "$finalBarCount"
                }

            } while ($count -gt 0)
            write-host "`n"
        }
  
        catch {
        
            $ExeptionMsg = $_.Exception.Message
            Write-Host "Download breaks with error : $ExeptionMsg"
        }
  
        finally {
            # cleanup
            if ($reader) { $reader.Close() }
            if ($writer) { $writer.Flush(); $writer.Close() }
        
            $ErrorActionPreference = $storeEAP
            [GC]::Collect()
        }    
    }
}

if([string]::IsNullOrEmpty($PATH)) {

    write-host "`n`nFirefox n'est pas installé`n"
	
    #fichier local ou sauvegarder l'installeur
    $LOCFILE="$PSSCRIPTROOT\firefox_setup_fr.msi"

    #on supprime l'installeur s'il a plus de 30 jours
    Get-ChildItem "$PSSCRIPTROOT" -Recurse -File -Filter "firefox_setup_fr.msi" | Where CreationTime -lt (Get-Date).AddDays(-30)  | Remove-Item -Force
    
    #url pour le dernier installeur firefox, format exe
    #$URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=fr"
    
    #url pour le dernier installeur firefox, format msi
    $URL="https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=fr"

    if (!(Test-Path $LOCFILE)) {

	    #pas d'installeur disponible à côté du script, on le télécharge
        write-host "`nL'installeur de Firefox n'est pas présent, téléchargement depuis`n$URL`n`n"

        #Invoke-WebRequest $URL -OutFile $LOCFILE
        Get-FileFromWeb $URL $LOCFILE
    }

    write-host "`nInstallation de Firefox`n"

    Start-Process Msiexec.exe -Wait -ArgumentList "/i $LOCFILE /qn"
}
else {

    write-host "`nFirefox est déjà installé`n"

}

$PATH=(Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -match "firefox" } | Select-Object -Property DisplayName, InstallLocation).InstallLocation

write-host "`nNettoyage de la configuration de Firefox`n"

remove-item $PATH/defaults/pref/autoconfig.js -force
remove-item $PATH/distribution/policies.json -force
remove-item $PATH/firefox.cfg -force

write-host "`nConfiguration de Firefox en mode [$DNST]`n"
New-Item -ItemType Directory -Path $PATH/defaults/pref -force > $null
New-Item -ItemType Directory -Path $PATH/distribution -force > $null

$STRING = @'
//
pref("general.config.sandbox_enabled", false);
pref("general.config.filename", "firefox.cfg");
pref("general.config.obscure_value", 0);
'@

$FILE="$PATH/defaults/pref/autoconfig.js"
[System.IO.File]::WriteAllLines($FILE, $STRING, $Utf8NoBomEncoding)

$STRING = @"
//the first line is always a comment
pref(`"network.trr.mode`", 3);
pref(`"network.trr.uri`", `"$DNS`");
pref(`"network.trr.custom_uri`", `"$DNS`");
pref(`"network.trr.bootstrapAddress`", `"$DNSR`");
pref(`"network.trr.default_provider_uri`", `"$DNS`");
pref(`"extensions.autoDisableScopes`", 0);
pref(`"browser.aboutConfig.showWarning`", false);
pref(`"browser.startup.homepage`", `"https://www.google.fr`");
pref(`"startup.homepage_welcome_url`", `"https://www.google.fr`");
pref(`"startup.homepage_override_url`", `"https://www.google.fr`");
pref(`"browser.shell.checkDefaultBrowser`", false);
pref(`"extensions.htmlaboutaddons.recommendations.enabled`", false);
pref(`"app.update.silent`", true);
pref(`"browser.messaging-system.whatsNewPanel.enabled`", false);
pref(`"privacy.trackingprotection.enabled`", true);
pref(`"privacy.firstparty.isolate`", true);
pref(`"privacy.donottrackheader.enabled`", true);
pref(`"privacy.globalprivacycontrol.enabled`", true);
pref(`"privacy.globalprivacycontrol.functionality.enabled`", true);
pref(`"toolkit.telemetry.archive.enabled`", false);
pref(`"toolkit.telemetry.enabled`", false);
pref(`"toolkit.telemetry.rejected`", true);
pref(`"toolkit.telemetry.unified`", false);
pref(`"toolkit.telemetry.unifiedIsOptIn`", false);
pref(`"toolkit.telemetry.prompted`", 2);
pref(`"toolkit.telemetry.rejected`", true);
pref(`"datareporting.policy.dataSubmissionEnabled`", false);
pref(`"datareporting.healthreport.service.enabled`", false);
pref(`"datareporting.healthreport.uploadEnabled`", false);
pref(`"app.shield.optoutstudies.enabled`", false);
pref(`"browser.urlbar.suggest.pocket`", false);
pref(`"browser.newtabpage.activity-stream.showSponsoredTopSites`", false);
pref(`"browser.newtabpage.activity-stream.system.showSponsored`", false);
pref(`"browser.newtabpage.activity-stream.showSponsored`", false);
pref(`"extensions.pocket.enabled`", false);
pref(`"browser.newtabpage.activity-stream.feeds.section.topstories`", false);
pref(`"network.dns.echconfig.enabled`", true);
pref(`"network.dns.http3_echconfig.enabled`", true);
pref(`"browser.toolbars.bookmarks.visibility`", `"always`");
pref(`"media.ffmpeg.vaapi.enabled`",true);
pref(`"media.ffvpx.enabled`",false);
pref(`"media.rdd-vpx.enabled`",false);
pref(`"media.navigator.mediadatadecoder_vpx_enabled`",true);
pref(`"image.webp`",false);
pref(`"browser.download.viewableInternally.typeWasRegistered.webp`",false);
pref(`"drm`",true);
pref(`"sidebar.visibility`", `"hide-sidebar`");
pref(`"sidebar.revamp`", false);
pref(`"signon.rememberSignons`", false);
pref(`"browser.translations.automaticallyPopup`", false);
pref(`"browser.startup.page`", 3);
pref(`"browser.shell.checkDefaultBrowser`", true);
pref(`"browser.uiCustomization.state`", '{`"placements`":{`"widget-overflow-fixed-list`":[],`"unified-extensions-area`":[`"jid1-mnnxcxisbpnsxq_jetpack-browser-action`",`"newtaboverride_agenedia_com-browser-action`",`"gmailellcheckersimple_durasoft-browser-action`",`"dontfuckwithpaste_raim_ist-browser-action`",`"gdpr_cavi_au_dk-browser-action`",`"chrome-gnome-shell_gnome_org-browser-action`",`"netflixprime_autoskip_io-browser-action`",`"plasma-browser-integration_kde_org-browser-action`",`"support_netflux_me-browser-action`",`"_a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7_-browser-action`",`"_74145f27-f039-47ce-a470-a662b129930a_-browser-action`"],`"nav-bar`":[`"back-button`",`"forward-button`",`"stop-reload-button`",`"vertical-spacer`",`"home-button`",`"new-tab-button`",`"urlbar-container`",`"downloads-button`",`"history-panelmenu`",`"print-button`",`"preferences-button`",`"unified-extensions-button`",`"ublock0_raymondhill_net-browser-action`",`"78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action`"],`"toolbar-menubar`":[`"menubar-items`"],`"TabsToolbar`":[`"firefox-view-button`",`"tabbrowser-tabs`",`"alltabs-button`"],`"vertical-tabs`":[],`"PersonalToolbar`":[`"import-button`",`"personal-bookmarks`"]},`"seen`":[`"developer-button`",`"screenshot-button`",`"gmailellcheckersimple_durasoft-browser-action`",`"newtaboverride_agenedia_com-browser-action`",`"dontfuckwithpaste_raim_ist-browser-action`",`"gdpr_cavi_au_dk-browser-action`",`"chrome-gnome-shell_gnome_org-browser-action`",`"netflixprime_autoskip_io-browser-action`",`"plasma-browser-integration_kde_org-browser-action`",`"support_netflux_me-browser-action`",`"_a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7_-browser-action`",`"_74145f27-f039-47ce-a470-a662b129930a_-browser-action`",`"jid1-mnnxcxisbpnsxq_jetpack-browser-action`",`"ublock0_raymondhill_net-browser-action`",`"78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action`"],`"dirtyAreaCache`":[`"nav-bar`",`"vertical-tabs`",`"PersonalToolbar`",`"unified-extensions-area`",`"TabsToolbar`"],`"currentVersion`":23,`"newElementCount`":3}');
pref(`"browser.tabs.groups.smart.enabled`", false);
pref(`"browser.ml.chat.enabled`", false);
pref(`"browser.ml.chat.shortcuts`", false);
pref(`"browser.ml.chat.sidebar`", false);
pref(`"browser.ml.chat.page`", false);
"@

$FILE="$PATH/firefox.cfg"
[System.IO.File]::WriteAllLines($FILE, $STRING, $Utf8NoBomEncoding)

$STRING = @'
{
  "policies": {
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      },
      "{26b743a8-b1b0-4b8c-a51e-0fc3797727a8}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/google-consent-dialog-remover/latest.xpi"
      },
      "DontFuckWithPaste@raim.ist": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/don-t-fuck-with-paste/latest.xpi"
      },
      "jid1-MnnxcxisBPnSXQ@jetpack": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi"
      },
      "newtaboverride@agenedia.com": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/new-tab-override/latest.xpi"
      },
      "pure-url@jetpack": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/pure-url/latest.xpi"
      },
      "gdpr@cavi.au.dk": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/consent-o-matic/latest.xpi"
      },
      "magnolia_limited_permissions@12.34": {
        "installation_mode": "normal_installed",
        "install_url": "https://gitflic.ru/project/magnolia1234/bpc_uploads/blob/raw?file=bypass_paywalls_clean-3.8.8.0-custom.xpi"
      },
      "{74145f27-f039-47ce-a470-a662b129930a}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi"
      },
      "dont-track-me-google@robwu.nl": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/dont-track-me-google1/latest.xpi"
      },
      "gmailellcheckersimple@durasoft": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/gmail-checker-simple/latest.xpi"
      },
      "{abea9bb3-7bd0-48bc-88b1-39f0560744d6}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/google-search-fixer-refreshed/latest.xpi"
      },
      "{00000f2a-7cde-4f20-83ed-434fcb420d71}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/imagus/latest.xpi"
      },
      "support@netflux.me": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/netflux/latest.xpi"
      },
      "plasma-browser-integration@kde.org": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/plasma-integration/latest.xpi"
      },
      "chrome-gnome-shell@gnome.org": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/gnome-shell-integration/latest.xpi"
      },
      "{7c73b62b-7ac7-4292-81a7-c15746af0972}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/google-search-display-icon/latest.xpi"
      },
      "{a6c4a591-f1b2-4f03-b3ff-767e5bedf4e7}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/user-agent-string-switcher/latest.xpi"
      },
      "NetflixPrime@Autoskip.io": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/netflix-prime-auto-skip/latest.xpi"
      },
      "78272b6fa58f4a1abaac99321d503a20@proton.me": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/proton-pass/latest.xpi"
      }
    }
  }
}
'@

$FILE="$PATH/distribution/policies.json"
[System.IO.File]::WriteAllLines($FILE, $STRING, $Utf8NoBomEncoding)

write-host "`nFirefox est prêt, vous pouvez le lancer.`n"

Timeout /T 5
