# ==========================================
# MENÚ PRINCIPAL - PRÁCTICA SERVER
# Guárdalo como: Menu.ps1
# ==========================================

# Importar las funciones desde el otro archivo (Dot-Sourcing)
. .\Funciones.ps1

do {
    Clear-Host
    Write-Host "=========================================" -ForegroundColor Magenta
    Write-Host "   MENÚ DE AUTOMATIZACIÓN - SERVIDOR     " -ForegroundColor White
    Write-Host "=========================================" -ForegroundColor Magenta
    Write-Host "1. Generar archivo CSV de prueba"
    Write-Host "2. Crear UOs, leer CSV y crear Usuarios"
    Write-Host "3. Configurar FSRM (Cuotas y Apantallamiento)"
    Write-Host "4. Configurar AppLocker y GPO de Desconexión"
    Write-Host "5. Salir"
    Write-Host "=========================================" -ForegroundColor Magenta
    
    $seleccion = Read-Host "Elige una opción (1-5)"

    switch ($seleccion) {
        '1' { Crear-CSVDemo; Write-Host "`nPresiona cualquier tecla..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        '2' { Crear-UsuariosYUnidades; Write-Host "`nPresiona cualquier tecla..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        '3' { Configurar-FSRM; Write-Host "`nPresiona cualquier tecla..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        '4' { Configurar-AppLockerGPO; Write-Host "`nPresiona cualquier tecla..." ; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        '5' { Write-Host "Saliendo del script..." -ForegroundColor Green }
        default { Write-Host "Opción no válida." -ForegroundColor Red; Start-Sleep -Seconds 2 }
    }
} until ($seleccion -eq '5')