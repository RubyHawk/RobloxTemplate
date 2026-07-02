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

function Start-CommandWindow([string]$FileName) {
    $commandFile = Join-Path $root $FileName
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList "/d /c `"$commandFile`"" -WorkingDirectory $root -PassThru
    Write-LauncherLog "Started $FileName as process $($process.Id)."
}

function Switch-ToVersion([string]$Branch) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Show-LauncherMessage "Git is missing. Ask the project owner to install Git, then run START_HERE.cmd again." "Git is needed" ([System.Windows.MessageBoxImage]::Error)
        return $false
    }

    $currentBranch = Get-CurrentBranch
    if ($currentBranch -eq $Branch) {
        Write-LauncherLog "Already on $Branch; keeping saved Studio UI changes."
        return $true
    }

    $trackedChanges = @(& git -C $root status --porcelain --untracked-files=no 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Show-LauncherMessage "This folder is not a working Git project. Ask the project owner to check the folder." "Project not found" ([System.Windows.MessageBoxImage]::Error)
        return $false
    }
    if ($trackedChanges.Count -gt 0) {
        Show-LauncherMessage "There are uncommitted project changes. Nothing was deleted. Ask the programmer to commit or save those changes before switching versions." "Changes need attention" ([System.Windows.MessageBoxImage]::Warning)
        return $false
    }

    # Windows PowerShell 5 reports normal Git status text from stderr as a
    # terminating error when ErrorActionPreference is Stop. Capture it without
    # treating messages such as "Switched to branch" as failures.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $switchOutput = @(& git -C $root switch $Branch 2>&1)
        $switchExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    Write-LauncherLog "Git switch $Branch returned $switchExitCode. $($switchOutput -join ' ')"
    if ($switchExitCode -ne 0) {
        Show-LauncherMessage (($switchOutput -join "`n") + "`n`nAsk the project owner for help switching branches.") "Could not switch version" ([System.Windows.MessageBoxImage]::Error)
        return $false
    }
    return $true
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Roblox Map Launcher" Width="720" Height="780"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
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

    <Grid Margin="34">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="18"/>
            <RowDefinition Height="112"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="112"/>
            <RowDefinition Height="14"/>
            <RowDefinition Height="112"/>
            <RowDefinition Height="24"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0">
            <TextBlock Text="ROBLOX MAP LAUNCHER" Foreground="#60A5FA" FontSize="13" FontWeight="Bold"/>
            <TextBlock Text="What do you want to open?" Foreground="White" FontSize="30" FontWeight="Bold" Margin="0,8,0,5"/>
            <TextBlock Text="Choose one. The launcher handles the branch, build, Rojo, and Studio." Foreground="#AAB8D4" FontSize="15"/>
        </StackPanel>

        <Border Grid.Row="1" Background="#111A2E" BorderBrush="#263654" BorderThickness="1" CornerRadius="9" Padding="13,9" Margin="0,18,0,0">
            <TextBlock x:Name="CurrentStatus" Foreground="#C9D7EE" FontSize="13"/>
        </Border>

        <Button x:Name="PlayableButton" Grid.Row="3" Style="{StaticResource PrimaryButton}">
            <StackPanel>
                <TextBlock Text="OPEN PLAYABLE STARTER" FontSize="18" FontWeight="Bold"/>
                <TextBlock Text="Recommended - complete systems plus the blue demo earning pad." Foreground="#DCEAFF" FontSize="13" FontWeight="Normal" Margin="0,7,0,0"/>
            </StackPanel>
        </Button>

        <Button x:Name="TemplateButton" Grid.Row="5" Style="{StaticResource SecondaryButton}">
            <StackPanel>
                <TextBlock Text="OPEN TEMPLATE" FontSize="18" FontWeight="Bold"/>
                <TextBlock Text="Reusable systems gallery only, without starter gameplay." Foreground="#B9C7DE" FontSize="13" FontWeight="Normal" Margin="0,7,0,0"/>
            </StackPanel>
        </Button>

        <Button x:Name="DesignerButton" Grid.Row="7" Style="{StaticResource SecondaryButton}">
            <StackPanel>
                <TextBlock Text="DESIGN A GAME PRESET" FontSize="18" FontWeight="Bold"/>
                <TextBlock Text="Choose an independent UI pack, 1-5 currencies, and shared systems." Foreground="#B9C7DE" FontSize="13" FontWeight="Normal" Margin="0,7,0,0"/>
            </StackPanel>
        </Button>

        <Grid Grid.Row="9">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="SetupButton" Grid.Column="0" Style="{StaticResource SmallButton}" Content="Repair / install setup"/>
            <Button x:Name="CheckButton" Grid.Column="2" Style="{StaticResource SmallButton}" Content="Run project checks"/>
        </Grid>

        <TextBlock Grid.Row="10" Text="Tip: generated presets are separate files, so UI Plus edits never leak into another pack."
                   Foreground="#7384A3" FontSize="12" VerticalAlignment="Bottom" TextAlignment="Center" Margin="0,0,0,4"/>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)
$currentStatus = $window.FindName("CurrentStatus")
$playableButton = $window.FindName("PlayableButton")
$templateButton = $window.FindName("TemplateButton")
$designerButton = $window.FindName("DesignerButton")
$setupButton = $window.FindName("SetupButton")
$checkButton = $window.FindName("CheckButton")

$currentStatus.Text = "Current selection: $(Get-CurrentBranch)  |  $(Get-CurrentProject)"
Write-LauncherLog "Launcher opened on $(Get-CurrentBranch) | $(Get-CurrentProject)."

$playableButton.Add_Click({
    $window.IsEnabled = $false
    try {
        if (Switch-ToVersion "playable-starter") {
            Start-CommandWindow "2_START.cmd"
            $window.Close()
        }
        else {
            $window.IsEnabled = $true
        }
    }
    catch {
        Write-LauncherLog "Playable starter failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The launcher hit an unexpected error. Nothing was deleted.`n`nDetails were saved to build\launcher.log." "Could not open playable starter" ([System.Windows.MessageBoxImage]::Error)
        $window.IsEnabled = $true
    }
})

$templateButton.Add_Click({
    $window.IsEnabled = $false
    try {
        if (Switch-ToVersion "template") {
            Start-CommandWindow "2_START.cmd"
            $window.Close()
        }
        else {
            $window.IsEnabled = $true
        }
    }
    catch {
        Write-LauncherLog "Template failed: $($_.Exception.ToString())"
        Show-LauncherMessage "The launcher hit an unexpected error. Nothing was deleted.`n`nDetails were saved to build\launcher.log." "Could not open template" ([System.Windows.MessageBoxImage]::Error)
        $window.IsEnabled = $true
    }
})

$designerButton.Add_Click({
    Start-CommandWindow "5_GAME_DESIGNER.cmd"
    $window.Close()
})

$setupButton.Add_Click({ Start-CommandWindow "1_SETUP.cmd" })
$checkButton.Add_Click({ Start-CommandWindow "3_CHECK.cmd" })

if ($SmokeTest) {
    Write-Host "Launcher UI loaded successfully"
    Write-Host "Current selection: $(Get-CurrentBranch) | $(Get-CurrentProject)"
    exit 0
}

$window.ShowDialog() | Out-Null
