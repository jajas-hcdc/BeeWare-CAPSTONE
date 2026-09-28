@echo off
title BeeWare - Deploy Serverless Cloud Functions
echo ========================================================
echo   BeeWare - Deploy Serverless 24/7 Cloud Functions
echo ========================================================
echo.
echo Checking Firebase CLI login...
call npx --yes firebase-tools login
echo.
echo Deploying Cloud Functions to Firebase (beeware-beaef)...
call npx --yes firebase-tools deploy --only functions
echo.
echo ========================================================
echo Deployment finished! Your cloud functions are now active.
echo ========================================================
pause
