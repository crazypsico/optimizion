#requires -RunAsAdministrator
<#[
HUNTEROPTIMIZATION - OTIMIZADOR EXTREMO PARA WINDOWS 10/11
Autor: HunterOptimization

Este script aplica otimizações via REGEDIT, serviços e políticas com foco em FPS, latência e performance.
Inclui backup completo do registro, ponto de restauração, snapshot de serviços e logs detalhados.

IMPORTANTE: Use por sua conta e risco. Sempre tenha backup.
#]>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectName = 'HunterOptimization'
$BaseDir = Join-Path -Path $env:ProgramData -ChildPath $ProjectName
$BackupDir = Join-Path -Path $BaseDir -ChildPath 'Backups'
$LogDir = Join-Path -Path $BaseDir -ChildPath 'Logs'
$ServiceSnapshotPath = Join-Path -Path $BackupDir -ChildPath "services_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$RegistryBackupHKLM = Join-Path -Path $BackupDir -ChildPath "HKLM_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
$RegistryBackupHKCU = Join-Path -Path $BackupDir -ChildPath "HKCU_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
$StateFile = Join-Path -Path $BackupDir -ChildPath "state_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$TranscriptPath = Join-Path -Path $LogDir -ChildPath "hunter_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

New-Item -Path $BackupDir -ItemType Directory -Force | Out-Null
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

Start-Transcript -Path $TranscriptPath -Force | Out-Null

function Assert-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Execute este script como Administrador.' -ForegroundColor Red
        Stop-Transcript | Out-Null
        exit 1
    }
}

function New-SystemRestorePoint {
    Write-Host 'Criando ponto de restauração...' -ForegroundColor Cyan
    try {
        Checkpoint-Computer -Description "${ProjectName}_PreOptimize" -RestorePointType 'MODIFY_SETTINGS'
    } catch {
        Write-Warning "Falha ao criar ponto de restauração: $($_.Exception.Message)"
    }
}

function Backup-Registry {
    Write-Host 'Backup completo do REGEDIT (HKLM e HKCU)...' -ForegroundColor Cyan
    & reg.exe export HKLM "$RegistryBackupHKLM" /y | Out-Null
    & reg.exe export HKCU "$RegistryBackupHKCU" /y | Out-Null
}

function Snapshot-Services {
    Write-Host 'Criando snapshot de serviços...' -ForegroundColor Cyan
    Get-CimInstance Win32_Service |
        Select-Object Name, DisplayName, StartMode, State, PathName |
        Export-Csv -NoTypeInformation -Encoding UTF8 -Path $ServiceSnapshotPath
}

