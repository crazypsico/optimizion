#requires -RunAsAdministrator
<#!
.SYNOPSIS
  HunterOptimization - Otimizador extremo para Windows 10/11.
.DESCRIPTION
  Script profissional com menu interativo, backups, restore point,
  snapshot de serviços, logs detalhados e reversão total.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Global:ProjectName = 'HunterOptimization'
$Global:RootDir = Join-Path $env:ProgramData $ProjectName
$Global:LogDir = Join-Path $Global:RootDir 'Logs'
$Global:BackupDir = Join-Path $Global:RootDir 'Backups'
$Global:StateFile = Join-Path $Global:RootDir 'state.json'
$Global:ServiceStateFile = Join-Path $Global:RootDir 'services.json'
$Global:RegBackupListFile = Join-Path $Global:RootDir 'reg-backups.txt'

function Initialize-Environment {
  New-Item -Path $Global:RootDir -ItemType Directory -Force | Out-Null
  New-Item -Path $Global:LogDir -ItemType Directory -Force | Out-Null
  New-Item -Path $Global:BackupDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
  param(
    [Parameter(Mandatory)]
    [string]$Message,
    [ValidateSet('INFO','WARN','ERROR')]
    [string]$Level = 'INFO'
  )
  $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $line = "[$timestamp][$Level] $Message"
  $logFile = Join-Path $Global:LogDir "HunterOptimization-$(Get-Date -Format yyyyMMdd).log"
  $line | Out-File -FilePath $logFile -Append -Encoding utf8
  Write-Host $line
}

function Create-RestorePoint {
  Write-Log 'Criando ponto de restauração do sistema...'
  try {
    Checkpoint-Computer -Description "$Global:ProjectName" -RestorePointType 'MODIFY_SETTINGS'
    Write-Log 'Ponto de restauração criado com sucesso.'
  } catch {
    Write-Log "Falha ao criar ponto de restauração: $($_.Exception.Message)" 'WARN'
  }
}

function Backup-RegistryKey {
  param(
    [Parameter(Mandatory)]
    [string]$KeyPath
  )
  $safeName = $KeyPath -replace '[\\/:*?"<>|]', '_'
  $backupFile = Join-Path $Global:BackupDir "$safeName.reg"
  if (-not (Test-Path $backupFile)) {
    Write-Log "Backup REG: $KeyPath -> $backupFile"
    & reg.exe export "$KeyPath" "$backupFile" /y | Out-Null
    Add-Content -Path $Global:RegBackupListFile -Value $backupFile
  }
}

function Backup-Registry {
  Write-Log 'Gerando backup completo das chaves que serão alteradas...'
  if (Test-Path $Global:RegBackupListFile) {
    Remove-Item $Global:RegBackupListFile -Force
  }
}

function Snapshot-Services {
  Write-Log 'Gerando snapshot de serviços...'
  $services = Get-Service | Select-Object Name, DisplayName, Status, StartType
  $services | ConvertTo-Json -Depth 3 | Out-File -FilePath $Global:ServiceStateFile -Encoding utf8
}

function Save-State {
  param(
    [Parameter(Mandatory)]
    [array]$Entries
  )
  $Entries | ConvertTo-Json -Depth 5 | Out-File -FilePath $Global:StateFile -Encoding utf8
}

function Load-State {
  if (-not (Test-Path $Global:StateFile)) {
    return @()
  }
  return Get-Content $Global:StateFile -Raw | ConvertFrom-Json
}

function Apply-RegistryValue {
  param(
    [Parameter(Mandatory)]
    [string]$Hive,
    [Parameter(Mandatory)]
    [string]$Path,
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [ValidateSet('DWord','QWord','String')]
    [string]$Type,
    [Parameter(Mandatory)]
    [object]$Value,
    [Parameter(Mandatory)]
    [System.Collections.Generic.List[object]]$State
  )

  $fullPath = "Registry::$Hive\\$Path"
  if (-not (Test-Path $fullPath)) {
    New-Item -Path $fullPath -Force | Out-Null
  }

  $existing = Get-ItemProperty -Path $fullPath -Name $Name -ErrorAction SilentlyContinue
  $oldExists = $false
  $oldValue = $null
  if ($null -ne $existing) {
    $oldExists = $true
    $oldValue = $existing.$Name
  }

  $State.Add([pscustomobject]@{
    Hive = $Hive
    Path = $Path
    Name = $Name
    Type = $Type
    OldExists = $oldExists
    OldValue = $oldValue
  }) | Out-Null

  $keyPath = "$Hive\\$Path"
  Backup-RegistryKey -KeyPath $keyPath

  Write-Log "REGEDIT: $Hive\\$Path -> $Name = $Value ($Type)"
  Set-ItemProperty -Path $fullPath -Name $Name -Value $Value -Type $Type
}

