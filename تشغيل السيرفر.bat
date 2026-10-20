@echo off
chcp 65001 >nul
title CyberFort 3D Server - مركز تشغيل السيرفرات

echo =========================================================================
echo    ⚡ CyberFort: Titan Strike 3D - Live Control ^& Guest Servers
echo =========================================================================
echo  [1/2] ضبط إعدادات اللابتوب ليعمل حتى عند إغلاق الشاشة...
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0 >nul 2>&1
powercfg /change standby-timeout-ac 0 >nul 2>&1
powercfg /change standby-timeout-dc 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
echo  [OK] تم ضبط الطاقة بنجاح (السيرفر لن ينقطع عند قفل اللابتوب).

echo.
echo  [2/2] جاري تشغيل سيرفر الأدمن وسيرفر الزوار...
cd /d "c:\Users\Administrator\OneDrive\Desktop\Game"

python server\update_server.py
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo =========================================================================
    echo  ❌ حدث خطأ أثناء تشغيل السيرفر! (كود الخطأ: %ERRORLEVEL%)
    echo =========================================================================
    echo  تأكد من إغلاق أي نافذة سيرفر سابقة وأنه لا يوجد برنامج يشغل البورت 8080 أو 8081.
    echo.
    pause
)