function Save-State {
    $state = [ordered]@{
        RegistryBackupHKLM = $RegistryBackupHKLM
        RegistryBackupHKCU = $RegistryBackupHKCU
        ServiceSnapshotPath = $ServiceSnapshotPath
        Timestamp = (Get-Date).ToString('o')
    }
    $state | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('String','DWord','QWord','Binary','MultiString','ExpandString')] [string] $Type,
        [Parameter(Mandatory)] $Value
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function Apply-Optimizations {
    param(
        [Parameter(Mandatory)] [ValidateSet('Basic','Aggressive','Extreme')] [string] $Level
    )

    Write-Host "Aplicando otimizações: $Level" -ForegroundColor Green

    $optimizations = @()

    # CPU & KERNEL
    $optimizations += [ordered]@{
        Name = 'Prioridade de thread para foreground (Win32PrioritySeparation)'
        Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
        Key = 'Win32PrioritySeparation'
        Type = 'DWord'
        Value = 38
        What = 'Aumenta prioridade para apps em foreground'
        Why = 'Mais CPU dedicada ao jogo/app ativo'
        Risk = 'Pode reduzir performance de tarefas em background'
        Revert = 'Importar backup do REGEDIT'
    }

    $optimizations += [ordered]@{
        Name = 'Desativar throttling de sistema multimídia'
        Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Key = 'SystemResponsiveness'
        Type = 'DWord'
        Value = 0
        What = 'Remove reserva de CPU para tarefas em background'
        Why = 'Menor latência e mais FPS'
        Risk = 'Streaming/áudio podem competir por CPU'
        Revert = 'Importar backup do REGEDIT'
    }

    # MEMÓRIA
    $optimizations += [ordered]@{
        Name = 'DisablePagingExecutive'
        Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        Key = 'DisablePagingExecutive'
        Type = 'DWord'
        Value = 1
        What = 'Mantém kernel/drivers na RAM'
        Why = 'Reduz page faults e melhora responsividade'
        Risk = 'Maior uso de RAM'
        Revert = 'Importar backup do REGEDIT'
    }

    $optimizations += [ordered]@{
        Name = 'LargeSystemCache'
        Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        Key = 'LargeSystemCache'
        Type = 'DWord'
        Value = 0
        What = 'Desativa cache agressivo para servidor'
        Why = 'Libera RAM para apps/jogos'
        Risk = 'Cache de arquivos menor'
        Revert = 'Importar backup do REGEDIT'
    }

    # DISCO
    $optimizations += [ordered]@{
        Name = 'Desativar Prefetch'
        Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
        Key = 'EnablePrefetcher'
        Type = 'DWord'
        Value = 0
        What = 'Desativa prefetch de apps'
        Why = 'Menos IO em SSD/NVMe'
        Risk = 'Boot pode ficar mais lento em HDD'
        Revert = 'Importar backup do REGEDIT'
    }

    $optimizations += [ordered]@{
        Name = 'Desativar Superfetch'
        Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters'
        Key = 'EnableSuperfetch'
        Type = 'DWord'
        Value = 0
        What = 'Desativa Superfetch/SysMain'
        Why = 'Reduz uso de disco e RAM'
        Risk = 'Pode afetar carregamento de apps em HDD'
        Revert = 'Importar backup do REGEDIT'
    }

    # GPU & JOGOS
    $optimizations += [ordered]@{
        Name = 'Desativar GameDVR'
        Path = 'HKCU:\System\GameConfigStore'
        Key = 'GameDVR_Enabled'
        Type = 'DWord'
        Value = 0
        What = 'Desativa gravação em segundo plano'
        Why = 'Menos uso de CPU/GPU'
        Risk = 'Perde captura automática'
        Revert = 'Importar backup do REGEDIT'
    }

    $optimizations += [ordered]@{
        Name = 'Desativar AppCaptureEnabled'
        Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
        Key = 'AppCaptureEnabled'
        Type = 'DWord'
        Value = 0
        What = 'Desativa captura de tela Xbox Game Bar'
        Why = 'Menos overhead'
        Risk = 'Perde gravação Game Bar'
        Revert = 'Importar backup do REGEDIT'
    }

    # REDE
    $optimizations += [ordered]@{
        Name = 'NetworkThrottlingIndex'
        Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Key = 'NetworkThrottlingIndex'
        Type = 'DWord'
        Value = 0xffffffff
        What = 'Desativa throttling de rede multimídia'
        Why = 'Menor latência em jogos online'
        Risk = 'Pode aumentar uso de rede'
        Revert = 'Importar backup do REGEDIT'
    }

    # TELEMETRIA
    $optimizations += [ordered]@{
        Name = 'AllowTelemetry'
        Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        Key = 'AllowTelemetry'
        Type = 'DWord'
        Value = 0
        What = 'Bloqueia telemetria'
        Why = 'Menos uso de CPU/disco e privacidade'
        Risk = 'Alguns diagnósticos limitados'
        Revert = 'Importar backup do REGEDIT'
    }

    if ($Level -in @('Aggressive','Extreme')) {
        $optimizations += [ordered]@{
            Name = 'Desativar Windows Search (WSearch)'
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\WSearch'
            Key = 'Start'
            Type = 'DWord'
            Value = 4
            What = 'Desativa serviço de indexação'
            Why = 'Menos uso de disco/CPU'
            Risk = 'Busca de arquivos mais lenta'
            Revert = 'Importar backup do REGEDIT'
        }

        $optimizations += [ordered]@{
            Name = 'Desativar SysMain'
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\SysMain'
            Key = 'Start'
            Type = 'DWord'
            Value = 4
            What = 'Desativa pré-carregamento inteligente'
            Why = 'Reduz picos de disco'
            Risk = 'Apps podem abrir mais lento em HDD'
            Revert = 'Importar backup do REGEDIT'
        }
    }

    if ($Level -eq 'Extreme') {
        $optimizations += [ordered]@{
            Name = 'Desativar Windows Update'
            Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\wuauserv'
            Key = 'Start'
            Type = 'DWord'
            Value = 4
            What = 'Desativa updates automáticos'
            Why = 'Evita uso de CPU/disco durante jogos'
            Risk = 'Sem atualizações de segurança'
            Revert = 'Importar backup do REGEDIT'
        }

        $optimizations += [ordered]@{
            Name = 'Desativar efeitos visuais'
            Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
            Key = 'VisualFXSetting'
            Type = 'DWord'
            Value = 2
            What = 'Define melhor desempenho visual'
            Why = 'Menos uso de GPU/CPU'
            Risk = 'UI menos bonita'
            Revert = 'Importar backup do REGEDIT'
        }
    }

    foreach ($opt in $optimizations) {
        Write-Host "Aplicando: $($opt.Name)" -ForegroundColor Yellow
        Write-Host "O QUE: $($opt.What)"
        Write-Host "CHAVE: $($opt.Path)\\$($opt.Key)"
        Write-Host "POR QUE: $($opt.Why)"
        Write-Host "RISCO: $($opt.Risk)"
        Write-Host "REVERTER: $($opt.Revert)"
        Set-RegistryValue -Path $opt.Path -Name $opt.Key -Type $opt.Type -Value $opt.Value
    }

    # Nagle / TCP em todas as interfaces
    $interfacesPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if (Test-Path $interfacesPath) {
        Get-ChildItem -Path $interfacesPath | ForEach-Object {
            Set-RegistryValue -Path $_.PSPath -Name 'TcpAckFrequency' -Type 'DWord' -Value 1
            Set-RegistryValue -Path $_.PSPath -Name 'TCPNoDelay' -Type 'DWord' -Value 1
            Set-RegistryValue -Path $_.PSPath -Name 'TcpDelAckTicks' -Type 'DWord' -Value 0
        }
        Write-Host 'Nagle Algorithm desativado em todas as interfaces.' -ForegroundColor Yellow
    }

    Write-Host 'Otimizações aplicadas. Reinicie o computador para efeito total.' -ForegroundColor Green
}