function Apply-ServiceChange {
  param(
    [Parameter(Mandatory)]
    [string]$ServiceName,
    [Parameter(Mandatory)]
    [ValidateSet('Disabled','Manual','Automatic')]
    [string]$StartupType,
    [Parameter(Mandatory)]
    [System.Collections.Generic.List[object]]$State
  )

  $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  if ($null -eq $svc) {
    Write-Log "Serviço $ServiceName não encontrado." 'WARN'
    return
  }

  Write-Log "O QUE: Ajuste de serviço $ServiceName."
  Write-Log "POR QUE: Reduz serviços em background para menor latência."
  Write-Log "RISCO: Pode afetar funcionalidades associadas ao serviço."
  Write-Log "REVERSÃO: Usar a função Reverter para restaurar StartType e Status."

  $State.Add([pscustomobject]@{
    ServiceName = $ServiceName
    OldStartType = $svc.StartType
    OldStatus = $svc.Status
  }) | Out-Null

  Write-Log "SERVIÇO: $ServiceName -> StartupType: $StartupType"
  Set-Service -Name $ServiceName -StartupType $StartupType
  if ($StartupType -eq 'Disabled' -and $svc.Status -eq 'Running') {
    Stop-Service -Name $ServiceName -Force
  }
}

function Apply-NetworkInterfaceTweaks {
  param(
    [Parameter(Mandatory)]
    [System.Collections.Generic.List[object]]$State,
    [ValidateSet('Basic','Aggressive','Extreme')]
    [string]$Level
  )

  $baseKey = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
  $interfaces = Get-ChildItem "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
  foreach ($iface in $interfaces) {
    $path = $iface.PSChildName
    Write-Log 'O QUE: Ajustes TCP (TcpAckFrequency/TCPNoDelay) por interface.'
    Write-Log 'POR QUE: Reduz latência desabilitando Nagle/ACK delay.'
    Write-Log 'RISCO: Pode aumentar uso de CPU e tráfego pequeno.'
    Write-Log 'REVERSÃO: Usar a função Reverter para restaurar valores.'
    Apply-RegistryValue -Hive 'HKEY_LOCAL_MACHINE' -Path "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$path" -Name 'TcpAckFrequency' -Type DWord -Value 1 -State $State
    Apply-RegistryValue -Hive 'HKEY_LOCAL_MACHINE' -Path "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$path" -Name 'TCPNoDelay' -Type DWord -Value 1 -State $State
    if ($Level -eq 'Extreme') {
      Write-Log 'O QUE: Define MTU fixo por interface.'
      Write-Log 'POR QUE: Evita fragmentação em alguns cenários.'
      Write-Log 'RISCO: MTU incorreto pode causar perda de pacotes.'
      Write-Log 'REVERSÃO: Usar a função Reverter para restaurar valores.'
      Apply-RegistryValue -Hive 'HKEY_LOCAL_MACHINE' -Path "SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$path" -Name 'MTU' -Type DWord -Value 1500 -State $State
    }
  }
}

