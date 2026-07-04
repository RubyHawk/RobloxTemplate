[CmdletBinding()]
param(
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

$root = Split-Path -Parent $PSScriptRoot
$logDirectory = Join-Path $root "build"
$taskLogDirectory = Join-Path $logDirectory "app-tasks"
$logFile = Join-Path $logDirectory "launcher.log"
New-Item -ItemType Directory -Path $logDirectory, $taskLogDirectory -Force | Out-Null

function Write-LauncherLog([string]$Message) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Get-CurrentBranch {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return "Git not found"
    }
    $branch = (& git -C $root branch --show-current 2>$null).Trim()
    if (-not $branch) {
        return "Unknown branch"
    }
    return $branch
}

function Get-CurrentProject {
    $projectFile = Join-Path $root "default.project.json"
    if (-not (Test-Path $projectFile -PathType Leaf)) {
        return "Project file missing"
    }
    return [string]((Get-Content -LiteralPath $projectFile -Raw | ConvertFrom-Json).name)
}

function Show-LauncherMessage([string]$Message, [string]$Title, [System.Windows.MessageBoxImage]$Icon) {
    [System.Windows.MessageBox]::Show($window, $Message, $Title, [System.Windows.MessageBoxButton]::OK, $Icon) | Out-Null
}

function Format-CommandArgument([string]$Value) {
    if ($Value -match '^[A-Za-z0-9_\-.:\\/]+$') {
        return $Value
    }
    return '"' + $Value + '"'
}

