param (
    [string]$ServerUrl = "https://patcher-server.onrender.com"
)

Write-Host "🔥 LO Boss Mode - YouTube APK Építő Script 🔥" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$WorkDir = "C:\Users\Szaby\Desktop\revanced-manager-main\boss_mode_builder"
$ToolsDir = "$WorkDir\tools"
$OutputApk = "$WorkDir\YouTube-BossMode.apk"

if (!(Test-Path $ToolsDir)) { New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null }

# 1. Eszközök letöltése
Write-Host "`n[1/6] Szükséges eszközök letöltése..." -ForegroundColor Yellow

$Urls = @{
    "apktool.jar" = "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar"
    "r8.jar" = "https://maven.google.com/com/android/tools/r8/8.2.33/r8-8.2.33.jar"
    "android.jar" = "https://github.com/Skathe/android-jar/raw/master/android-30/android.jar"
    "youtube_revanced.apk" = "https://github.com/Android-App-Patches/build-apps/releases/download/v2024.10.20-1835/youtube-revanced-extended-v19.16.39-all.apk"
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

# 2. LicenseManager Java kód frissítése a szerver URL-lel
Write-Host "`n[2/6] Boss Mode kód előkészítése..." -ForegroundColor Yellow
$JavaSourcePath = "C:\Users\Szaby\Desktop\revanced-manager-main\revanced-subscription-server\patches\src\main\java\app\revanced\integrations\youtube\bossmode\LicenseManager.java"
$TempJava = "$ToolsDir\LicenseManager.java"
(Get-Content $JavaSourcePath) -replace 'private static final String SERVER_URL = "http://localhost:3000";', "private static final String SERVER_URL = `"$ServerUrl`";" | Set-Content $TempJava

# 3. Fordítás (Java -> Class -> Dex -> Smali)
Write-Host "`n[3/6] Android gépi kód (Smali) generálása..." -ForegroundColor Yellow
Set-Location $ToolsDir

Write-Host "  -> Java fordítás..."
javac -cp "android.jar" -source 8 -target 8 LicenseManager.java

Write-Host "  -> Dex fordítás (R8)..."
java -cp r8.jar com.android.tools.r8.D8 --min-api 26 --output . LicenseManager.class

Write-Host "  -> Dex dekódolás Smali-ra..."
java -jar apktool.jar d classes.dex -o smali_out -f

# 4. YouTube APK Kicsomagolása
Write-Host "`n[4/6] YouTube APK kicsomagolása (ez eltart 1-2 percig)..." -ForegroundColor Yellow
java -jar apktool.jar d youtube_revanced.apk -o youtube_decoded -f

# 5. Injektálás
Write-Host "`n[5/6] Boss Mode injektálása az APK-ba..." -ForegroundColor Yellow
$TargetSmaliDir = "$ToolsDir\youtube_decoded\smali_classes4\app\revanced\integrations\youtube\bossmode"
if (!(Test-Path $TargetSmaliDir)) { New-Item -ItemType Directory -Force -Path $TargetSmaliDir | Out-Null }
Copy-Item -Path "$ToolsDir\smali_out\smali\app\revanced\integrations\youtube\bossmode\*" -Destination $TargetSmaliDir -Recurse -Force

# Keresünk egy indító Activity-t, pl. a YouTube MainActivity-jét.
# Mivel a ReVanced Extended már injektált, megkeressük a ReVanced belépési pontját, vagy a MainActivity onCreate-et.
$MainActivity = Get-ChildItem -Path "$ToolsDir\youtube_decoded" -Filter "MainActivity.smali" -Recurse | Select-Object -First 1

if ($MainActivity) {
    Write-Host "  -> MainActivity megtalálva: $($MainActivity.FullName)"
    $Content = Get-Content $MainActivity.FullName
    $NewContent = @()
    $Injected = $false

    foreach ($line in $Content) {
        $NewContent += $line
        if ($line -match "invoke-super \{.*\}, L.*Activity;->onCreate\(Landroid/os/Bundle;\)V" -and -not $Injected) {
            # Hozzáadjuk a hívást a MainActivity onCreate végéhez
            $NewContent += "    invoke-static {p0}, Lapp/revanced/integrations/youtube/bossmode/LicenseManager;->checkLicense(Landroid/app/Activity;)V"
            $Injected = $true
            Write-Host "  -> LicenseManager hívás beinjektálva!" -ForegroundColor Green
        }
    }
    Set-Content -Path $MainActivity.FullName -Value $NewContent
} else {
    Write-Host "  -> HIBA: Nem találtam MainActivity-t!" -ForegroundColor Red
}

# 6. Újracsomagolás
Write-Host "`n[6/6] APK Újracsomagolása és teszt aláírása..." -ForegroundColor Yellow
java -jar apktool.jar b youtube_decoded -o youtube_bossmode_unsigned.apk

# Simple apksigner using uber-apk-signer (download if needed)
$SignerJar = "$ToolsDir\uber-apk-signer.jar"
if (!(Test-Path $SignerJar)) {
    Invoke-WebRequest -Uri "https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar" -OutFile $SignerJar
}
java -jar $SignerJar -a youtube_bossmode_unsigned.apk --allowResign -o .

Move-Item -Path "$ToolsDir\youtube_bossmode_unsigned-aligned-debugSigned.apk" -Destination $OutputApk -Force

Write-Host "`n✅ KÉSZ! A Boss Mode APK sikeresen elkészült!" -ForegroundColor Green
Write-Host "Fájl helye: $OutputApk" -ForegroundColor Cyan
Write-Host "Ezt a fájlt már küldheted is a telefonodra! 😈" -ForegroundColor Magenta
