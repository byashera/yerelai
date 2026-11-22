param(
  [int]$Port = 8070,
  [switch]$ForceVenv
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
try { Start-Transcript -Path (Join-Path $Root "kurulum.log") -Force | Out-Null } catch {}

function Detect-CudaIndexUrl {
  $candidates = @(
    "nvidia-smi",
    "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
    "C:\Windows\System32\nvidia-smi.exe"
  )
  $smiExe = $null
  foreach ($c in $candidates) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $smiExe = $c; break }
    elseif (Test-Path $c) { $smiExe = $c; break }
  }
  if ($smiExe) {
    try {
      $smi = & cmd.exe /c "`"$smiExe`" 2>nul" | Out-String
      if ($smi -match "CUDA Version:\s*(\d+)\.(\d+)") {
        $ver = ([int]$Matches[1]) * 10 + ([int]$Matches[2])
        Write-Host "NVIDIA Surucu CUDA Surumu: $($Matches[1]).$($Matches[2])" -ForegroundColor Green
        if ($ver -ge 124) { return "https://download.pytorch.org/whl/cu124" }
        elseif ($ver -ge 121) { return "https://download.pytorch.org/whl/cu121" }
        elseif ($ver -ge 118) { return "https://download.pytorch.org/whl/cu118" }
      }
    } catch {}
  }
  try {
    $nv = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "NVIDIA|GeForce|RTX|GTX" } | Select-Object -First 1
    if ($nv) { return "https://download.pytorch.org/whl/cu124" }
  } catch {}
  return "https://download.pytorch.org/whl/cpu"
}

$PyExe = $null
$UnslothPy = Join-Path $env:USERPROFILE ".unsloth\studio\unsloth_studio\Scripts\python.exe"
$LocalVenv = Join-Path $Root "venv"
$LocalPy = Join-Path $LocalVenv "Scripts\python.exe"
$ReqFile = Join-Path $Root "requirements.txt"

if (-not $ForceVenv -and (Test-Path $UnslothPy)) {
  $ok = & cmd.exe /c "`"$UnslothPy`" -c `"import torch, transformers; print(torch.cuda.is_available() and hasattr(transformers, 'Gemma4ForConditionalGeneration'))`" 2>nul" | Out-String
  if ($ok -match "True") {
    $PyExe = $UnslothPy
    Write-Host "Hazir Unsloth CUDA + Gemma 4 ortami bulundu: $PyExe" -ForegroundColor Green
    & cmd.exe /c "`"$PyExe`" -m pip install -q -r `"$ReqFile`""
  }
}

if (-not $PyExe) {
  if (Test-Path $LocalPy) {
    $ok = & cmd.exe /c "`"$LocalPy`" -c `"import torch, transformers; print(torch.cuda.is_available() and hasattr(transformers, 'Gemma4ForConditionalGeneration'))`" 2>nul" | Out-String
    if ($ok -match "True") {
      $PyExe = $LocalPy
      & cmd.exe /c "`"$PyExe`" -m pip install -q -r `"$ReqFile`""
    } else {
      Remove-Item $LocalVenv -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

if (-not $PyExe) {
  Write-Host "[1/4] Izole Python 3.11 sanal ortami hazirlaniyor..." -ForegroundColor Cyan
  $UvDir = Join-Path $Root ".uv"
  $UvExe = Join-Path $UvDir "uv.exe"
  $env:UV_PYTHON_INSTALL_DIR = Join-Path $Root ".python"
  if (-not (Test-Path $UvExe)) {
    $sysUv = Get-Command uv -ErrorAction SilentlyContinue
    if ($sysUv) { $UvExe = $sysUv.Source }
    else {
      New-Item -ItemType Directory -Path $UvDir -Force | Out-Null
      $uvZip = Join-Path $UvDir "uv.zip"
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest -Uri "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" -OutFile $uvZip -UseBasicParsing
      Expand-Archive -Path $uvZip -DestinationPath $UvDir -Force
      $foundUv = Get-ChildItem -Path $UvDir -Filter "uv.exe" -Recurse | Select-Object -First 1
      if ($foundUv -and ($foundUv.FullName -ne $UvExe)) {
        Copy-Item $foundUv.FullName $UvExe -Force
      }
      Remove-Item $uvZip -Force -ErrorAction SilentlyContinue
    }
  }
  & cmd.exe /c "`"$UvExe`" python install 3.11"
  & cmd.exe /c "`"$UvExe`" venv `"$LocalVenv`" --python 3.11 --seed"
  $PyExe = $LocalPy

  $CudaUrl = Detect-CudaIndexUrl
  $tag = ($CudaUrl -split "/")[-1]
  Write-Host "[2/4] PyTorch ($tag) ve bagimliliklar kuruluyor..." -ForegroundColor Cyan
  & cmd.exe /c "`"$PyExe`" -m pip install --upgrade pip setuptools wheel"
  if ($CudaUrl -eq "https://download.pytorch.org/whl/cpu") {
    & cmd.exe /c "`"$PyExe`" -m pip install torch torchvision torchaudio --index-url $CudaUrl"
  } else {
    & cmd.exe /c "`"$PyExe`" -m pip install torch torchvision torchaudio --index-url $CudaUrl --extra-index-url https://pypi.org/simple"
  }
  & cmd.exe /c "`"$PyExe`" -m pip install -r `"$ReqFile`""
}

Write-Host "[3/4] Electron Masaustu Uygulamasi kontrol ediliyor..." -ForegroundColor Cyan
$DesktopAppDir = Join-Path $Root "desktop"
$ElectronDir = Join-Path $DesktopAppDir "node_modules\electron"
$ElectronDistDir = Join-Path $ElectronDir "dist"
$ElectronExe = Join-Path $ElectronDistDir "electron.exe"
$SharedNodeModules = Join-Path $env:USERPROFILE "Desktop\yerelai\desktop\node_modules"
$LocalNodeModules = Join-Path $DesktopAppDir "node_modules"

if (-not (Test-Path $ElectronExe)) {
  if ((Test-Path (Join-Path $SharedNodeModules "electron\dist\electron.exe")) -and ($SharedNodeModules -ne $LocalNodeModules) -and (-not (Test-Path $LocalNodeModules))) {
    try {
      New-Item -ItemType Junction -Path $LocalNodeModules -Target $SharedNodeModules -ErrorAction Stop | Out-Null
      Write-Host "Mevcut Electron paketi otomatik baglandi." -ForegroundColor Green
    } catch {}
  }
}

if (-not (Test-Path $ElectronExe)) {
  $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if ($npmCmd -and $nodeCmd -and (Test-Path (Join-Path $DesktopAppDir "package.json"))) {
    Write-Host "Electron masaustu paketleri kuruluyor (npm install)..." -ForegroundColor Cyan
    Push-Location $DesktopAppDir
    & cmd.exe /c "npm install --ignore-scripts --no-audit --no-fund --loglevel=error"

    if (-not (Test-Path $ElectronExe)) {
      Write-Host "Electron Windows ikili paketi (electron.exe) hazirlaniyor..." -ForegroundColor Cyan
      $dlLine = & cmd.exe /c "node -e `"const {downloadArtifact}=require('@electron/get');const v=require('./node_modules/electron/package.json').version;downloadArtifact({version:v,artifactName:'electron',platform:'win32',arch:process.arch}).then(p=>console.log('EL_ZIP='+p)).catch(e=>{console.error(e);process.exit(1);});`"" | Out-String
      if ($dlLine -match "EL_ZIP=(.+)") {
        $zipPath = $Matches[1].Trim()
        if (Test-Path $zipPath) {
          New-Item -ItemType Directory -Path $ElectronDistDir -Force | Out-Null
          & tar.exe -xf $zipPath -C $ElectronDistDir
          [System.IO.File]::WriteAllText((Join-Path $ElectronDir "path.txt"), "electron.exe")
          Write-Host "Electron masaustu motoru basariyla kuruldu." -ForegroundColor Green
        }
      }
    }
    Pop-Location
  } else {
    Write-Host "Not: Node.js/npm bulunamadi; uygulama web tarayici modunda calisacak." -ForegroundColor Yellow
  }
}

# Windows Masaustune "SEN.AI Studio" kisayolu olustur (Dogrudan electron.exe veya YerelAI_Masaustu.vbs'e baglar)
try {
  $UserDesktop = [Environment]::GetFolderPath("Desktop")
  $ShortcutPath = Join-Path $UserDesktop "SEN.AI Studio.lnk"
  $IconPath = Join-Path $DesktopAppDir "icon.ico"
  $WshShell = New-Object -ComObject WScript.Shell
  $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
  if (Test-Path $ElectronExe) {
    $Shortcut.TargetPath = $ElectronExe
    $Shortcut.Arguments = "."
    $Shortcut.WorkingDirectory = $DesktopAppDir
  } else {
    $VbsLauncher = Join-Path $Root "YerelAI_Masaustu.vbs"
    $Shortcut.TargetPath = "wscript.exe"
    $Shortcut.Arguments = "`"$VbsLauncher`""
    $Shortcut.WorkingDirectory = $Root
  }
  if (Test-Path $IconPath) { $Shortcut.IconLocation = $IconPath }
  $Shortcut.Description = "SEN.AI Studio - Yerel GPU Yapay Zeka Studyosu"
  $Shortcut.Save()
  Write-Host "Masaustu kisayolu guncellendi: $ShortcutPath" -ForegroundColor Green
} catch {}

Write-Host "[4/4] SEN.AI Studio baslatiliyor (http://127.0.0.1:$Port)..." -ForegroundColor Green
if (Test-Path $ElectronExe) {
  Start-Process -FilePath $ElectronExe -ArgumentList "." -WorkingDirectory $DesktopAppDir
} else {
  $Backend = Join-Path $Root "backend.py"
  Start-Process -FilePath $PyExe -ArgumentList "`"$Backend`"" -WorkingDirectory $Root -WindowStyle Minimized
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    try {
      $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/status" -TimeoutSec 1 -UseBasicParsing -ErrorAction Stop
      if ($resp.StatusCode -eq 200) { break }
    } catch {}
  }
  Start-Process "http://127.0.0.1:$Port"
}
try { Stop-Transcript | Out-Null } catch {}
