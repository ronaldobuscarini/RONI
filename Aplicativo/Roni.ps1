#requires -Version 5.1
param([switch]$Background,[switch]$Demo)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
$script:Root=$PSScriptRoot
$script:Data=Join-Path $env:LOCALAPPDATA 'RONICompanion'
[void][IO.Directory]::CreateDirectory($script:Data)
$script:ConfigFile=Join-Path $script:Data 'preferencias.json'
$script:HistoryFile=Join-Path $script:Data 'mensagens.json'
$script:ShowFile=Join-Path $script:Data 'abrir.request'
$script:ExitFile=Join-Path $script:Data 'sair.request'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:Mutex=New-Object System.Threading.Mutex($false,('Local\RONICompanion-'+$sid))
if(-not $script:Mutex.WaitOne(0,$false)) { [IO.File]::WriteAllText($script:ShowFile,'abrir');$script:Mutex.Dispose();exit }
$script:Port=$null;$script:Verified=$false;$script:Paused=$false;$script:Closing=$false
$script:CurrentBoot='';$script:Buffer='';$script:LastScan=[datetime]::MinValue;$script:LastHello=[datetime]::MinValue
$script:OpenedAt=[datetime]::MinValue;$script:LastSeen=[datetime]::MinValue
$script:Candidates=@();$script:CandidateIndex=0;$script:UpdatingPorts=$false
$script:Records=@();$script:Seen=@();$script:Popups=New-Object System.Collections.ArrayList
$script:Settings=@{Sound=$true;Popup=$true;Port='Auto'}
function Write-JsonAtomic($Path,$Value) {
 $text=ConvertTo-Json -InputObject $Value -Depth 8
 $tmp=$Path+'.tmp'
 [IO.File]::WriteAllText($tmp,$text,(New-Object System.Text.UTF8Encoding($false)))
 Move-Item -LiteralPath $tmp -Destination $Path -Force
}
function Save-Settings { Write-JsonAtomic $script:ConfigFile $script:Settings }
try {
 if(Test-Path -LiteralPath $script:ConfigFile){$v=Get-Content -LiteralPath $script:ConfigFile -Raw -Encoding UTF8|ConvertFrom-Json;$script:Settings.Sound=[bool]$v.Sound;$script:Settings.Popup=[bool]$v.Popup;if($v.Port){$script:Settings.Port=[string]$v.Port}}
 if(Test-Path -LiteralPath $script:HistoryFile){$v=Get-Content -LiteralPath $script:HistoryFile -Raw -Encoding UTF8|ConvertFrom-Json;$script:Records=@($v.Records);$script:Seen=@($v.Seen)}
} catch { [IO.File]::AppendAllText((Join-Path $script:Data 'diagnostico.log'),"Preferencias/historico ilegivel. Arquivo original preservado.\r\n") }
[xml]$xaml=Get-Content -LiteralPath (Join-Path $script:Root 'Interface.xaml') -Raw -Encoding UTF8
$reader=New-Object System.Xml.XmlNodeReader $xaml
$script:Window=[Windows.Markup.XamlReader]::Load($reader)
$script:UI=@{}
foreach($n in 'Connection','DeviceTitle','DeviceHelp','Ports','Refresh','Pause','Sound','Popup','Startup','Test','Count','Messages','Empty','Clear','Hide'){$script:UI[$n]=$script:Window.FindName($n)}
$script:Tray=New-Object System.Windows.Forms.NotifyIcon
$script:Tray.Icon=New-Object System.Drawing.Icon((Join-Path $script:Root 'Roni.ico'))
$script:Window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([uri](Join-Path $script:Root 'Roni.ico'))
$script:Tray.Text='RONI Companion - aguardando USB';$script:Tray.Visible=$true
$menu=New-Object System.Windows.Forms.ContextMenuStrip
$miOpen=$menu.Items.Add('Abrir RONI');$miPause=$menu.Items.Add('Pausar / retomar USB');[void]$menu.Items.Add('-');$miExit=$menu.Items.Add('Sair do aplicativo')
$script:Tray.ContextMenuStrip=$menu
$script:SoundPlayer=New-Object System.Media.SoundPlayer((Join-Path $script:Root 'Aviso.wav'))
function Get-StartupPath { Join-Path ([Environment]::GetFolderPath('Startup')) 'RONI Companion.lnk' }
function Set-Startup([bool]$Enabled) {
 $path=Get-StartupPath
 if($Enabled){
  $shell=New-Object -ComObject WScript.Shell;$lnk=$shell.CreateShortcut($path)
  $lnk.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $lnk.Arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $script:Root 'Roni.ps1')+'" -Background'
  $lnk.WorkingDirectory=$script:Root;$lnk.IconLocation=Join-Path $script:Root 'Roni.ico';$lnk.Save()
 } elseif(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
}
function Show-Main { $script:Window.Show();$script:Window.WindowState='Normal';[void]$script:Window.Activate() }
function Set-State([string]$Title,[string]$Help,[string]$Badge,[string]$Color='#F2C879') {
 $script:UI.DeviceTitle.Text=$Title;$script:UI.DeviceHelp.Text=$Help;$script:UI.Connection.Text=$Badge
 $script:UI.Connection.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($Color)
}
function Disconnect-Roni {
 if($null -ne $script:Port){try{$script:Port.Close();$script:Port.Dispose()}catch{};$script:Port=$null}
 $script:Verified=$false;$script:Buffer='';$script:Tray.Text='RONI Companion - aguardando USB'
}
function Render-History {
 $script:UI.Messages.Children.Clear()
 if($script:Records.Count -eq 0){[void]$script:UI.Messages.Children.Add($script:UI.Empty)}
 foreach($r in $script:Records){
  $card=New-Object System.Windows.Controls.Border;$card.Background=[Windows.Media.Brushes]::Transparent
  $card.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#29414F');$card.BorderThickness='0,0,0,1';$card.Padding='2,14,2,17'
  $stack=New-Object System.Windows.Controls.StackPanel
  $meta=New-Object System.Windows.Controls.TextBlock;$meta.Text=([string]$r.Source+'  •  '+[string]$r.At);$meta.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#78E7BF');$meta.FontSize=11
  $body=New-Object System.Windows.Controls.TextBlock;$body.Text=[string]$r.Text;$body.TextWrapping='Wrap';$body.FontSize=18;$body.Margin='0,8,0,0';$body.LineHeight=27
  [void]$stack.Children.Add($meta);[void]$stack.Children.Add($body);$card.Child=$stack;[void]$script:UI.Messages.Children.Add($card)
 }
 $script:UI.Count.Text=('{0} mensagens' -f $script:Records.Count)
}
function Alert-Message([string]$Text,[string]$Source) {
 if($script:Settings.Sound){try{$script:SoundPlayer.Play()}catch{[Media.SystemSounds]::Asterisk.Play()}}
 if(-not $script:Settings.Popup){return}
 # Janela propria: nao abre o navegador, nao usa HTML e nao rouba o foco.
 $pop=New-Object System.Windows.Window;$pop.Width=390;$pop.SizeToContent='Height';$pop.MaxHeight=320;$pop.WindowStyle='None';$pop.ResizeMode='NoResize';$pop.AllowsTransparency=$true;$pop.Background=[Windows.Media.Brushes]::Transparent;$pop.Topmost=$true;$pop.ShowActivated=$false;$pop.ShowInTaskbar=$false
 $border=New-Object System.Windows.Controls.Border;$border.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#13232F');$border.CornerRadius=18;$border.Padding=22;$border.BorderThickness=1;$border.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#78E7BF')
 $stack=New-Object System.Windows.Controls.StackPanel
 $title=New-Object System.Windows.Controls.TextBlock;$title.Text='RONI  •  Nova mensagem';$title.FontFamily='Segoe UI';$title.FontWeight='SemiBold';$title.FontSize=15;$title.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#78E7BF')
 $body=New-Object System.Windows.Controls.TextBlock;$body.Text=$Text;$body.FontFamily='Segoe UI';$body.FontSize=20;$body.TextWrapping='Wrap';$body.Margin='0,12,0,12';$body.Foreground=[Windows.Media.Brushes]::White
 $foot=New-Object System.Windows.Controls.TextBlock;$foot.Text=$Source+' • Clique para abrir o histórico';$foot.FontSize=11;$foot.Foreground=[Windows.Media.Brushes]::LightGray
 [void]$stack.Children.Add($title);[void]$stack.Children.Add($body);[void]$stack.Children.Add($foot);$border.Child=$stack;$pop.Content=$border
 $pop.Add_MouseLeftButtonUp({Show-Main;$this.Close()})
 $pop.Add_ContentRendered({$wa=[Windows.SystemParameters]::WorkArea;$this.Left=$wa.Right-$this.ActualWidth-18;$this.Top=$wa.Bottom-$this.ActualHeight-18})
 # Evita varios avisos sobrepostos; as mensagens anteriores permanecem no historico.
 foreach($old in @($script:Popups)){try{$old.Window.Close()}catch{}}
 $script:Popups.Clear();[void]$script:Popups.Add(@{Window=$pop;Until=[datetime]::UtcNow.AddSeconds(14)})
 $pop.Show()
}
function Send-Line([string]$Text) { if($null -ne $script:Port -and $script:Port.IsOpen){$script:Port.WriteLine($Text)} }
function Accept-Line([string]$Line) {
 if(-not $Line.StartsWith('RONI_PC ')){return}
 try{$p=$Line.Substring(8)|ConvertFrom-Json}catch{return}
 if($p.v -ne 1 -or $p.device -ne 'RONI' -or [string]$p.boot -notmatch '^[0-9a-fA-F]{16}$'){return}
 if($p.type -eq 'hello'){
  $script:Verified=$true;$script:CurrentBoot=[string]$p.boot;$script:LastSeen=[datetime]::UtcNow
  $script:Tray.Text='RONI Companion - conectado'
  $extra='Você pode minimizar. As mensagens do Telegram chegarão por aqui.'
  if([int]$p.dropped -gt 0){$extra='A fila do RONI encheu enquanto estava desconectado. Alguns avisos antigos foram descartados.'}
  Set-State 'RONI conectado' $extra ('●  Conectado · '+$script:Port.PortName) '#78E7BF';return
 }
 if(-not $script:Verified -or $p.type -ne 'message' -or [string]$p.boot -ne $script:CurrentBoot){return}
 $script:LastSeen=[datetime]::UtcNow
 $id=0L;if(-not [long]::TryParse([string]$p.id,[ref]$id) -or $id -le 0 -or $id -gt 4294967295){return}
 $text=[string]$p.text;if([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 160){return}
 $key=('{0}:{1}' -f $p.boot,$id)
 if($script:Seen -notcontains $key){
  $r=[pscustomobject]@{Key=$key;Text=$text;Source=[string]$p.source;At=(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')}
  $records=@(@($r)+@($script:Records)|Select-Object -First 100)
  $seen=@(@($key)+@($script:Seen)|Select-Object -First 500)
  # Confirma apenas depois de salvar; nao marca como recebido se o disco falhar.
  Write-JsonAtomic $script:HistoryFile @{Records=$records;Seen=$seen}
  $script:Records=$records;$script:Seen=$seen;Render-History
  Alert-Message $text ([string]$p.source)
 }
 Send-Line ('RONI_PC_ACK {0} {1}' -f $p.boot,$id)
}
function Refresh-Ports {
 $script:LastScan=[datetime]::UtcNow
 $names=@([IO.Ports.SerialPort]::GetPortNames()|Sort-Object)
 $script:UpdatingPorts=$true;$script:UI.Ports.Items.Clear();[void]$script:UI.Ports.Items.Add('Auto')
 foreach($n in $names){[void]$script:UI.Ports.Items.Add($n)}
 if($script:Settings.Port -ne 'Auto' -and $names -notcontains $script:Settings.Port){[void]$script:UI.Ports.Items.Add($script:Settings.Port)}
 $script:UI.Ports.SelectedItem=$script:Settings.Port;$script:UpdatingPorts=$false
 if($script:Settings.Port -ne 'Auto'){$script:Candidates=@($script:Settings.Port);return}
 # Auto so abre dispositivos Espressif. Outras portas exigem selecao manual.
 $found=@()
 try{foreach($dev in @(Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE '%VID_303A%'" -ErrorAction Stop)){
  if([string]$dev.Name -match '\((COM\d+)\)'){$portName=$Matches[1];if($names -contains $portName){$found+=$portName}}
 }}catch{}
 $script:Candidates=@($found|Sort-Object -Unique)
}
function Toggle-Pause {
 $script:Paused=-not $script:Paused;Disconnect-Roni
 if($script:Paused){$script:UI.Pause.Content='Retomar conexão USB';Set-State 'USB liberada' 'Agora você pode usar a Arduino IDE e o Monitor Serial. Clique em Retomar quando terminar.' 'Ⅱ  Pausado'}
 else{$script:UI.Pause.Content='Pausar USB / programar';$script:LastScan=[datetime]::MinValue;Set-State 'Procurando o RONI' 'Feche o Monitor Serial para liberar a porta USB.' '●  Procurando USB'}
}
function Quit-Roni { $script:Closing=$true;$script:Window.Close() }
$script:Timer=New-Object System.Windows.Threading.DispatcherTimer;$script:Timer.Interval=[timespan]::FromMilliseconds(120)
$script:Timer.Add_Tick({
 try{
  if(Test-Path -LiteralPath $script:ExitFile){Remove-Item -LiteralPath $script:ExitFile -Force;Quit-Roni;return}
  if(Test-Path -LiteralPath $script:ShowFile){Remove-Item -LiteralPath $script:ShowFile -Force;Show-Main}
  foreach($p in @($script:Popups)){if([datetime]::UtcNow -gt $p.Until){$p.Window.Close();[void]$script:Popups.Remove($p)}}
  if($script:Paused -or $Demo){return}
  $now=[datetime]::UtcNow
  if($null -eq $script:Port){
   if(($now-$script:LastScan).TotalSeconds -lt 5){return}
   Refresh-Ports
   if($script:Candidates.Count -eq 0){Set-State 'Aguardando o RONI' 'Conecte a USB de dados. Se necessário, escolha a COM manualmente. Feche o Monitor Serial da Arduino IDE.' '●  Aguardando USB';return}
   $name=$script:Candidates[$script:CandidateIndex % $script:Candidates.Count];$script:CandidateIndex++
   $s=New-Object System.IO.Ports.SerialPort($name,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
   $s.ReadTimeout=30;$s.WriteTimeout=150;$s.DtrEnable=$true;$s.RtsEnable=$false;$s.Encoding=New-Object System.Text.UTF8Encoding($false);$s.NewLine="`n"
   try{$s.Open();$script:Port=$s;$script:Buffer='';$script:OpenedAt=$now;$script:LastHello=[datetime]::MinValue;Set-State 'Identificando o RONI' ('Verificando '+$name+'…') '●  Conectando USB'}
   catch{$s.Dispose();Set-State 'Porta ocupada ou indisponível' 'Feche o Monitor Serial da Arduino IDE. Depois tentaremos novamente.' '●  Aguardando porta'}
   return
  }
  $chunk=$script:Port.ReadExisting()
  if($chunk){$script:Buffer+=$chunk}
  $lines=0
  while($script:Buffer.Contains("`n") -and $lines -lt 30){
   $i=$script:Buffer.IndexOf("`n");$line=$script:Buffer.Substring(0,$i).TrimEnd("`r");$script:Buffer=$script:Buffer.Substring($i+1);$lines++;Accept-Line $line
  }
  if($script:Buffer.Length -gt 16384){$script:Buffer=''}
  if(($now-$script:LastHello).TotalSeconds -ge 5){Send-Line 'RONI_PC_HELLO';$script:LastHello=$now}
  if((-not $script:Verified -and ($now-$script:OpenedAt).TotalSeconds -gt 7) -or ($script:Verified -and ($now-$script:LastSeen).TotalSeconds -gt 22)){
   Disconnect-Roni;Set-State 'RONI ainda não respondeu' 'Confira se gravou a versão V12 e se está usando a mesma USB de dados da programação.' '●  Tentando novamente'
  }
 }catch{Disconnect-Roni;Set-State 'Conexão interrompida' 'Reconecte a USB. O aplicativo tentará novamente sozinho.' '●  Reconectando USB'}
})
$script:UI.Sound.IsChecked=$script:Settings.Sound;$script:UI.Popup.IsChecked=$script:Settings.Popup;$script:UI.Startup.IsChecked=Test-Path -LiteralPath (Get-StartupPath)
$script:UI.Sound.Add_Click({$script:Settings.Sound=[bool]$script:UI.Sound.IsChecked;Save-Settings})
$script:UI.Popup.Add_Click({$script:Settings.Popup=[bool]$script:UI.Popup.IsChecked;Save-Settings})
$script:UI.Startup.Add_Click({try{Set-Startup ([bool]$script:UI.Startup.IsChecked)}catch{[Windows.MessageBox]::Show('Não foi possível alterar o início automático.','RONI')|Out-Null}})
$script:UI.Test.Add_Click({Alert-Message 'Oi! Quando uma mensagem chegar ao RONI, eu aviso por aqui.' 'Teste local'})
$script:UI.Hide.Add_Click({$script:Window.Hide()})
$script:UI.Pause.Add_Click({Toggle-Pause})
$script:UI.Refresh.Add_Click({$script:LastScan=[datetime]::MinValue})
$script:UI.Ports.Add_SelectionChanged({if(-not $script:UpdatingPorts -and $script:UI.Ports.SelectedItem){$script:Settings.Port=[string]$script:UI.Ports.SelectedItem;Save-Settings;Disconnect-Roni;$script:LastScan=[datetime]::MinValue}})
$script:UI.Clear.Add_Click({if([Windows.MessageBox]::Show('Apagar o histórico deste computador?','RONI','YesNo','Question') -eq 'Yes'){$script:Records=@();Write-JsonAtomic $script:HistoryFile @{Records=@();Seen=$script:Seen};Render-History}})
$miOpen.Add_Click({Show-Main});$miPause.Add_Click({Toggle-Pause});$miExit.Add_Click({Quit-Roni});$script:Tray.Add_DoubleClick({Show-Main})
$script:Window.Add_Closing({param($sender,$e) if(-not $script:Closing){$e.Cancel=$true;$script:Window.Hide()}})
$script:Window.Add_StateChanged({if($script:Window.WindowState -eq 'Minimized'){$script:Window.Hide()}})
$script:Window.Add_Closed({$script:Timer.Stop();Disconnect-Roni;foreach($p in @($script:Popups)){$p.Window.Close()};$script:Tray.Visible=$false;$script:Tray.Dispose();[Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown()})
try{
 Render-History;Refresh-Ports;$script:Timer.Start()
 if(-not $Background){Show-Main}
 [Windows.Threading.Dispatcher]::Run()
} finally {
 Disconnect-Roni;$script:Tray.Dispose();$script:SoundPlayer.Dispose();$script:Mutex.ReleaseMutex();$script:Mutex.Dispose()
}
