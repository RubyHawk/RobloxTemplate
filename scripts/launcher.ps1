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
$logFile = Join-Path $logDirectory "launcher.log"
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

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

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Roblox Template App" Width="760" Height="880"
        WindowStartupLocation="CenterScreen" MinWidth="700" MinHeight="620"
        Background="#0B1020" FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="BaseButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="20,14"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonBorder" CornerRadius="12"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.86"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.70"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="Background" Value="#2563EB"/>
            <Setter Property="BorderBrush" Value="#60A5FA"/>
        </Style>
        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="Background" Value="#18233B"/>
            <Setter Property="BorderBrush" Value="#334A70"/>
        </Style>
        <Style x:Key="SmallButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
            <Setter Property="Background" Value="#111A2E"/>
            <Setter Property="BorderBrush" Value="#2A3A5A"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="16,11"/>
            <Setter Property="HorizontalContentAlignment" Value="Center"/>
        </Style>
    </Window.Resources>

    <DockPanel>
        <Border DockPanel.Dock="Bottom" Background="#111A2E" BorderBrush="#263654" BorderThickness="0,1,0,0" Padding="22,10">
            <TextBlock x:Name="ActionStatus" Foreground="#C9D7EE" FontSize="13" TextWrapping="Wrap"
                       Text="Ready. Every task starts pre-filled from this window."/>
        </Border>
        <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel Margin="30,26,30,20">
                <TextBlock Text="ROBLOX TEMPLATE" Foreground="#60A5FA" FontSize="13" FontWeight="Bold"/>
                <TextBlock Text="One window for everything" Foreground="White" FontSize="30" FontWeight="Bold" Margin="0,8,0,5"/>
                <TextBlock Text="Pick your options here and click once. No typed choices, no dragging files into console windows."
                           Foreground="#AAB8D4" FontSize="15" TextWrapping="Wrap"/>

                <Border Background="#111A2E" BorderBrush="#263654" BorderThickness="1" CornerRadius="9" Padding="13,9" Margin="0,16,0,0">
                    <TextBlock x:Name="CurrentStatus" Foreground="#C9D7EE" FontSize="13" TextWrapping="Wrap"/>
                </Border>

                <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,16,0,0">
                    <StackPanel>
                        <TextBlock Text="PLAY AND TEST" FontWeight="Bold" Foreground="#93C5FD"/>
                        <TextBlock Text="Builds the selected recipe and opens the permanent player-test experience with live saved data."
                                   Foreground="#AAB8D4" Margin="0,5,0,10" TextWrapping="Wrap"/>
                        <DockPanel>
                            <TextBlock DockPanel.Dock="Left" Text="Game recipe" Foreground="#8FA1BF" VerticalAlignment="Center" Margin="0,0,10,0"/>
                            <ComboBox x:Name="RecipeBox" Height="32" VerticalContentAlignment="Center"/>
                        </DockPanel>
                        <Button x:Name="PlayableButton" Style="{StaticResource PrimaryButton}" Margin="0,12,0,0">
                            <StackPanel>
                                <TextBlock Text="OPEN SHARED TEST EXPERIENCE" FontSize="17" FontWeight="Bold"/>
                                <TextBlock Text="One console window handles setup, build, Studio, and Rojo. Keep it open while playing."
                                           Foreground="#DCEAFF" FontSize="13" FontWeight="Normal" Margin="0,6,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Button>
                    </StackPanel>
                </Border>

                <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,14,0,0">
                    <StackPanel>
                        <TextBlock Text="APPLY A FIGMA DESIGN" FontWeight="Bold" Foreground="#93C5FD"/>
                        <TextBlock Text="Uses the patch exported by the Roblox UI Bridge plugin, updates one UI pack, and rebuilds its playable files."
                                   Foreground="#AAB8D4" Margin="0,5,0,10" TextWrapping="Wrap"/>
                        <DockPanel>
                            <TextBlock DockPanel.Dock="Left" Text="UI pack" Foreground="#8FA1BF" VerticalAlignment="Center" Margin="0,0,10,0"/>
                            <ComboBox x:Name="FigmaPresetBox" Height="32" VerticalContentAlignment="Center"/>
                        </DockPanel>
                        <Grid Margin="0,10,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="PatchBox" Height="36" VerticalContentAlignment="Center"
                                     Background="#0B1224" Foreground="White" BorderBrush="#334A70" Padding="8,0"/>
                            <Button x:Name="RescanButton" Grid.Column="2" Style="{StaticResource SmallButton}" Content="Newest export"/>
                            <Button x:Name="BrowseButton" Grid.Column="4" Style="{StaticResource SmallButton}" Content="Browse..."/>
                        </Grid>
                        <TextBlock x:Name="PatchHint" Foreground="#8FA1BF" FontSize="12" Margin="0,7,0,0" TextWrapping="Wrap"/>
                        <Button x:Name="ApplyFigmaButton" Style="{StaticResource PrimaryButton}" Margin="0,12,0,0">
                            <StackPanel>
                                <TextBlock Text="APPLY FIGMA DESIGN" FontSize="17" FontWeight="Bold"/>
                                <TextBlock Text="Validates every layer path, updates only the selected pack, then rebuilds it."
                                           Foreground="#DCEAFF" FontSize="13" FontWeight="Normal" Margin="0,6,0,0" TextWrapping="Wrap"/>
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
                    <Button x:Name="TemplateButton" Grid.Column="0" Style="{StaticResource SecondaryButton}">
                        <StackPanel>
                            <TextBlock Text="OPEN TEMPLATE" FontSize="16" FontWeight="Bold"/>
                            <TextBlock Text="UI authoring workbench. Mock data only."
                                       Foreground="#B9C7DE" FontSize="12" FontWeight="Normal" Margin="0,6,0,0" TextWrapping="Wrap"/>
                        </StackPanel>
                    </Button>
                    <Button x:Name="DesignerButton" Grid.Column="2" Style="{StaticResource SecondaryButton}">
                        <StackPanel>
                            <TextBlock Text="GAME DESIGNER" FontSize="16" FontWeight="Bold"/>
                            <TextBlock Text="Pick a UI pack, currencies, and systems in a form."
                                       Foreground="#B9C7DE" FontSize="12" FontWeight="Normal" Margin="0,6,0,0" TextWrapping="Wrap"/>
                        </StackPanel>
                    </Button>
                </Grid>

                <Grid Margin="0,14,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="12"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Grid.RowDefinitions>
                        <RowDefinition/>
                        <RowDefinition Height="10"/>
                        <RowDefinition/>
                    </Grid.RowDefinitions>
                    <Button x:Name="SetupButton" Grid.Row="0" Grid.Column="0" Style="{StaticResource SmallButton}" Content="Repair / install setup"/>
                    <Button x:Name="CheckButton" Grid.Row="0" Grid.Column="2" Style="{StaticResource SmallButton}" Content="Run project checks"/>
                    <Button x:Name="UiPackButton" Grid.Row="2" Grid.Column="0" Style="{StaticResource SmallButton}" Content="Build drag-and-drop UI package"/>
                    <Button x:Name="IconsButton" Grid.Row="2" Grid.Column="2" Style="{StaticResource SmallButton}" Content="Icon library manager"/>
                </Grid>

                <TextBlock Text="Two permanent cloud experiences are reused; each preset keeps separate saved data and visual files."
                           Foreground="#7384A3" FontSize="12" TextAlignment="Center" Margin="0,16,0,0" TextWrapping="Wrap"/>
            </StackPanel>
        </ScrollViewer>
    </DockPanel>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

