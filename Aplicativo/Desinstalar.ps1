#requires -Version 5.1
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
if([Windows.MessageBox]::Show('Remover o aplicativo RONI deste usuário? O programa da ESP32 não será alterado.','Desinstalar RONI','YesNo','Question') -ne 'Yes'){exit}
$data=Join-Path $env:LOCALAPPDATA 'RONICompanion'
$keep=[Windows.MessageBox]::Show('Deseja manter o histórico de mensagens e as preferências?','RONI','YesNo','Question') -eq 'Yes'
try{
 [IO.File]::WriteAllText((Join-Path $data 'sair.request'),'sair');Start-Sleep -Milliseconds 1000
 foreach($dir in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('Startup'))){
  foreach($name in 'RONI Companion.lnk','Desinstalar RONI Companion.lnk'){$path=Join-Path $dir $name;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}
 }
 $app=Join-Path $data 'App';if(Test-Path -LiteralPath $app){Remove-Item -LiteralPath $app -Recurse -Force}
 $req=Join-Path $data 'sair.request';if(Test-Path -LiteralPath $req){Remove-Item -LiteralPath $req -Force}
 if(-not $keep){Remove-Item -LiteralPath $data -Recurse -Force}
 [Windows.MessageBox]::Show('RONI removido deste computador.','RONI')|Out-Null
}catch{[Windows.MessageBox]::Show('Feche o RONI junto ao relógio e tente novamente. '+$_.Exception.Message,'RONI')|Out-Null}
