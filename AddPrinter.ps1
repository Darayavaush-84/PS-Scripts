<#
.SYNOPSIS
    This script provides a graphical user interface to manage printers on a local machine. It allows users to install, uninstall, and search for printers on a specified print server. 

.DESCRIPTION
    The script creates a GUI using XAML and the Windows Presentation Foundation (WPF) library. It retrieves a list of printers from a print server and displays them in a table with their installation status. Users can install or uninstall printers by selecting them from the table and clicking the 'Install' or 'Uninstall' button. Users can also search for specific printers using the search box. 

.PARAMETER None
    The script does not take any parameters.

.EXAMPLE
    To run the script, navigate to the folder containing the script and type:
    .\AddPrinter.ps1

.NOTES
    Make sure to run the script with the necessary permissions for managing printers. 

.AUTHOR
    Original script by Dario Barbarino
#>

Add-Type -AssemblyName PresentationFramework

[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Printer Installer" Height="550" Width="800">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <DataGrid x:Name="PrinterDataGrid" Grid.Row="0" Margin="10" AutoGenerateColumns="False" IsReadOnly="True">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Printer Name" Binding="{Binding Name}" Width="*"/>
                <DataGridTextColumn Header="Location" Binding="{Binding Location}" Width="*"/>
                <DataGridTextColumn Header="Model" Binding="{Binding DriverName}" Width="*"/>
                <DataGridTemplateColumn Header="Status">
                    <DataGridTemplateColumn.CellTemplate>
                        <DataTemplate>
                            <TextBlock Text="{Binding InstallStatus}" Margin="0,0,10,0">
                                <TextBlock.Style>
                                    <Style TargetType="TextBlock">
                                        <Style.Triggers>
                                            <DataTrigger Binding="{Binding InstallStatus}" Value="Installed">
                                                <Setter Property="Foreground" Value="Green" />
                                            </DataTrigger>
                                            <DataTrigger Binding="{Binding InstallStatus}" Value="Error Installing">
                                                <Setter Property="Foreground" Value="Red" />
                                            </DataTrigger>
                                        </Style.Triggers>
                                    </Style>
                                </TextBlock.Style>
                            </TextBlock>
                        </DataTemplate>
                    </DataGridTemplateColumn.CellTemplate>
                </DataGridTemplateColumn>
            </DataGrid.Columns>
        </DataGrid>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Left" Margin="10,10,0,0">
    <TextBox x:Name="SearchBox" Width="200" Margin="0,0,10,10"/>
    <Button x:Name="SearchButton" Content="Search" Width="100" Margin="0,0,10,10"/>
    <Button x:Name="ResetSearchButton" Content="Reset Search" Width="100" Margin="0,0,10,10"/>
    <Button x:Name="InstallButton" Content="Install" Width="100" Margin="0,0,10,10">
    <Button.Style>
        <Style TargetType="Button">
            <Setter Property="IsEnabled" Value="True" />
            <Style.Triggers>
                <DataTrigger Binding="{Binding ElementName=PrinterDataGrid, Path=SelectedItem.InstallStatus}" Value="Installed">
                    <Setter Property="IsEnabled" Value="False" />
                </DataTrigger>
            </Style.Triggers>
        </Style>
    </Button.Style>
</Button>

<Button x:Name="UninstallButton" Content="Uninstall" Width="100" Margin="0,0,10,10">
    <Button.Style>
        <Style TargetType="Button">
            <Setter Property="IsEnabled" Value="False" />
            <Style.Triggers>
                <DataTrigger Binding="{Binding ElementName=PrinterDataGrid, Path=SelectedItem.InstallStatus}" Value="Installed">
                    <Setter Property="IsEnabled" Value="True" />
                </DataTrigger>
            </Style.Triggers>
        </Style>
    </Button.Style>
</Button>

<!-- Added Info button -->
<Button x:Name="InfoButton" Content="Info" Width="100" Margin="0,0,10,10"/>

</StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAML.DocumentElement
$window = [Windows.Markup.XamlReader]::Load($reader)

$PrinterDataGrid = $window.FindName("PrinterDataGrid")
$InstallButton = $window.FindName("InstallButton")
$UninstallButton = $window.FindName("UninstallButton")
$SearchBox = $window.FindName("SearchBox")
$SearchButton = $window.FindName("SearchButton")
$ResetSearchButton = $window.FindName("ResetSearchButton")

# Added Info button reference
$InfoButton = $window.FindName("InfoButton")

$printers = Get-Printer -ComputerName yourprintserver.yourdomain.local | Select-Object Name, Location, DriverName, @{Name='InstallStatus';Expression={''}}
$PrinterDataGrid.ItemsSource = $printers

$installedPrinters = Get-Printer | Select-Object -ExpandProperty Name
$installedPrinters = $installedPrinters | ForEach-Object { $_.Split('\')[-1] }

foreach ($printer in $printers) {
    if ($installedPrinters -contains $printer.Name) {
        $printer.InstallStatus = "Installed"
    } else {
        $printer.InstallStatus = "Not Installed"
    }
}

$InstallButton.Add_Click({
    $selectedPrinters = $PrinterDataGrid.SelectedItems
    foreach ($selectedPrinter in $selectedPrinters) {
        $printerName = $selectedPrinter.Name
        try {
            Add-Printer -ConnectionName "\\yourprintserver.yourdomain.local\$printerName"
            $selectedPrinter.InstallStatus = "Installed"
        } catch {
            $selectedPrinter.InstallStatus = "Error Installing"
        }
    }
    $PrinterDataGrid.Items.Refresh()

    # Force a re-evaluation of the DataTrigger
    $selectedItem = $PrinterDataGrid.SelectedItem
    $PrinterDataGrid.SelectedItem = $null
    $PrinterDataGrid.SelectedItem = $selectedItem
})

$UninstallButton.Add_Click({
    $selectedPrinters = $PrinterDataGrid.SelectedItems
    foreach ($selectedPrinter in $selectedPrinters) {
        $printerName = $selectedPrinter.Name
        try {
            $localPrinter = Get-Printer | Where-Object { $_.Name -like "*\$printerName" }
            if ($localPrinter) {
                Remove-Printer -Name $localPrinter.Name
                $selectedPrinter.InstallStatus = "Not Installed"
            } else {
                $selectedPrinter.InstallStatus = "Error Uninstalling"
            }
        } catch {
            $selectedPrinter.InstallStatus = "Error Uninstalling"
        }
    }
    $PrinterDataGrid.Items.Refresh()

    # Force a re-evaluation of the DataTrigger
    $selectedItem = $PrinterDataGrid.SelectedItem
    $PrinterDataGrid.SelectedItem = $null
    $PrinterDataGrid.SelectedItem = $selectedItem
})

# Added Info button event handler
$InfoButton.Add_Click({
    [System.Windows.MessageBox]::Show("AddPrinter Tool V 1.0 - Developed by Dario Barbarino, All Rights Reserved", "Info")
})

$SearchBox.Add_KeyDown({
    if ($_.Key -eq "Enter") {
        $SearchButton_Click.Invoke($null, $null)
    }
})

$SearchButton_Click = {
    $searchString = $SearchBox.Text
    $filteredPrinters = ,($printers | Where-Object { $_.Name -like "*$searchString*" })
    $PrinterDataGrid.ItemsSource = $filteredPrinters
}

$SearchButton.Add_Click($SearchButton_Click)

$ResetSearchButton.Add_Click({
    $SearchBox.Text = ""
    $PrinterDataGrid.ItemsSource = $printers
})

$window.ShowDialog() | Out-Null