function Restore-All {
    Write-Host 'Restaurando configurações via backups...' -ForegroundColor Cyan

    $latestState = Get-ChildItem -Path $BackupDir -Filter 'state_*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latestState) {
        Write-Host 'Nenhum backup encontrado.' -ForegroundColor Red
        return
    }

    $state = Get-Content -Path $latestState.FullName -Raw | ConvertFrom-Json

    if (Test-Path $state.RegistryBackupHKLM) {
        & reg.exe import "$($state.RegistryBackupHKLM)" | Out-Null
    }
    if (Test-Path $state.RegistryBackupHKCU) {
        & reg.exe import "$($state.RegistryBackupHKCU)" | Out-Null
    }

    if (Test-Path $state.ServiceSnapshotPath) {
        $services = Import-Csv -Path $state.ServiceSnapshotPath
        foreach ($svc in $services) {
            try {
                if ($svc.StartMode) {
                    $startMode = $svc.StartMode
                    $svcName = $svc.Name
                    switch ($startMode) {
                        'Auto' { sc.exe config $svcName start= auto | Out-Null }
                        'Manual' { sc.exe config $svcName start= demand | Out-Null }
                        'Disabled' { sc.exe config $svcName start= disabled | Out-Null }
                    }
                }
            } catch {
                Write-Warning "Falha ao restaurar serviço $($svc.Name): $($_.Exception.Message)"
            }
        }
    }

    Write-Host 'Restauração concluída. Reinicie o computador.' -ForegroundColor Green
}

function Show-Menu {
    Clear-Host
    Write-Host '==== HUNTEROPTIMIZATION ====' -ForegroundColor Cyan
    Write-Host '1) Básico'
    Write-Host '2) Agressivo'
    Write-Host '3) EXTREME MODE'
    Write-Host '4) Reverter Tudo'
    Write-Host '0) Sair'
}

Assert-Admin

$choice = ''
while ($choice -ne '0') {
    Show-Menu
    $choice = Read-Host 'Escolha uma opção'
    switch ($choice) {
        '1' {
            New-SystemRestorePoint
            Backup-Registry
            Snapshot-Services
            Save-State
            Apply-Optimizations -Level 'Basic'
        }
        '2' {
            New-SystemRestorePoint
            Backup-Registry
            Snapshot-Services
            Save-State
            Apply-Optimizations -Level 'Aggressive'
        }
        '3' {
            Write-Host 'EXTREME MODE: alto risco. Sem atualização de segurança.' -ForegroundColor Red
            $confirm = Read-Host 'Digite SIM para continuar'
            if ($confirm -eq 'SIM') {
                New-SystemRestorePoint
                Backup-Registry
                Snapshot-Services
                Save-State
                Apply-Optimizations -Level 'Extreme'
            } else {
                Write-Host 'Cancelado.'
            }
        }
        '4' {
            Restore-All
        }
        '0' { Write-Host 'Saindo...' }
        default { Write-Host 'Opção inválida.' -ForegroundColor Yellow }
    }
    if ($choice -ne '0') {
        Read-Host 'Pressione Enter para continuar'
    }
}

Stop-Transcript | Out-Null
