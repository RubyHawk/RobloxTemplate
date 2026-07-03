[CmdletBinding()]
param([switch]$SmokeTest)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

$root = Split-Path -Parent $PSScriptRoot

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Roblox Game Designer" Width="900" Height="760"
        WindowStartupLocation="CenterScreen" Background="#0B1020"
        Foreground="White" FontFamily="Segoe UI">
  <ScrollViewer Name="DesignerScroll" VerticalScrollBarVisibility="Auto">
    <StackPanel Margin="30">
      <TextBlock Text="GAME PRESET DESIGNER" Foreground="#60A5FA" FontWeight="Bold" FontSize="13"/>
      <TextBlock Text="Build one clean game configuration" FontWeight="Bold" FontSize="30" Margin="0,6,0,4"/>
      <TextBlock Text="Each UI pack is a separate physical copy. Editing one never changes another." Foreground="#AAB8D4" FontSize="15"/>

      <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,22,0,0">
        <StackPanel>
          <TextBlock Text="1. UI PACK" FontWeight="Bold" Foreground="#93C5FD"/>
          <ComboBox Name="Preset" SelectedIndex="0" Height="38" Margin="0,9,0,0">
            <ComboBoxItem Content="Incremental / Simulator" Tag="incremental"/>
            <ComboBoxItem Content="Fantasy RPG" Tag="rpg"/>
          </ComboBox>
        </StackPanel>
      </Border>

      <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,14,0,0">
        <StackPanel>
          <TextBlock Text="2. CURRENCIES" FontWeight="Bold" Foreground="#93C5FD"/>
          <TextBlock Text="Choose 1-5. Every enabled currency is saved and controlled by the server." Foreground="#AAB8D4" Margin="0,5,0,8"/>
          <ComboBox Name="CurrencyCount" SelectedIndex="0" Width="100" HorizontalAlignment="Left" Height="34">
            <ComboBoxItem Content="1"/><ComboBoxItem Content="2"/><ComboBoxItem Content="3"/><ComboBoxItem Content="4"/><ComboBoxItem Content="5"/>
          </ComboBox>
          <Grid Margin="0,10,0,0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="44"/><ColumnDefinition Width="*"/><ColumnDefinition Width="90"/><ColumnDefinition Width="130"/><ColumnDefinition Width="150"/></Grid.ColumnDefinitions>
            <Grid.RowDefinitions><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
            <TextBlock Grid.Column="1" Text="Name" Foreground="#8FA1BF"/><TextBlock Grid.Column="2" Text="Symbol" Foreground="#8FA1BF"/><TextBlock Grid.Column="3" Text="Starting" Foreground="#8FA1BF"/><TextBlock Grid.Column="4" Text="RGB color" Foreground="#8FA1BF"/>
            <TextBlock Grid.Row="1" Text="1" VerticalAlignment="Center"/><TextBox Name="Name1" Grid.Row="1" Grid.Column="1" Text="Coins" Margin="3"/><TextBox Name="Symbol1" Grid.Row="1" Grid.Column="2" Text="$" Margin="3"/><TextBox Name="Start1" Grid.Row="1" Grid.Column="3" Text="2500" Margin="3"/><TextBox Name="Color1" Grid.Row="1" Grid.Column="4" Text="255,202,10" Margin="3"/>
            <TextBlock Grid.Row="2" Text="2" VerticalAlignment="Center"/><TextBox Name="Name2" Grid.Row="2" Grid.Column="1" Text="Gems" Margin="3"/><TextBox Name="Symbol2" Grid.Row="2" Grid.Column="2" Text="G" Margin="3"/><TextBox Name="Start2" Grid.Row="2" Grid.Column="3" Text="0" Margin="3"/><TextBox Name="Color2" Grid.Row="2" Grid.Column="4" Text="55,135,255" Margin="3"/>
            <TextBlock Grid.Row="3" Text="3" VerticalAlignment="Center"/><TextBox Name="Name3" Grid.Row="3" Grid.Column="1" Text="Stars" Margin="3"/><TextBox Name="Symbol3" Grid.Row="3" Grid.Column="2" Text="*" Margin="3"/><TextBox Name="Start3" Grid.Row="3" Grid.Column="3" Text="0" Margin="3"/><TextBox Name="Color3" Grid.Row="3" Grid.Column="4" Text="158,61,245" Margin="3"/>
            <TextBlock Grid.Row="4" Text="4" VerticalAlignment="Center"/><TextBox Name="Name4" Grid.Row="4" Grid.Column="1" Text="Tokens" Margin="3"/><TextBox Name="Symbol4" Grid.Row="4" Grid.Column="2" Text="T" Margin="3"/><TextBox Name="Start4" Grid.Row="4" Grid.Column="3" Text="0" Margin="3"/><TextBox Name="Color4" Grid.Row="4" Grid.Column="4" Text="5,209,178" Margin="3"/>
            <TextBlock Grid.Row="5" Text="5" VerticalAlignment="Center"/><TextBox Name="Name5" Grid.Row="5" Grid.Column="1" Text="Event" Margin="3"/><TextBox Name="Symbol5" Grid.Row="5" Grid.Column="2" Text="!" Margin="3"/><TextBox Name="Start5" Grid.Row="5" Grid.Column="3" Text="0" Margin="3"/><TextBox Name="Color5" Grid.Row="5" Grid.Column="4" Text="255,46,138" Margin="3"/>
          </Grid>
        </StackPanel>
      </Border>

      <Border Background="#111A2E" BorderBrush="#334A70" BorderThickness="1" CornerRadius="12" Padding="18" Margin="0,14,0,0">
        <StackPanel>
          <TextBlock Text="3. SHARED SYSTEMS" FontWeight="Bold" Foreground="#93C5FD"/>
          <WrapPanel Margin="0,8,0,0">
            <CheckBox Name="Store" Content="Store" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Inventory" Content="Inventory" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Rewards" Content="Daily rewards" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Offline" Content="Offline earnings" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Profiles" Content="Profiles" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Boards" Content="Leaderboards" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Codes" Content="Codes" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Feedback" Content="Feedback" IsChecked="True" Width="170" Margin="3"/>
            <CheckBox Name="Community" Content="Community verification" Width="210" Margin="3"/>
          </WrapPanel>
        </StackPanel>
      </Border>

      <Button Name="Build" Content="BUILD AND OPEN SHARED SANDBOX" Height="58" Margin="0,20,0,0" Background="#2563EB" Foreground="White" FontSize="17" FontWeight="Bold"/>
      <TextBlock Text="The same private Roblox sandbox is reused. Each preset has isolated real saved data." Foreground="#FBBF24" Margin="0,8,0,0" TextWrapping="Wrap"/>
      <Button Name="Package" Content="BUILD DRAG-AND-DROP UI PACKAGE" Height="46" Margin="0,9,0,0" Background="#18233B" Foreground="White" FontWeight="Bold"/>
      <TextBlock Name="Status" Text="Nothing has been generated yet." Foreground="#93A4C0" Margin="0,12,0,20" TextWrapping="Wrap"/>
    </StackPanel>
  </ScrollViewer>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)