function Find-Control([string]$Name) {
    $control = $window.FindName($Name)
    if (-not $control) {
        throw "Launcher control is missing from the window: $Name"
    }
    return $control
}

$currentStatus = Find-Control "CurrentStatus"
$actionStatus = Find-Control "ActionStatus"
$recipeBox = Find-Control "RecipeBox"
$playableButton = Find-Control "PlayableButton"
$figmaPresetBox = Find-Control "FigmaPresetBox"
$patchBox = Find-Control "PatchBox"
$patchHint = Find-Control "PatchHint"
$rescanButton = Find-Control "RescanButton"
$browseButton = Find-Control "BrowseButton"
$applyFigmaButton = Find-Control "ApplyFigmaButton"
$templateButton = Find-Control "TemplateButton"
$designerButton = Find-Control "DesignerButton"
$setupButton = Find-Control "SetupButton"
$checkButton = Find-Control "CheckButton"
$uiPackButton = Find-Control "UiPackButton"
$iconsButton = Find-Control "IconsButton"

function Set-ActionStatus([string]$Message) {
    $actionStatus.Text = $Message
}

$currentStatus.Text = "Project: $(Get-CurrentProject)  |  Git branch: $(Get-CurrentBranch)"
Write-LauncherLog "Launcher opened on $(Get-CurrentBranch) | $(Get-CurrentProject)."

# Game recipes for the shared player-test sandbox.
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

# Complete UI packs that the Figma bridge can update.
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

$playableButton.Add_Click({
    try {
        $selectedRecipe = $recipeBox.SelectedItem
        if (-not $selectedRecipe) {
            Show-LauncherMessage "Add a recipe file under config-presets first." "No recipe selected" ([System.Windows.MessageBoxImage]::Warning)
            return
        }
        Start-CommandWindow "SANDBOX.cmd" @("-RecipePath", [string]$selectedRecipe.Tag)
        Set-ActionStatus "Opening the shared test experience with the '$([string]$selectedRecipe.Content)' recipe. Keep its console window open while playing."
    }
    catch {
        Write-LauncherLog "Shared sandbox failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The launcher hit an unexpected error. Nothing was deleted.`n`nDetails were saved to build\launcher.log." "Could not open shared sandbox" ([System.Windows.MessageBoxImage]::Error)
    }
})

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
        Start-CommandWindow "FIGMA_UI.cmd" @("-Preset", [string]$selectedPack.Tag, "-PatchPath", $patchPath)
        Set-ActionStatus "Applying the Figma design to the '$([string]$selectedPack.Content)' pack. Its console window rebuilds the playable files and then says Done."
    }
    catch {
        Write-LauncherLog "Figma apply failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The Figma design could not be applied.`n`n$($_.Exception.Message)" "Apply Figma design" ([System.Windows.MessageBoxImage]::Error)
    }
})

$templateButton.Add_Click({
    try {
        Start-CommandWindow "2_START.cmd"
        Set-ActionStatus "Opening the template workbench. Keep its console window open while editing."
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

$setupButton.Add_Click({
    Start-CommandWindow "1_SETUP.cmd"
    Set-ActionStatus "Running setup in its own console window."
})

$checkButton.Add_Click({
    Start-CommandWindow "3_CHECK.cmd"
    Set-ActionStatus "Running the project checks in their own console window."
})

$uiPackButton.Add_Click({
    Start-CommandWindow "4_BUILD_UI_PACK.cmd"
    Set-ActionStatus "Building the drag-and-drop UI package in its own console window."
})

$iconsButton.Add_Click({
    Start-CommandWindow "ICON_LIBRARY.cmd"
    Set-ActionStatus "Opening the shared icon library manager."
})

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
