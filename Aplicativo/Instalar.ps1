#requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$dest=Join-Path $env:LOCALAPPDATA 'RONICompanion\App'
[xml]$x=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Instalar RONI Companion" Width="540" Height="460" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Background="#0B151D" Foreground="#EDF5F8" FontFamily="Segoe UI">
 <StackPanel Margin="32"><TextBlock Text="Olá, eu sou o RONI." FontSize="29" FontWeight="SemiBold" Foreground="#78E7BF"/><TextBlock Text="Uma mensagem de longe. Um aviso pertinho." FontSize="15" Margin="0,12,0,22" Foreground="#A8C0CA"/>
 <TextBlock Text="Vou receber as mensagens pela USB e avisar com som e uma janela discreta. Você pode fechar minha janela e continuar usando o notebook." TextWrapping="Wrap" FontSize="15" LineHeight="24"/>
 <TextBlock Text="Instalação somente para seu usuário. Sem administrador, sem navegador aberto e sem baixar programas extras." TextWrapping="Wrap" Foreground="#A8C0CA" Margin="0,18,0,14"/>
 <CheckBox Name="Start" Content="Iniciar automaticamente com o Windows" IsChecked="True" Foreground="#EDF5F8" Margin="0,8,0,20"/>
 <Button Name="Install" Content="Permitir e instalar" Background="#78E7BF" Foreground="#09271F" FontSize="16" FontWeight="SemiBold" Padding="15"/>
 <TextBlock Name="Status" Text="A chave do Telegram fica somente no RONI." Foreground="#A8C0CA" TextWrapping="Wrap" Margin="0,16,0,0"/>
 </StackPanel>
</Window>
'@
$w=[Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $x))
$btn=$w.FindName('Install');$status=$w.FindName('Status');$start=$w.FindName('Start')
$btn.Add_Click({
 try {
  $btn.IsEnabled=$false;$status.Text='Instalando para seu usuário…'
  $data=Join-Path $env:LOCALAPPDATA 'RONICompanion';[void][IO.Directory]::CreateDirectory($data)
  # Solicita saida apenas da instancia do RONI deste usuario ao atualizar.
  [IO.File]::WriteAllText((Join-Path $data 'sair.request'),'sair');Start-Sleep -Milliseconds 700
  [void][IO.Directory]::CreateDirectory($dest)
  foreach($name in 'Roni.ps1','Interface.xaml','Roni.ico','Aviso.wav','Desinstalar.ps1','Desinstalar.cmd'){
   $src=Join-Path $PSScriptRoot $name;$dst=Join-Path $dest $name
   if([IO.Path]::GetFullPath($src) -ne [IO.Path]::GetFullPath($dst)){Copy-Item -LiteralPath $src -Destination $dst -Force}
  }
  $request=Join-Path $data 'sair.request';if(Test-Path -LiteralPath $request){Remove-Item -LiteralPath $request -Force}
  $shell=New-Object -ComObject WScript.Shell
  $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $args='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $dest 'Roni.ps1')+'"'
  foreach($dir in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){
   $lnk=$shell.CreateShortcut((Join-Path $dir 'RONI Companion.lnk'));$lnk.TargetPath=$ps;$lnk.Arguments=$args;$lnk.WorkingDirectory=$dest;$lnk.IconLocation=Join-Path $dest 'Roni.ico';$lnk.Save()
  }
  $startup=Join-Path ([Environment]::GetFolderPath('Startup')) 'RONI Companion.lnk'
  if($start.IsChecked){$lnk=$shell.CreateShortcut($startup);$lnk.TargetPath=$ps;$lnk.Arguments=$args+' -Background';$lnk.WorkingDirectory=$dest;$lnk.IconLocation=Join-Path $dest 'Roni.ico';$lnk.Save()}
  elseif(Test-Path -LiteralPath $startup){Remove-Item -LiteralPath $startup -Force}
  $shortcut=$shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Desinstalar RONI Companion.lnk'))
  $shortcut.TargetPath=$ps;$shortcut.Arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+(Join-Path $dest 'Desinstalar.ps1')+'"';$shortcut.Save()
  Start-Process -FilePath $ps -ArgumentList $args -WindowStyle Hidden
  $w.Close()
 }catch{$btn.IsEnabled=$true;$status.Text='Não foi possível instalar: '+$_.Exception.Message}
})
[void]$w.ShowDialog()