function Start-CommandWindow([string]$FileName, [string[]]$ArgumentValues = @()) {
    $commandFile = Join-Path $root $FileName
    $argumentText = ""
    foreach ($value in $ArgumentValues) {
        $argumentText = $argumentText + " " + (Format-CommandArgument $value)
    }
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /c `"`"$commandFile`"$argumentText`"" -WorkingDirectory $root -PassThru
    Write-LauncherLog "Started $FileName$argumentText as process $($process.Id)."
}

function Get-DownloadsFolder {
    try {
        $shell = New-Object -ComObject Shell.Application
        $downloads = $shell.NameSpace("shell:Downloads")
        if ($downloads -and $downloads.Self) {
            $downloadsPath = [string]$downloads.Self.Path
            if ($downloadsPath -and (Test-Path -LiteralPath $downloadsPath -PathType Container)) {
                return $downloadsPath
            }
        }
    }
    catch {
        Write-LauncherLog "Downloads folder lookup failed: $($_.Exception.Message)"
    }
    if ($env:USERPROFILE) {
        $fallback = Join-Path $env:USERPROFILE "Downloads"
        if (Test-Path -LiteralPath $fallback -PathType Container) {
            return $fallback
        }
    }
    return $null
}

function Find-NewestFigmaPatch {
    $candidates = @()
    foreach ($folder in @((Get-DownloadsFolder), $root)) {
        if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
            $candidates += @(Get-ChildItem -LiteralPath $folder -Filter "*.figma-patch.json" -File -ErrorAction SilentlyContinue)
        }
    }
    return $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-FriendlyAge([datetime]$Timestamp) {
    $elapsed = (Get-Date) - $Timestamp
    if ($elapsed.TotalMinutes -lt 1) { return "just now" }
    if ($elapsed.TotalMinutes -lt 60) { return "$([int][math]::Floor($elapsed.TotalMinutes)) min ago" }
    if ($elapsed.TotalHours -lt 24) { return "$([int][math]::Floor($elapsed.TotalHours)) hours ago" }
    return "$([int][math]::Floor($elapsed.TotalDays)) days ago"
}

function Get-PresetDisplayName([string]$FolderName) {
    if ($FolderName -eq "rpg") { return "RPG" }
    return (Get-Culture).TextInfo.ToTitleCase(($FolderName -replace '[-_]+', ' '))
}

$script:darkTitleBarReady = $false
try {
    Add-Type -Namespace RobloxTemplateApp -Name NativeMethods -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);' -ErrorAction Stop
    $script:darkTitleBarReady = $true
}
catch {
    Write-LauncherLog "Dark title bar helper unavailable: $($_.Exception.Message)"
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Roblox Template" Width="1010" Height="720"
        WindowStartupLocation="CenterScreen" MinWidth="940" MinHeight="620"
        Background="#0B1020" FontFamily="Segoe UI">
    <DockPanel>
        <Border DockPanel.Dock="Left" Width="230" Background="#070C19" BorderBrush="#1C2A47" BorderThickness="0,0,1,0">
            <DockPanel>
                <StackPanel DockPanel.Dock="Top" Margin="22,26,22,8">
                    <TextBlock Text="ROBLOX TEMPLATE" Foreground="#60A5FA" FontSize="12" FontWeight="Bold"/>
                    <TextBlock Text="Control Center" Foreground="White" FontSize="21" FontWeight="Bold" Margin="0,4,0,0"/>
                </StackPanel>
                <TextBlock x:Name="SidebarInfo" DockPanel.Dock="Bottom" Margin="22,0,22,18"
                           Foreground="#5E6F92" FontSize="11" TextWrapping="Wrap"/>
                <StackPanel Margin="12,16,12,0">
                    <Button x:Name="PlayNavButton" Style="{DynamicResource NavButton}" Content="Play and test" Margin="0,0,0,4"/>
                    <Button x:Name="FigmaNavButton" Style="{DynamicResource NavButton}" Content="Figma design" Margin="0,0,0,4"/>
                    <Button x:Name="ToolsNavButton" Style="{DynamicResource NavButton}" Content="Build and tools"/>
                </StackPanel>
            </DockPanel>
        </Border>

        <Border DockPanel.Dock="Bottom" Background="#0A1122" BorderBrush="#1C2A47" BorderThickness="0,1,0,0" Padding="18,10">
            <DockPanel>
                <Button x:Name="OutputToggle" DockPanel.Dock="Right" Style="{DynamicResource SmallButton}" Content="Show activity" Margin="8,0,0,0"/>
                <Button x:Name="StopTaskButton" DockPanel.Dock="Right" Style="{DynamicResource SmallButton}" Content="Stop" Visibility="Collapsed" Margin="8,0,0,0"/>
                <TextBlock x:Name="ActivityStatus" Foreground="#C9D7EE" FontSize="13" VerticalAlignment="Center"
                           TextWrapping="Wrap" Text="Ready."/>
            </DockPanel>
        </Border>

        <Border x:Name="OutputPanel" DockPanel.Dock="Bottom" Height="216" Background="#080D1A"
                BorderBrush="#1C2A47" BorderThickness="0,1,0,0" Padding="14,10" Visibility="Collapsed">
            <TextBox x:Name="OutputBox" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                     VerticalContentAlignment="Stretch" FontFamily="Consolas" FontSize="12"
                     Background="#080D1A" BorderBrush="#080D1A" Foreground="#C7D4EC" Padding="4,2"/>
        </Border>

        <ScrollViewer VerticalScrollBarVisibility="Auto">
            <Grid Margin="34,26,34,24">
                <StackPanel x:Name="PlayPage">
                    <TextBlock Text="Play and test" Foreground="White" FontSize="26" FontWeight="Bold"/>
                    <TextBlock Text="Everything here reuses the two permanent Roblox experiences. Nothing creates a new one."
                               Foreground="#AAB8D4" FontSize="14" Margin="0,6,0,0" TextWrapping="Wrap"/>

                    <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,18,0,0">
                        <StackPanel>
                            <TextBlock Text="SHARED TEST EXPERIENCE" FontWeight="Bold" Foreground="#93C5FD" FontSize="12"/>
                            <TextBlock Text="Builds the selected recipe and opens the player-test experience with live saved data."
                                       Foreground="#AAB8D4" Margin="0,5,0,10" TextWrapping="Wrap"/>
                            <DockPanel>
                                <TextBlock DockPanel.Dock="Left" Text="Game recipe" Foreground="#8FA1BF" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <ComboBox x:Name="RecipeBox"/>
                            </DockPanel>
                            <Button x:Name="PlayableButton" Style="{DynamicResource PrimaryButton}" Margin="0,12,0,0">
                                <StackPanel>
                                    <TextBlock Text="OPEN SHARED TEST EXPERIENCE" FontSize="16" FontWeight="Bold"/>
                                    <TextBlock Text="Runs in its own session window with Studio and Rojo. Keep that window open while playing."
                                               Foreground="#DCEAFF" FontSize="12" FontWeight="Normal" Margin="0,5,0,0" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Button>
                        </StackPanel>
                    </Border>

                    <Grid Margin="0,14,0,0">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="12"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button x:Name="TemplateButton" Grid.Column="0" Style="{DynamicResource SecondaryButton}">
                            <StackPanel>
                                <TextBlock Text="TEMPLATE WORKBENCH" FontSize="15" FontWeight="Bold"/>
                                <TextBlock Text="Author UI on mock data in its own session window."
                                           Foreground="#B9C7DE" FontSize="12" FontWeight="Normal" Margin="0,5,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Button>
                        <Button x:Name="DesignerButton" Grid.Column="2" Style="{DynamicResource SecondaryButton}">
                            <StackPanel>
                                <TextBlock Text="GAME DESIGNER" FontSize="15" FontWeight="Bold"/>
                                <TextBlock Text="Pick a UI pack, currencies, and systems in a form."
                                           Foreground="#B9C7DE" FontSize="12" FontWeight="Normal" Margin="0,5,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Button>
                    </Grid>
                </StackPanel>

                <StackPanel x:Name="FigmaPage" Visibility="Collapsed">
                    <TextBlock Text="Figma design" Foreground="White" FontSize="26" FontWeight="Bold"/>
                    <TextBlock Text="Edit a UI pack visually in Figma, export a patch with the Roblox UI Bridge plugin, then apply it here."
                               Foreground="#AAB8D4" FontSize="14" Margin="0,6,0,0" TextWrapping="Wrap"/>

                    <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,18,0,0">
                        <StackPanel>
                            <TextBlock Text="APPLY AN EXPORTED DESIGN" FontWeight="Bold" Foreground="#93C5FD" FontSize="12"/>
                            <TextBlock Text="Only the selected pack changes; every layer path and class is validated first."
                                       Foreground="#AAB8D4" Margin="0,5,0,10" TextWrapping="Wrap"/>
                            <DockPanel>
                                <TextBlock DockPanel.Dock="Left" Text="UI pack" Foreground="#8FA1BF" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <ComboBox x:Name="FigmaPresetBox"/>
                            </DockPanel>
                            <Grid Margin="0,10,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="8"/>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="8"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox x:Name="PatchBox" Height="36"/>
                                <Button x:Name="RescanButton" Grid.Column="2" Style="{DynamicResource SmallButton}" Content="Newest export"/>
                                <Button x:Name="BrowseButton" Grid.Column="4" Style="{DynamicResource SmallButton}" Content="Browse..."/>
                            </Grid>
                            <TextBlock x:Name="PatchHint" Foreground="#8FA1BF" FontSize="12" Margin="0,7,0,0" TextWrapping="Wrap"/>
                            <Button x:Name="ApplyFigmaButton" Style="{DynamicResource PrimaryButton}" Margin="0,12,0,0">
                                <StackPanel>
                                    <TextBlock Text="APPLY FIGMA DESIGN" FontSize="16" FontWeight="Bold"/>
                                    <TextBlock Text="Updates the pack and rebuilds its playable files right here, with progress in the activity panel."
                                               Foreground="#DCEAFF" FontSize="12" FontWeight="Normal" Margin="0,5,0,0" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Button>
                        </StackPanel>
                    </Border>

                    <Border Background="#0E1626" BorderBrush="#263654" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,14,0,0">
                        <StackPanel>
                            <TextBlock Text="HOW THE ROUND TRIP WORKS" FontWeight="Bold" Foreground="#7E93BC" FontSize="12"/>
                            <TextBlock Foreground="#8FA1BF" FontSize="13" Margin="0,8,0,0" TextWrapping="Wrap"
                                       Text="1.  In Figma, run the Roblox UI Bridge plugin and import a pack's model files."/>
                            <TextBlock Foreground="#8FA1BF" FontSize="13" Margin="0,4,0,0" TextWrapping="Wrap"
                                       Text="2.  Edit layers freely, then click 'Export selected Roblox patch'."/>
                            <TextBlock Foreground="#8FA1BF" FontSize="13" Margin="0,4,0,0" TextWrapping="Wrap"
                                       Text="3.  Come back here - the newest export is already selected. One-time plugin setup is described in docs/FIGMA_UI.md."/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <StackPanel x:Name="ToolsPage" Visibility="Collapsed">
                    <TextBlock Text="Build and tools" Foreground="White" FontSize="26" FontWeight="Bold"/>
                    <TextBlock Text="Housekeeping tasks run inside this window; watch them in the activity panel below."
                               Foreground="#AAB8D4" FontSize="14" Margin="0,6,0,0" TextWrapping="Wrap"/>

                    <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,18,0,0">
                        <StackPanel>
                            <TextBlock Text="PROJECT HEALTH" FontWeight="Bold" Foreground="#93C5FD" FontSize="12"/>
                            <TextBlock Text="Verifies tools, formatting, linting, builds, and tests, then explains any problem in plain language."
                                       Foreground="#AAB8D4" Margin="0,5,0,10" TextWrapping="Wrap"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="12"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Button x:Name="RunChecksButton" Grid.Column="0" Style="{DynamicResource SmallButton}" Content="Run full project checks"/>
                                <Button x:Name="RepairSetupButton" Grid.Column="2" Style="{DynamicResource SmallButton}" Content="Repair / install setup"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,14,0,0">
                        <StackPanel>
                            <TextBlock Text="UI PACKAGES" FontWeight="Bold" Foreground="#93C5FD" FontSize="12"/>
                            <TextBlock Text="Builds the independent drag-and-drop .rbxm packages for every UI pack."
                                       Foreground="#AAB8D4" Margin="0,5,0,10" TextWrapping="Wrap"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="12"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Button x:Name="BuildPackButton" Grid.Column="0" Style="{DynamicResource SmallButton}" Content="Build UI packages"/>
                                <Button x:Name="OpenExportsButton" Grid.Column="2" Style="{DynamicResource SmallButton}" Content="Open exports folder"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,14,0,0">
                        <StackPanel>
                            <TextBlock Text="SHARED ICON LIBRARY" FontWeight="Bold" Foreground="#93C5FD" FontSize="12"/>
                            <TextBlock Text="Swap or disable shared UI icons and record their Roblox image mapping. Opens in its own window."
                                       Foreground="#AAB8D4" Margin="0,5,0,10" TextWrapping="Wrap"/>
                            <Button x:Name="IconsButton" Style="{DynamicResource SmallButton}" Content="Open icon library manager" HorizontalAlignment="Left" MinWidth="260"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>
        </ScrollViewer>
    </DockPanel>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$themePath = Join-Path $PSScriptRoot "app-theme.xaml"
if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
    throw "The shared app theme is missing: $themePath"
}
$themeStream = [System.IO.File]::OpenRead($themePath)
try {
    $window.Resources.MergedDictionaries.Add([System.Windows.Markup.XamlReader]::Load($themeStream))
}
finally {
    $themeStream.Dispose()
}

if ($script:darkTitleBarReady) {
    $window.Add_SourceInitialized({
        try {
            $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
            $enabled = 1
            [void][RobloxTemplateApp.NativeMethods]::DwmSetWindowAttribute($helper.Handle, 20, [ref]$enabled, 4)
            [void][RobloxTemplateApp.NativeMethods]::DwmSetWindowAttribute($helper.Handle, 19, [ref]$enabled, 4)
        }
        catch { }
    })
}

function Find-Control([string]$Name) {
    $control = $window.FindName($Name)
    if (-not $control) {
        throw "Launcher control is missing from the window: $Name"
    }
    return $control
}

$sidebarInfo = Find-Control "SidebarInfo"
$playNavButton = Find-Control "PlayNavButton"
$figmaNavButton = Find-Control "FigmaNavButton"
$toolsNavButton = Find-Control "ToolsNavButton"
$playPage = Find-Control "PlayPage"
$figmaPage = Find-Control "FigmaPage"
$toolsPage = Find-Control "ToolsPage"
$recipeBox = Find-Control "RecipeBox"
$playableButton = Find-Control "PlayableButton"
$templateButton = Find-Control "TemplateButton"
$designerButton = Find-Control "DesignerButton"
$figmaPresetBox = Find-Control "FigmaPresetBox"
$patchBox = Find-Control "PatchBox"
$patchHint = Find-Control "PatchHint"
$rescanButton = Find-Control "RescanButton"
$browseButton = Find-Control "BrowseButton"
$applyFigmaButton = Find-Control "ApplyFigmaButton"
$runChecksButton = Find-Control "RunChecksButton"
$repairSetupButton = Find-Control "RepairSetupButton"
$buildPackButton = Find-Control "BuildPackButton"
$openExportsButton = Find-Control "OpenExportsButton"
$iconsButton = Find-Control "IconsButton"
$activityStatus = Find-Control "ActivityStatus"
$stopTaskButton = Find-Control "StopTaskButton"
$outputToggle = Find-Control "OutputToggle"
$outputPanel = Find-Control "OutputPanel"
$outputBox = Find-Control "OutputBox"

$brushConverter = New-Object System.Windows.Media.BrushConverter
$navSelectedBrush = $brushConverter.ConvertFromString("#1B2942")
$navIdleForeground = $brushConverter.ConvertFromString("#C9D7EE")
$statusNeutralBrush = $brushConverter.ConvertFromString("#C9D7EE")
$statusSuccessBrush = $brushConverter.ConvertFromString("#34D399")
$statusErrorBrush = $brushConverter.ConvertFromString("#F87171")

$sidebarInfo.Text = "$(Get-CurrentProject)`nBranch: $(Get-CurrentBranch)"
Write-LauncherLog "Launcher opened on $(Get-CurrentBranch) | $(Get-CurrentProject)."

function Set-ActionStatus([string]$Message) {
    $activityStatus.Foreground = $statusNeutralBrush
    $activityStatus.Text = $Message
}

function Show-OutputPanel([bool]$Show) {
    if ($Show) {
        $outputPanel.Visibility = "Visible"
        $outputToggle.Content = "Hide activity"
    }
    else {
        $outputPanel.Visibility = "Collapsed"
        $outputToggle.Content = "Show activity"
    }
}

function Select-Page([string]$PageName) {
    $pages = @{ Play = $playPage; Figma = $figmaPage; Tools = $toolsPage }
    $buttons = @{ Play = $playNavButton; Figma = $figmaNavButton; Tools = $toolsNavButton }
    foreach ($key in @("Play", "Figma", "Tools")) {
        if ($key -eq $PageName) {
            $pages[$key].Visibility = "Visible"
            $buttons[$key].Background = $navSelectedBrush
            $buttons[$key].Foreground = [System.Windows.Media.Brushes]::White
        }
        else {
            $pages[$key].Visibility = "Collapsed"
            $buttons[$key].Background = [System.Windows.Media.Brushes]::Transparent
            $buttons[$key].Foreground = $navIdleForeground
        }
    }
}

# ---------------------------------------------------------------------------
# In-app task runner: short scripts run hidden with their output streamed
# into the activity panel. Long-running Studio/Rojo sessions stay in their
# own console windows because they must survive independently of this app.
# ---------------------------------------------------------------------------

$script:activeTask = $null
$taskButtons = @($applyFigmaButton, $runChecksButton, $repairSetupButton, $buildPackButton)

function Read-TaskFileTail([string]$Path, [long]$Position) {
    $result = @{ Text = ""; Position = $Position }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -gt $Position) {
            [void]$stream.Seek($Position, [System.IO.SeekOrigin]::Begin)
            $buffer = New-Object byte[] ([int]($stream.Length - $Position))
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            $result.Text = [System.Text.Encoding]::Default.GetString($buffer, 0, $bytesRead)
            $result.Position = $Position + $bytesRead
        }
    }
    finally {
        $stream.Dispose()
    }
    return $result
}