function Build-Tweaks {
  param(
    [ValidateSet('Basic','Aggressive','Extreme')]
    [string]$Level
  )

  $tweaks = @()

  # CPU & Kernel
  $tweaks += [pscustomobject]@{ Level = 'Basic'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\PriorityControl'; Name='Win32PrioritySeparation'; Type='DWord'; Value=26; What='Ajusta prioridade do scheduler para foreground apps.'; Why='Favorece jogos e apps em primeiro plano.'; Risk='Pode reduzir responsividade de serviços em background.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Aggressive'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\PriorityControl'; Name='Win32PrioritySeparation'; Type='DWord'; Value=38; What='Aumenta quantum para processos foreground.'; Why='Melhora FPS e estabilidade de frame time.'; Risk='Pode afetar tarefas em background.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Extreme'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\PriorityControl'; Name='Win32PrioritySeparation'; Type='DWord'; Value=40; What='Scheduler agressivo para foreground.'; Why='Minimiza latência do processo principal.'; Risk='Impacto em multitarefa pesada.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Basic'; Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name='SystemResponsiveness'; Type='DWord'; Value=0; What='Remove reserva de CPU para multimedia background.'; Why='Libera CPU para jogo.'; Risk='Pode afetar streaming em background.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Basic'; Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name='NetworkThrottlingIndex'; Type='DWord'; Value=0xffffffff; What='Desativa throttling de rede multimídia.'; Why='Reduz latência de rede.'; Risk='Pode aumentar uso de CPU em rede.'; Revert='Reverter para valor anterior via função Reverter.' }

  # Memory
  $tweaks += [pscustomobject]@{ Level = 'Basic'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name='DisablePagingExecutive'; Type='DWord'; Value=1; What='Mantém partes do kernel na RAM.'; Why='Reduz paginação e melhora latência.'; Risk='Aumenta uso de RAM.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Aggressive'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; Name='LargeSystemCache'; Type='DWord'; Value=0; What='Desativa cache de servidor em desktop.'; Why='Prioriza apps em vez de cache.'; Risk='Pode reduzir desempenho de arquivos em cache.'; Revert='Reverter para valor anterior via função Reverter.' }

  # Disk
  $tweaks += [pscustomobject]@{ Level = 'Aggressive'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name='EnablePrefetcher'; Type='DWord'; Value=0; What='Desativa Prefetch.'; Why='Reduz I/O em SSDs e stutter.'; Risk='Pode aumentar tempo de abertura de apps.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Aggressive'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'; Name='EnableSuperfetch'; Type='DWord'; Value=0; What='Desativa Superfetch/SysMain.'; Why='Reduz uso de disco e RAM.'; Risk='Pode reduzir pré-carregamento.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Extreme'; Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name='DisableIndexing'; Type='DWord'; Value=1; What='Desativa indexação.'; Why='Reduz I/O e CPU em background.'; Risk='Busca de arquivos mais lenta.'; Revert='Reverter para valor anterior via função Reverter.' }

  # GPU & Jogos
  $tweaks += [pscustomobject]@{ Level = 'Basic'; Hive='HKEY_CURRENT_USER'; Path='System\GameConfigStore'; Name='GameDVR_Enabled'; Type='DWord'; Value=0; What='Desativa GameDVR.'; Why='Reduz overhead e latência.'; Risk='Perde gravação automática.'; Revert='Reverter para valor anterior via função Reverter.' }
  $tweaks += [pscustomobject]@{ Level = 'Basic'; Hive='HKEY_CURRENT_USER'; Path='SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'; Name='AppCaptureEnabled'; Type='DWord'; Value=0; What='Desativa captura em background.'; Why='Remove hooks de captura.'; Risk='Sem gravação via Game Bar.'; Revert='Reverter para valor anterior via função Reverter.' }

  # Telemetria
  $tweaks += [pscustomobject]@{ Level = 'Aggressive'; Hive='HKEY_LOCAL_MACHINE'; Path='SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name='AllowTelemetry'; Type='DWord'; Value=0; What='Desativa telemetria.'; Why='Menos serviços e upload.'; Risk='Alguns recursos de diagnóstico ficam limitados.'; Revert='Reverter para valor anterior via função Reverter.' }

  # Boot
  $tweaks += [pscustomobject]@{ Level = 'Basic'; Hive='HKEY_LOCAL_MACHINE'; Path='SYSTEM\CurrentControlSet\Control\Session Manager\Power'; Name='HiberbootEnabled'; Type='DWord'; Value=1; What='Ativa Fast Startup.'; Why='Boot mais rápido.'; Risk='Dual-boot pode ter problemas.'; Revert='Reverter para valor anterior via função Reverter.' }

  $applySet = @('Basic')
  if ($Level -eq 'Aggressive') { $applySet = @('Basic','Aggressive') }
  if ($Level -eq 'Extreme') { $applySet = @('Basic','Aggressive','Extreme') }

  return $tweaks | Where-Object { $applySet -contains $_.Level }
}

function Apply-Optimizations {
  param(
    [ValidateSet('Basic','Aggressive','Extreme')]
    [string]$Level
  )

  Initialize-Environment
  Write-Log "Iniciando otimizações nível: $Level"
  Create-RestorePoint
  Backup-Registry
  Snapshot-Services

  $state = New-Object 'System.Collections.Generic.List[object]'
  $serviceState = New-Object 'System.Collections.Generic.List[object]'

  $tweaks = Build-Tweaks -Level $Level
  foreach ($tweak in $tweaks) {
    if ($tweak.What) { Write-Log "O QUE: $($tweak.What)" }
    if ($tweak.Why) { Write-Log "POR QUE: $($tweak.Why)" }
    if ($tweak.Risk) { Write-Log "RISCO: $($tweak.Risk)" }
    if ($tweak.Revert) { Write-Log "REVERSÃO: $($tweak.Revert)" }
    Apply-RegistryValue -Hive $tweak.Hive -Path $tweak.Path -Name $tweak.Name -Type $tweak.Type -Value $tweak.Value -State $state
  }

  Apply-NetworkInterfaceTweaks -State $state -Level $Level

  if ($Level -eq 'Aggressive') {
    Apply-ServiceChange -ServiceName 'DiagTrack' -StartupType Disabled -State $serviceState
    Apply-ServiceChange -ServiceName 'dmwappushservice' -StartupType Disabled -State $serviceState
  }

  if ($Level -eq 'Extreme') {
    Apply-ServiceChange -ServiceName 'SysMain' -StartupType Disabled -State $serviceState
    Apply-ServiceChange -ServiceName 'WSearch' -StartupType Disabled -State $serviceState
    Apply-ServiceChange -ServiceName 'WindowsUpdate' -StartupType Manual -State $serviceState
  }

  Save-State -Entries $state
  $serviceState | ConvertTo-Json -Depth 5 | Out-File -FilePath $Global:ServiceStateFile -Encoding utf8

  Write-Log 'Otimizações aplicadas. Reinicie o PC para efeito completo.'
}

function Revert-Optimizations {
  Initialize-Environment
  Write-Log 'Revertendo todas as alterações...'
  $state = Load-State

  foreach ($entry in $state) {
    $fullPath = "Registry::$($entry.Hive)\\$($entry.Path)"
    if (-not (Test-Path $fullPath)) {
      continue
    }

    if ($entry.OldExists -eq $true) {
      Write-Log "REVERTER REG: $($entry.Hive)\\$($entry.Path) -> $($entry.Name) = $($entry.OldValue)"
      Set-ItemProperty -Path $fullPath -Name $entry.Name -Value $entry.OldValue
    } else {
      Write-Log "REMOVER REG: $($entry.Hive)\\$($entry.Path) -> $($entry.Name)"
      Remove-ItemProperty -Path $fullPath -Name $entry.Name -ErrorAction SilentlyContinue
    }
  }

  if (Test-Path $Global:ServiceStateFile) {
    $services = Get-Content $Global:ServiceStateFile -Raw | ConvertFrom-Json
    foreach ($svc in $services) {
      Write-Log "REVERTER SERVIÇO: $($svc.ServiceName) -> $($svc.OldStartType)"
      Set-Service -Name $svc.ServiceName -StartupType $svc.OldStartType
      if ($svc.OldStatus -eq 'Running') {
        Start-Service -Name $svc.ServiceName
      }
    }
  }

  Write-Log 'Reversão concluída. Reinicie o PC.'
}

function Show-Info {
  @'
USO BÁSICO
1) Execute como Administrador.
2) Escolha o nível de otimização.
3) Reinicie o PC.
4) Para desfazer, use "Reverter tudo".

