param (
    [string]$ServerUrl = "https://patcher-server.onrender.com"
)

Write-Host "🔥 LO Boss Mode - YouTube APK Építő Script (Teljes Patchelés) 🔥" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$WorkDir = "C:\Users\Szaby\Desktop\revanced-manager-main\boss_mode_builder"
$ToolsDir = "$WorkDir\tools"
$OriginalApk = "$WorkDir\youtube_original.apk"
$PatchedApk = "$WorkDir\youtube_patched.apk"
$OutputApk = "$WorkDir\YouTube-BossMode.apk"

if (!(Test-Path $ToolsDir)) { New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null }

if (!(Test-Path $OriginalApk)) {
    Write-Host "`n❌ HIBA: Nem találom a szűz YouTube APK-t!" -ForegroundColor Red
    Write-Host "Kérlek töltsd le az APKMirror-ról a YouTube 19.16.39 APK-t (NEM Bundle!)," -ForegroundColor Yellow
    Write-Host "nevezd át 'youtube_original.apk'-ra, és tedd be ide:" -ForegroundColor Yellow
    Write-Host $WorkDir -ForegroundColor Cyan
    Write-Host "Utána futtasd újra ezt a scriptet!" -ForegroundColor Yellow
    exit 1
}

# 1. Eszközök letöltése
Write-Host "`n[1/7] Szükséges eszközök letöltése..." -ForegroundColor Yellow

# Itt beszerezzük a ReVanced CLI-t és a hivatalos patcheket is
$Urls = @{
    "apktool.jar" = "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar"
    "r8.jar" = "https://maven.google.com/com/android/tools/r8/8.2.33/r8-8.2.33.jar"
    "android.jar" = "https://github.com/Skathe/android-jar/raw/master/android-30/android.jar"
    "revanced-cli.jar" = "https://github.com/ReVanced/revanced-cli/releases/latest/download/revanced-cli.jar"
    "revanced-patches.jar" = "https://github.com/ReVanced/revanced-patches/releases/latest/download/revanced-patches.jar"
    "revanced-integrations.apk" = "https://github.com/ReVanced/revanced-integrations/releases/latest/download/app-release-unsigned.apk"
}

foreach ($item in $Urls.GetEnumerator()) {
    $Dest = "$ToolsDir\$($item.Key)"
    if (!(Test-Path $Dest)) {
        Write-Host "  -> $($item.Key) letöltése..."
        Invoke-WebRequest -Uri $item.Value -OutFile $Dest
    } else {
        Write-Host "  -> $($item.Key) már megvan." -ForegroundColor Green
    }
}

# 2. ReVanced alap patchelés
Write-Host "`n[2/7] YouTube patchelése hivatalos ReVanceddel (eltart pár percig)..." -ForegroundColor Yellow
if (!(Test-Path $PatchedApk)) {
    java -jar "$ToolsDir\revanced-cli.jar" patch -p "$ToolsDir\revanced-patches.jar" -m "$ToolsDir\revanced-integrations.apk" -b $OriginalApk -o $PatchedApk
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Hiba a ReVanced patchelés során!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  -> Patchelt APK már létezik, folytatás..." -ForegroundColor Green
}

# 3. LicenseManager Java kód frissítése a szerver URL-lel
Write-Host "`n[3/7] Boss Mode kód előkészítése..." -ForegroundColor Yellow
$JavaSourcePath = "C:\Users\Szaby\Desktop\revanced-manager-main\revanced-subscription-server\patches\src\main\java\app\revanced\integrations\youtube\bossmode\LicenseManager.java"
$TempJava = "$ToolsDir\LicenseManager.java"
(Get-Content $JavaSourcePath) -replace 'private static final String SERVER_URL = "http://localhost:3000";', "private static final String SERVER_URL = `"$ServerUrl`";" | Set-Content $TempJava

# 4. Fordítás (Java -> Class -> Dex -> Smali)
Write-Host "`n[4/7] Android gépi kód (Smali) generálása..." -ForegroundColor Yellow
Set-Location $ToolsDir

Write-Host "  -> Java fordítás..."
javac -cp "android.jar" -source 8 -target 8 LicenseManager.java

Write-Host "  -> Dex fordítás (R8)..."
java -cp r8.jar com.android.tools.r8.D8 --min-api 26 --output . LicenseManager.class

Write-Host "  -> Dex dekódolás Smali-ra..."
java -jar apktool.jar d classes.dex -o smali_out -f

# 5. YouTube APK Kicsomagolása
Write-Host "`n[5/7] Patchelt YouTube APK kicsomagolása..." -ForegroundColor Yellow
java -jar apktool.jar d $PatchedApk -o youtube_decoded -f

# 6. Injektálás
Write-Host "`n[6/7] Boss Mode injektálása az APK-ba..." -ForegroundColor Yellow
$TargetSmaliDir = "$ToolsDir\youtube_decoded\smali_classes4\app\revanced\integrations\youtube\bossmode"
if (!(Test-Path $TargetSmaliDir)) { New-Item -ItemType Directory -Force -Path $TargetSmaliDir | Out-Null }
Copy-Item -Path "$ToolsDir\smali_out\smali\app\revanced\integrations\youtube\bossmode\*" -Destination $TargetSmaliDir -Recurse -Force

$MainActivity = Get-ChildItem -Path "$ToolsDir\youtube_decoded" -Filter "MainActivity.smali" -Recurse | Select-Object -First 1

if ($MainActivity) {
    Write-Host "  -> MainActivity megtalálva: $($MainActivity.FullName)"
    $Content = Get-Content $MainActivity.FullName
    $NewContent = @()
    $Injected = $false

    foreach ($line in $Content) {
        $NewContent += $line
        if ($line -match "invoke-super \{.*\}, L.*Activity;->onCreate\(Landroid/os/Bundle;\)V" -and -not $Injected) {
            $NewContent += "    invoke-static {p0}, Lapp/revanced/integrations/youtube/bossmode/LicenseManager;->checkLicense(Landroid/app/Activity;)V"
            $Injected = $true
            Write-Host "  -> LicenseManager hívás beinjektálva!" -ForegroundColor Green
        }
    }
    Set-Content -Path $MainActivity.FullName -Value $NewContent
} else {
    Write-Host "  -> HIBA: Nem találtam MainActivity-t!" -ForegroundColor Red
}

# 7. Újracsomagolás
Write-Host "`n[7/7] APK Újracsomagolása és aláírása..." -ForegroundColor Yellow
java -jar apktool.jar b youtube_decoded -o youtube_bossmode_unsigned.apk

$SignerJar = "$ToolsDir\uber-apk-signer.jar"
if (!(Test-Path $SignerJar)) {
    Invoke-WebRequest -Uri "https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar" -OutFile $SignerJar
}
java -jar $SignerJar -a youtube_bossmode_unsigned.apk --allowResign -o .

Move-Item -Path "$ToolsDir\youtube_bossmode_unsigned-aligned-debugSigned.apk" -Destination $OutputApk -Force

Write-Host "`n✅ KÉSZ! A Boss Mode APK sikeresen elkészült!" -ForegroundColor Green
Write-Host "Fájl helye: $OutputApk" -ForegroundColor Cyan
Write-Host "Ezt a fájlt már küldheted is a telefonodra! 😈" -ForegroundColor Magenta