function Control([string]$Name) { return $window.FindName($Name) }
$designerScroll = $window.FindName("DesignerScroll")
$window.Add_ContentRendered({ $designerScroll.ScrollToTop() })

$presetControl = Control "Preset"
$presetControl.Items.Clear()
$presetFolders = @(Get-ChildItem -LiteralPath (Join-Path $root "src\ui\presets") -Directory | Sort-Object Name)
foreach ($folder in $presetFolders) {
    $item = [System.Windows.Controls.ComboBoxItem]::new()
    $item.Tag = $folder.Name
    $item.Content = if ($folder.Name -eq "rpg") { "RPG" } else { (Get-Culture).TextInfo.ToTitleCase(($folder.Name -replace '[-_]+', ' ')) }
    [void]$presetControl.Items.Add($item)
}
if ($presetControl.Items.Count -eq 0) { throw "No complete UI presets were found under src\ui\presets." }
$presetControl.SelectedIndex = 0

function Slug([string]$Value) {
    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '_'
    $slug = $slug.Trim('_')
    if ($slug -notmatch '^[a-z]') { $slug = "currency_$slug" }
    return $slug.Substring(0, [math]::Min(24, $slug.Length))
}

function Read-Recipe {
    $presetItem = [System.Windows.Controls.ComboBoxItem](Control "Preset").SelectedItem
    $countItem = [System.Windows.Controls.ComboBoxItem](Control "CurrencyCount").SelectedItem
    $count = [int]$countItem.Content
    $currencies = @()
    for ($index = 1; $index -le $count; $index++) {
        $name = [string](Control "Name$index").Text
        $symbol = [string](Control "Symbol$index").Text
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($symbol)) { throw "Currency $index needs a name and symbol." }
        $colorParts = @([string](Control "Color$index").Text -split ',' | ForEach-Object { [int]$_.Trim() })
        if ($colorParts.Count -ne 3) { throw "Currency $index color must look like 255,202,10." }
        $currencies += [ordered]@{
            id = Slug $name
            name = $name.Trim()
            symbol = $symbol.Trim()
            startingAmount = [int64](Control "Start$index").Text
            color = $colorParts
        }
    }
    return [ordered]@{
        preset = [string]$presetItem.Tag
        dataNamespace = [string]$presetItem.Tag
        currencies = $currencies
        features = [ordered]@{
            store = [bool](Control "Store").IsChecked
            inventory = [bool](Control "Inventory").IsChecked
            dailyRewards = [bool](Control "Rewards").IsChecked
            offlineEarnings = [bool](Control "Offline").IsChecked
            profiles = [bool](Control "Profiles").IsChecked
            leaderboards = [bool](Control "Boards").IsChecked
            codes = [bool](Control "Codes").IsChecked
            feedback = [bool](Control "Feedback").IsChecked
            communityVerification = [bool](Control "Community").IsChecked
        }
    }
}

function Invoke-Build([bool]$PackageOnly) {
    $status = Control "Status"
    try {
        $recipe = Read-Recipe
        $recipePath = Join-Path $root "build\designer\recipe.json"
        New-Item -ItemType Directory -Path (Split-Path -Parent $recipePath) -Force | Out-Null
        $recipe | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recipePath -Encoding UTF8
        $status.Text = "Building…"
        if ($PackageOnly) {
            & (Join-Path $PSScriptRoot "build-game-preset.ps1") -RecipePath $recipePath -PackageOnly
            $status.Text = "Ready. The independent UI package is in exports."
        } else {
            $sandboxScript = Join-Path $PSScriptRoot "sandbox.ps1"
            Start-Process -FilePath "powershell.exe" -ArgumentList @(
                "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
                "-File", $sandboxScript,
                "-RecipePath", $recipePath
            )
            $status.Text = "Opening the selected preset in the shared sandbox."
        }
    } catch {
        $status.Text = "Could not build: $($_.Exception.Message)"
    }
}

(Control "Build").Add_Click({ Invoke-Build $false })
(Control "Package").Add_Click({ Invoke-Build $true })

if ($SmokeTest) {
    Write-Host "Game Designer UI loaded successfully"
    exit 0
}
$window.ShowDialog() | Out-Null