COMO GERAR HunterOptimization.exe
- Instale o PS2EXE: Install-Module ps2exe -Scope CurrentUser
- Converta: Invoke-PS2EXE .\HunterOptimization.ps1 .\HunterOptimization.exe

RECOMENDAÇÕES PARA NOTEBOOKS FRACOS
- Use o nível Básico primeiro.
- Evite Extreme se o notebook depende de Windows Update frequente.
- Mantenha o perfil de energia em Alto Desempenho.

CONSIDERAÇÕES PARA PCs ARM
- As otimizações de registry são compatíveis, mas drivers ARM podem reagir diferente.
- Teste primeiro o nível Básico e monitore estabilidade.
'@ | Write-Host
}

function Show-Menu {
  Clear-Host
  Write-Host '========================================'
  Write-Host " $Global:ProjectName - Otimizador Extremo"
  Write-Host '========================================'
  Write-Host '1) Aplicar Básico'
  Write-Host '2) Aplicar Agressivo'
  Write-Host '3) Aplicar EXTREME MODE'
  Write-Host '4) REVERTER TUDO'
  Write-Host '5) Informações e uso'
  Write-Host '0) Sair'
}

function Confirm-Action {
  param(
    [Parameter(Mandatory)]
    [string]$Message
  )
  $response = Read-Host "$Message (S/N)"
  return $response -match '^[sS]$'
}

function Main {
  Initialize-Environment
  while ($true) {
    Show-Menu
    $choice = Read-Host 'Selecione uma opção'
    switch ($choice) {
      '1' {
        if (Confirm-Action -Message 'Aplicar nível Básico?') {
          Apply-Optimizations -Level 'Basic'
        }
      }
      '2' {
        Write-Host 'AVISO: nível Agressivo altera telemetria e serviços.'
        if (Confirm-Action -Message 'Aplicar nível Agressivo?') {
          Apply-Optimizations -Level 'Aggressive'
        }
      }
      '3' {
        Write-Host 'AVISO: EXTREME MODE pode impactar updates e serviços críticos.'
        if (Confirm-Action -Message 'Aplicar EXTREME MODE?') {
          Apply-Optimizations -Level 'Extreme'
        }
      }
      '4' {
        if (Confirm-Action -Message 'Reverter TUDO?') {
          Revert-Optimizations
        }
      }
      '5' { Show-Info }
      '0' { break }
      Default { Write-Host 'Opção inválida.' }
    }
    Read-Host 'Pressione Enter para continuar'
  }
}

Main
