# HunterOptimization

Otimizador extremo para Windows 10/11 focado em FPS máximo, latência mínima e menor uso de CPU/RAM/Disco.

## Passo a passo de uso
1. Abra o PowerShell como **Administrador**.
2. Execute o script:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\HunterOptimization.ps1
   ```
3. Escolha o nível desejado:
   - **Básico**: ajustes seguros e reversíveis.
   - **Agressivo**: desativa serviços de indexação e SysMain.
   - **EXTREME MODE**: inclui desativar Windows Update e reduzir efeitos visuais.
4. Reinicie o computador para aplicar tudo.

## Segurança (Obrigatório)
O script faz:
- **Ponto de restauração** automático.
- **Backup completo do REGEDIT** (HKLM e HKCU em `.reg`).
- **Snapshot de serviços** com StartMode.
- **Logs detalhados** em `C:\ProgramData\HunterOptimization\Logs`.

## Como reverter tudo
- Selecione **Reverter Tudo** no menu do script.
- Isso importa o backup do REGEDIT e restaura StartMode dos serviços.
- Reinicie o PC.

## Como gerar HunterOptimization.exe
Use o `PS2EXE`:
```powershell
Install-Module PS2EXE -Scope CurrentUser -Force
Invoke-PS2EXE -InputFile .\HunterOptimization.ps1 -OutputFile .\HunterOptimization.exe
```

## Recomendações para notebooks fracos
- Use **Básico** ou **Agressivo**.
- Evite **EXTREME MODE** se depende de updates ou drivers automáticos.
- Considere limitar efeitos visuais e desativar GameDVR.

## Considerações para PCs ARM
- O script é compatível com PowerShell, mas algumas otimizações podem ter efeito reduzido por diferenças de driver/scheduler.
- Evite desativar Windows Update se o dispositivo recebe drivers via Windows Update.

## Aviso
Use por sua conta e risco. Mantenha backups e ponto de restauração.