function Complete-ActiveTask {
    $task = $script:activeTask
    $taskTimer.Stop()
    $exitCode = -1
    try { $exitCode = $task.Process.ExitCode } catch { }
    if ($exitCode -eq 0) {
        $activityStatus.Foreground = $statusSuccessBrush
        $activityStatus.Text = "$($task.Name) finished successfully."
        $outputBox.AppendText("`r`n[done] $($task.Name) finished successfully.`r`n")
    }
    else {
        $activityStatus.Foreground = $statusErrorBrush
        $activityStatus.Text = "$($task.Name) failed (exit code $exitCode). Read the activity output for the reason."
        $outputBox.AppendText("`r`n[failed] Exit code $exitCode.`r`n")
        Show-OutputPanel $true
    }
    $outputBox.ScrollToEnd()
    $stopTaskButton.Visibility = "Collapsed"
    foreach ($button in $taskButtons) { $button.IsEnabled = $true }
    Write-LauncherLog "Task finished: $($task.Name) exit $exitCode"
    $script:activeTask = $null
}

function Update-ActiveTask {
    if (-not $script:activeTask) { return }
    $task = $script:activeTask
    foreach ($channel in @("Out", "Err")) {
        $read = Read-TaskFileTail $task."$($channel)File" $task."$($channel)Position"
        $task."$($channel)Position" = $read.Position
        if ($read.Text) {
            $outputBox.AppendText($read.Text)
            $outputBox.ScrollToEnd()
        }
    }
    if ($task.Process.HasExited) {
        $task.ExitTicks = $task.ExitTicks + 1
        if ($task.ExitTicks -ge 2) {
            Complete-ActiveTask
        }
    }
}

