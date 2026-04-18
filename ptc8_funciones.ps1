# ==========================================
# ARCHIVO DE FUNCIONES - PRÁCTICA SERVER
# Funciones.ps1
# ==========================================

Import-Module ActiveDirectory

# --- VARIABLES GLOBALES ---
$global:Dominio = "DC=reprobados,DC=com" # Dominio configurado
$global:SufijoUPN = "@reprobados.com"    
$global:RutaCSV = "C:\usuarios.csv"
$global:RutaCarpetas = "C:\Shares\Usuarios"


Function Crear-UsuariosYUnidades {
    Clear-Host
    Write-Host "--- 1. CREANDO UOs, GRUPOS Y USUARIOS ---" -ForegroundColor Cyan
    
    if (!(Test-Path $global:RutaCSV)) {
        Write-Host "ERROR: No se encontró el archivo CSV en $($global:RutaCSV)" -ForegroundColor Red
        return
    }

    # 1. Crear las UOs
    $UOs = @("Cuates", "No Cuates")
    foreach ($uo in $UOs) {
        if (!(Get-ADOrganizationalUnit -Filter "Name -eq '$uo'" -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $uo -Path $global:Dominio
            Write-Host "-> UO '$uo' creada exitosamente." -ForegroundColor Green
        }
    }

    # 2. Crear los Grupos de Seguridad (Esto soluciona tu problema del grupo faltante)
    $Grupos = @(
        @{ Nombre = "Grupo_Cuates"; OU = "OU=Cuates,$($global:Dominio)" },
        @{ Nombre = "Grupo_NoCuates"; OU = "OU=No Cuates,$($global:Dominio)" }
    )
    foreach ($g in $Grupos) {
        if (!(Get-ADGroup -Filter "Name -eq '$($g.Nombre)'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $g.Nombre -GroupCategory Security -GroupScope Global -Path $g.OU
            Write-Host "-> Grupo de Seguridad '$($g.Nombre)' creado en su UO." -ForegroundColor Green
        }
    }

    # 3. Función interna para calcular horas UTC exactas (Lógica de tu amigo)
    Function Obtener-HorarioUTC ($Inicio, $Fin) {
        [byte[]]$bytes = New-Object byte[] 21
        for ($dia = 0; $dia -lt 7; $dia++) {
            for ($hora = 0; $hora -lt 24; $hora++) {
                $permitido = $false
                if ($Inicio -lt $Fin) {
                    if ($hora -ge $Inicio -and $hora -lt $Fin) { $permitido = $true }
                } else {
                    if ($hora -ge $Inicio -or $hora -lt $Fin) { $permitido = $true }
                }

                if ($permitido) {
                    # Calcula el desfase de la zona horaria del servidor
                    $fechaLocal = (Get-Date -Year 2024 -Month 1 -Day 7 -Hour 0 -Minute 0 -Second 0).AddDays($dia).AddHours($hora)
                    $fechaUTC = $fechaLocal.ToUniversalTime()
                    
                    $diaUTC = [int]$fechaUTC.DayOfWeek
                    $horaUTC = $fechaUTC.Hour
                    
                    $byteIndex = ($diaUTC * 3) + [Math]::Floor($horaUTC / 8)
                    $bitIndex = $horaUTC % 8
                    
                    $bytes[$byteIndex] = $bytes[$byteIndex] -bor (1 -shl $bitIndex)
                }
            }
        }
        return $bytes
    }

    # Asignar los arreglos calculados
    [byte[]]$HorarioCuates = Obtener-HorarioUTC -Inicio 8 -Fin 15
    [byte[]]$HorarioNoCuates = Obtener-HorarioUTC -Inicio 15 -Fin 2

    # 4. Crear los usuarios y unirlos a los grupos
    $Usuarios = Import-Csv $global:RutaCSV
    foreach ($user in $Usuarios) {
        # Eliminar si ya existe para evitar conflictos
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($user.Usuario)'" -ErrorAction SilentlyContinue
        if ($existe) { Remove-ADUser -Identity $user.Usuario -Confirm:$false }

        $OUPath = "OU=$($user.Departamento),$($global:Dominio)"
        $Horario = if ($user.Departamento -eq "Cuates") { $HorarioCuates } else { $HorarioNoCuates }
        $NombreGrupo = if ($user.Departamento -eq "Cuates") { "Grupo_Cuates" } else { "Grupo_NoCuates" }

        $Parametros = @{
            SamAccountName = $user.Usuario
            UserPrincipalName = "$($user.Usuario)$($global:SufijoUPN)"
            Name = $user.Nombre
            GivenName = $user.Nombre.Split(" ")[0]
            Surname = $user.Nombre.Split(" ")[1]
            AccountPassword = (ConvertTo-SecureString $user.Password -AsPlainText -Force)
            Enabled = $true
            Path = $OUPath
        }

        # Crear, inyectar horas UTC y agregar al grupo
        New-ADUser @Parametros
        Set-ADUser -Identity $user.Usuario -Replace @{logonhours=[byte[]]$Horario}
        Add-ADGroupMember -Identity $NombreGrupo -Members $user.Usuario -ErrorAction SilentlyContinue
        
        Write-Host "-> Usuario $($user.Usuario) creado limpio, horas UTC aplicadas y unido a $NombreGrupo" -ForegroundColor Green
    }
}

Function Configurar-FSRM {
    Clear-Host
    Write-Host "--- 2. CONFIGURANDO FSRM (CUOTAS Y APANTALLAMIENTO) ---" -ForegroundColor Cyan
    
    if (!(Get-WindowsFeature FS-Resource-Manager).Installed) {
        Write-Host "Instalando FSRM... (Esto puede tomar un minuto)" -ForegroundColor Yellow
        Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools | Out-Null
    }
    Import-Module FileServerResourceManager

    if (!(Test-Path $global:RutaCarpetas)) { New-Item -Path $global:RutaCarpetas -ItemType Directory | Out-Null }

    try {
        New-FsrmFileGroup -Name "Bloqueo Media y Exe" -IncludePattern @("*.mp3", "*.mp4", "*.exe", "*.msi") -ErrorAction Stop
        New-FsrmQuotaTemplate -Name "Cuota Cuates 10MB" -Size 10MB -LimitMode Hard -ErrorAction Stop
        New-FsrmQuotaTemplate -Name "Cuota No Cuates 5MB" -Size 5MB -LimitMode Hard -ErrorAction Stop
        Write-Host "-> Plantillas de cuota y grupos de archivos creados." -ForegroundColor Green
    } catch {
        Write-Host "-> Las plantillas de FSRM ya existen." -ForegroundColor Yellow
    }

    $Usuarios = Import-Csv $global:RutaCSV
    foreach ($user in $Usuarios) {
        $RutaUsuario = "$($global:RutaCarpetas)\$($user.Usuario)"
        if (!(Test-Path $RutaUsuario)) { New-Item -Path $RutaUsuario -ItemType Directory | Out-Null }

        try {
            if ($user.Departamento -eq "Cuates") {
                New-FsrmQuota -Path $RutaUsuario -Template "Cuota Cuates 10MB" -ErrorAction Stop
            } else {
                New-FsrmQuota -Path $RutaUsuario -Template "Cuota No Cuates 5MB" -ErrorAction Stop
            }
            New-FsrmFileScreen -Path $RutaUsuario -Active -IncludeGroup "Bloqueo Media y Exe" -ErrorAction Stop
            Write-Host "-> FSRM configurado para $($user.Usuario)" -ForegroundColor Green
        } catch {
             Write-Host "-> FSRM ya estaba configurado para $($user.Usuario)" -ForegroundColor Yellow
        }
    }
}

Function Configurar-AppLockerGPO {
    Clear-Host
    Write-Host "--- 3. CONFIGURANDO APPLOCKER Y GPO DE CIERRE ---" -ForegroundColor Cyan
    
    # 1. Crear el Grupo de Seguridad y agregar usuarios
    Write-Host "-> Creando Grupo de Seguridad..." -ForegroundColor Yellow
    $grupo = Get-ADGroup -Filter "Name -eq 'GrupoNoCuates'" -ErrorAction SilentlyContinue
    if (-not $grupo) {
        New-ADGroup -Name "GrupoNoCuates" -GroupCategory Security -GroupScope Global -Path "OU=No Cuates,$global:Dominio"
    }
    Get-ADUser -SearchBase "OU=No Cuates,$global:Dominio" -Filter * | ForEach-Object {
        Add-ADGroupMember -Identity "GrupoNoCuates" -Members $_.SamAccountName -ErrorAction SilentlyContinue
    }

    # 2. Detener servicio AppLocker temporalmente para configurarlo
    Stop-Service -Name AppIDSvc -Force -ErrorAction SilentlyContinue

    # 3. EL SALVAVIDAS: Reglas por Defecto para no bloquear el Servidor
    Write-Host "-> Inyectando reglas de salvavidas (Administradores y Windows)..." -ForegroundColor Yellow
    $xmlSalvavidas = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Permitir Program Files" Description="Regla por defecto" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7e51" Name="Permitir Windows" Description="Regla por defecto" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="Permitir Administradores" Description="Regla por defecto" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
    $rutaXML = "$env:TEMP\salvavidas.xml"
    $xmlSalvavidas | Out-File -FilePath $rutaXML -Encoding UTF8
    Set-AppLockerPolicy -XmlPolicy $rutaXML -ErrorAction SilentlyContinue

    # 4. Generar la regla Hash para el Bloc de Notas
    Write-Host "-> Generando regla Hash restrictiva para el Bloc de Notas..." -ForegroundColor Yellow
    $netbios = (Get-ADDomain).NetBIOSName
    $polNotepad = Get-AppLockerFileInformation -Path "C:\Windows\System32\notepad.exe" | New-AppLockerPolicy -RuleType Hash -User "$netbios\GrupoNoCuates" -ErrorAction SilentlyContinue
    
    if ($polNotepad) {
        foreach ($coleccion in $polNotepad.RuleCollections) {
            foreach ($regla in $coleccion) {
                $regla.Action = 'Deny'
            }
        }
        Set-AppLockerPolicy -PolicyObject $polNotepad -Merge | Out-Null
    }

    # 5. Activar y arrancar el servicio de AppLocker
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\AppIDSvc" -Name "Start" -Value 2 -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue

    # 6. GPO de Cierre Forzado 
    Write-Host "-> Aplicando GPO de cierre de sesión..." -ForegroundColor Yellow
    Install-WindowsFeature GPMC -ErrorAction SilentlyContinue | Out-Null
    Import-Module GroupPolicy
    $nombreGPO = "Politicas_FIM_CierreForzado"
    New-GPO -Name $nombreGPO -ErrorAction SilentlyContinue | New-GPLink -Target $global:Dominio -ErrorAction SilentlyContinue | Out-Null
    Set-GPRegistryValue -Name $nombreGPO -Key "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" -ValueName "enableforcedlogoff" -Type DWord -Value 1 -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "-> ¡Configuración de AppLocker y GPO completada con éxito y sin riesgos!" -ForegroundColor Green
}

Function Crear-CSVDemo {
    Clear-Host
    Write-Host "--- GENERANDO CSV DE PRUEBA ---" -ForegroundColor Cyan
    
    if (!(Test-Path $global:RutaCSV)) {
        $contenidoCSV = @"
Nombre,Usuario,Password,Departamento
Juan Perez,jperez,Practica2026!,Cuates
Maria Lopez,mlopez,Practica2026!,No Cuates
Carlos Slim,cslim,Practica2026!,Cuates
Ana Frank,afrank,Practica2026!,No Cuates
Pedro Infante,pinfante,Practica2026!,Cuates
Frida Kahlo,fkahlo,Practica2026!,No Cuates
Diego Rivera,drivera,Practica2026!,Cuates
Sor Juana,sjuana,Practica2026!,No Cuates
Pancho Villa,pvilla,Practica2026!,Cuates
Emiliano Zapata,ezapata,Practica2026!,No Cuates
"@
        $contenidoCSV | Out-File -FilePath $global:RutaCSV -Encoding UTF8
        Write-Host "-> Archivo CSV de prueba creado exitosamente en $($global:RutaCSV)" -ForegroundColor Green
    } else {
        Write-Host "-> El archivo CSV ya existe en $($global:RutaCSV). No se sobreescribió." -ForegroundColor Yellow
    }
}