$taskTimer = New-Object System.Windows.Threading.DispatcherTimer
$taskTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$taskTimer.Add_Tick({ Update-ActiveTask })

function Start-LauncherTask([string]$Name, [string]$ScriptPath, [string[]]$ScriptArguments = @()) {
    if ($script:activeTask) {
        Show-LauncherMessage "Wait for '$($script:activeTask.Name)' to finish, or press Stop, before starting another task." "A task is already running" ([System.Windows.MessageBoxImage]::Warning)
        return
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeName = ($Name -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    $outFile = Join-Path $taskLogDirectory "$stamp-$safeName.out.log"
    $errFile = Join-Path $taskLogDirectory "$stamp-$safeName.err.log"
    $arguments = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $ScriptArguments
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru
    $script:activeTask = @{
        Name = $Name
        Process = $process
        OutFile = $outFile
        ErrFile = $errFile
        OutPosition = [long]0
        ErrPosition = [long]0
        ExitTicks = 0
    }
    $outputBox.Clear()
    $outputBox.AppendText("> $Name`r`n`r`n")
    Show-OutputPanel $true
    $activityStatus.Foreground = $statusNeutralBrush
    $activityStatus.Text = "Running: $Name ..."
    $stopTaskButton.Visibility = "Visible"
    foreach ($button in $taskButtons) { $button.IsEnabled = $false }
    $taskTimer.Start()
    Write-LauncherLog "Task started: $Name -> $ScriptPath $($ScriptArguments -join ' ')"
}

$stopTaskButton.Add_Click({
    if (-not $script:activeTask) { return }
    try {
        Start-Process -FilePath "taskkill.exe" -ArgumentList @("/PID", "$($script:activeTask.Process.Id)", "/T", "/F") -WindowStyle Hidden
        Set-ActionStatus "Stopping $($script:activeTask.Name) ..."
        Write-LauncherLog "Task stop requested: $($script:activeTask.Name)"
    }
    catch {
        Write-LauncherLog "Task stop failed: $($_.Exception.Message)"
    }
})

$outputToggle.Add_Click({ Show-OutputPanel ($outputPanel.Visibility -ne "Visible") })

# --- Play page -------------------------------------------------------------

$recipePresets = @{}
$recipeFiles = @(Get-ChildItem -LiteralPath (Join-Path $root "config-presets") -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($recipeFile in $recipeFiles) {
    $recipePreset = ""
    try {
        $recipeJson = Get-Content -LiteralPath $recipeFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($recipeJson.PSObject.Properties.Name -contains "preset") {
            $recipePreset = [string]$recipeJson.preset
        }
    }
    catch {
        Write-LauncherLog "Could not read recipe $($recipeFile.Name): $($_.Exception.Message)"
    }
    $recipePresets[$recipeFile.BaseName] = $recipePreset
    $recipeItem = [System.Windows.Controls.ComboBoxItem]::new()
    $recipeItem.Content = $recipeFile.BaseName
    $recipeItem.Tag = $recipeFile.FullName
    [void]$recipeBox.Items.Add($recipeItem)
}

$defaultRecipeName = ""
try {
    $experiencesConfig = Get-Content -LiteralPath (Join-Path $root "experiences.config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if (($experiencesConfig.PSObject.Properties.Name -contains "playerTest") -and
        ($experiencesConfig.playerTest.PSObject.Properties.Name -contains "defaultPreset")) {
        $defaultRecipeName = [string]$experiencesConfig.playerTest.defaultPreset
    }
}
catch {
    Write-LauncherLog "Could not read experiences.config.json: $($_.Exception.Message)"
}
if ($recipeBox.Items.Count -gt 0) {
    $recipeBox.SelectedIndex = 0
    for ($index = 0; $index -lt $recipeBox.Items.Count; $index++) {
        if ([string]$recipeBox.Items[$index].Content -eq $defaultRecipeName) {
            $recipeBox.SelectedIndex = $index
            break
        }
    }
}
else {
    $playableButton.IsEnabled = $false
    Set-ActionStatus "No recipes exist under config-presets, so the shared test experience is unavailable."
}

$playableButton.Add_Click({
    try {
        $selectedRecipe = $recipeBox.SelectedItem
        if (-not $selectedRecipe) {
            Show-LauncherMessage "Add a recipe file under config-presets first." "No recipe selected" ([System.Windows.MessageBoxImage]::Warning)
            return
        }
        Start-CommandWindow "SANDBOX.cmd" @("-RecipePath", [string]$selectedRecipe.Tag)
        Set-ActionStatus "Opening the shared test experience with the '$([string]$selectedRecipe.Content)' recipe. Keep its session window open while playing."
    }
    catch {
        Write-LauncherLog "Shared sandbox failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The launcher hit an unexpected error. Nothing was deleted.`n`nDetails were saved to build\launcher.log." "Could not open shared sandbox" ([System.Windows.MessageBoxImage]::Error)
    }
})

$templateButton.Add_Click({
    try {
        Start-CommandWindow "2_START.cmd"
        Set-ActionStatus "Opening the template workbench. Keep its session window open while editing."
    }
    catch {
        Write-LauncherLog "Template failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The launcher hit an unexpected error. Nothing was deleted.`n`nDetails were saved to build\launcher.log." "Could not open template" ([System.Windows.MessageBoxImage]::Error)
    }
})

$designerButton.Add_Click({
    Start-CommandWindow "5_GAME_DESIGNER.cmd"
    Set-ActionStatus "Opening the Game Designer window."
})

# --- Figma page ------------------------------------------------------------

$requiredModels = @("TemplateUI.model.json", "TemplateLoading.model.json", "StarterSignUI.model.json")
$presetRoot = Join-Path $root "src\ui\presets"
$presetFolders = @()
if (Test-Path -LiteralPath $presetRoot -PathType Container) {
    $presetFolders = @(Get-ChildItem -LiteralPath $presetRoot -Directory | Where-Object {
        $folder = $_.FullName
        @($requiredModels | Where-Object { -not (Test-Path -LiteralPath (Join-Path $folder $_) -PathType Leaf) }).Count -eq 0
    } | Sort-Object Name)
}
foreach ($presetFolder in $presetFolders) {
    $presetItem = [System.Windows.Controls.ComboBoxItem]::new()
    $presetItem.Content = Get-PresetDisplayName $presetFolder.Name
    $presetItem.Tag = $presetFolder.Name
    [void]$figmaPresetBox.Items.Add($presetItem)
}
if ($figmaPresetBox.Items.Count -gt 0) {
    $figmaPresetBox.SelectedIndex = 0
}
else {
    $applyFigmaButton.IsEnabled = $false
    $patchHint.Text = "No complete UI packs were found under src\ui\presets."
}

function Update-FigmaPackFromRecipe {
    $selectedRecipe = $recipeBox.SelectedItem
    if (-not $selectedRecipe) { return }
    $recipePreset = [string]$recipePresets[[string]$selectedRecipe.Content]
    if (-not $recipePreset) { return }
    for ($index = 0; $index -lt $figmaPresetBox.Items.Count; $index++) {
        if ([string]$figmaPresetBox.Items[$index].Tag -eq $recipePreset) {
            $figmaPresetBox.SelectedIndex = $index
            break
        }
    }
}

function Update-PatchSelection {
    $newestPatch = Find-NewestFigmaPatch
    if ($newestPatch) {
        $patchBox.Text = $newestPatch.FullName
        $patchFolder = [System.IO.Path]::GetDirectoryName($newestPatch.FullName)
        $patchHint.Text = "Newest Figma export: $($newestPatch.Name) ($(Get-FriendlyAge $newestPatch.LastWriteTime), found in $patchFolder)."
    }
    elseif ($figmaPresetBox.Items.Count -gt 0) {
        $patchBox.Text = ""
        $patchHint.Text = "No *.figma-patch.json found in Downloads yet. In Figma, run the Roblox UI Bridge plugin and click 'Export selected Roblox patch'."
    }
}

Update-FigmaPackFromRecipe
Update-PatchSelection

$recipeBox.Add_SelectionChanged({ Update-FigmaPackFromRecipe })

$rescanButton.Add_Click({
    Update-PatchSelection
    if (-not $patchBox.Text) {
        Set-ActionStatus "No Figma export was found. Export a patch from the Roblox UI Bridge plugin, then click 'Newest export' again."
    }
    else {
        Set-ActionStatus "Selected the newest Figma export."
    }
})

$browseButton.Add_Click({
    try {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = "Choose a Figma patch"
        $dialog.Filter = "Figma patch (*.figma-patch.json)|*.figma-patch.json|JSON files (*.json)|*.json"
        $downloadsFolder = Get-DownloadsFolder
        if ($downloadsFolder) {
            $dialog.InitialDirectory = $downloadsFolder
        }
        if ($dialog.ShowDialog($window)) {
            $patchBox.Text = $dialog.FileName
            $patchHint.Text = "Selected manually: $([System.IO.Path]::GetFileName($dialog.FileName))."
        }
    }
    catch {
        Write-LauncherLog "Patch browse failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The file picker could not open.`n`n$($_.Exception.Message)" "Browse for patch" ([System.Windows.MessageBoxImage]::Error)
    }
})

$applyFigmaButton.Add_Click({
    try {
        $selectedPack = $figmaPresetBox.SelectedItem
        if (-not $selectedPack) {
            Show-LauncherMessage "Choose the UI pack that you edited in Figma." "No UI pack selected" ([System.Windows.MessageBoxImage]::Warning)
            return
        }
        $patchPath = $patchBox.Text.Trim().Trim('"')
        if (-not $patchPath) {
            Show-LauncherMessage "Export a patch from the Roblox UI Bridge plugin in Figma first, then click 'Newest export'." "No patch selected" ([System.Windows.MessageBoxImage]::Warning)
            return
        }
        if (-not (Test-Path -LiteralPath $patchPath -PathType Leaf)) {
            Show-LauncherMessage "The patch file no longer exists:`n$patchPath" "Patch not found" ([System.Windows.MessageBoxImage]::Warning)
            return
        }
        $patchJson = Get-Content -LiteralPath $patchPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patchFormat = ""
        if ($patchJson.PSObject.Properties.Name -contains "format") {
            $patchFormat = [string]$patchJson.format
        }
        if ($patchFormat -ne "roblox-ui-bridge-v1") {
            Show-LauncherMessage "This file is not a Roblox UI Bridge export. Use the patch downloaded by the Figma plugin." "Unsupported patch" ([System.Windows.MessageBoxImage]::Warning)
            return
        }
        Start-LauncherTask "Apply Figma design to $([string]$selectedPack.Content)" (Join-Path $root "scripts\figma-ui.ps1") @("-Preset", [string]$selectedPack.Tag, "-PatchPath", $patchPath)
    }
    catch {
        Write-LauncherLog "Figma apply failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The Figma design could not be applied.`n`n$($_.Exception.Message)" "Apply Figma design" ([System.Windows.MessageBoxImage]::Error)
    }
})

# --- Tools page ------------------------------------------------------------

$runChecksButton.Add_Click({
    Start-LauncherTask "Project checks" (Join-Path $root "scripts\doctor.ps1") @("-Full")
})

$repairSetupButton.Add_Click({
    Start-LauncherTask "Repair / install setup" (Join-Path $root "scripts\setup.ps1")
})

$buildPackButton.Add_Click({
    Start-LauncherTask "Build UI packages" (Join-Path $root "scripts\build-ui-pack.ps1")
})

$openExportsButton.Add_Click({
    $exportsFolder = Join-Path $root "exports"
    New-Item -ItemType Directory -Path $exportsFolder -Force | Out-Null
    Start-Process -FilePath "explorer.exe" -ArgumentList $exportsFolder
})

$iconsButton.Add_Click({
    Start-CommandWindow "ICON_LIBRARY.cmd"
    Set-ActionStatus "Opening the shared icon library manager in its own window."
})

# --- Navigation ------------------------------------------------------------

$playNavButton.Add_Click({ Select-Page "Play" })
$figmaNavButton.Add_Click({ Select-Page "Figma" })
$toolsNavButton.Add_Click({ Select-Page "Tools" })
Select-Page "Play"

if ($SmokeTest) {
    $newestPatchName = "none"
    if ($patchBox.Text) {
        $newestPatchName = [System.IO.Path]::GetFileName($patchBox.Text)
    }
    Write-Host "Launcher UI loaded successfully"
    Write-Host "Project: $(Get-CurrentProject) | Git branch: $(Get-CurrentBranch)"
    Write-Host "Recipes: $($recipeBox.Items.Count) | UI packs: $($figmaPresetBox.Items.Count) | Newest Figma export: $newestPatchName"
    exit 0
}

$window.ShowDialog() | Out-Null
