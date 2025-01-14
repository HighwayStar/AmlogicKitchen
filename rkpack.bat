@echo off

:: BatchGotAdmin
:-------------------------------------
REM  --> Check for permissions
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

REM --> If error flag set, we do not have admin.
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"
:--------------------------------------

setlocal EnableDelayedExpansion

cls


echo .....................
echo Rockchip Kitchen
echo .....................
set /P level=Select level 1,2 or 3: 
IF %level% == 1 GOTO level1
IF %level% == 2 GOTO level2
IF %level% == 3 GOTO level3
ELSE echo Invalid option
echo Unpack level 1 first
pause
exit

:level1

if exist level1 goto pass
echo Unpack level 1 first
pause
exit

:pass

if exist out rmdir /q /s out
md out

set /p filename=< level1\projectname.txt
echo Supported models:
echo px30            RKPX30
echo px3se           RK312A
echo rk1808          RK180A
echo rk3036          RK303A
echo rk3128h         RK312X
echo rk312*          RK312A
echo rk322*          RK322A
echo rk3229          RK3229
echo rk3288          RK320A
echo rk3308          RK3308
echo rk3326          RK3326
echo rk3328          RK322H
echo rk3368          RK330A
echo rk3399*         RK330C
echo rk356*          RK3568
echo rv1126_rv1109   RK1126
echo If your model starts with rk312* then its RK312A
set /P chip=Enter your chip model, Eg: RK312X:
IF "%chip%"=="" echo Error: Chip is invalid, must be started with RK && pause && exit

findstr /m "trust.img" level1\package-file >Nul
if %errorlevel%==0 (
    if not exist level1\Image\trust.img (
        fsutil file createnew level1\Image\trust.img 102400
    )
)

bin\windows\afptool.exe -pack level1\ level1\Image\update.img
bin\windows\rkImageMaker.exe -%chip% level1\Image\MiniLoaderAll.bin level1\Image\update.img "out\%filename%.img" -os_type:androidos

pause
exit

:level2

if exist level2 goto pass2
echo Unpack level 2 first
pause
exit

:pass2

if not exist level1\Image\super.img (
    FOR %%A IN (odm oem product vendor system system_ext odm_ext_a odm_ext_b) DO (
        if exist level2\%%A\ (
            set /p size=<"level2\config\%%A_size.txt"
            bin\windows\make_ext4fs -J -L %%A -T -1 -S level2\config\%%A_file_contexts -C level2\config\%%A_fs_config -l !size! -a %%A level1\Image\%%A.img level2\%%A\
        )
    )
) else (
    FOR %%A IN (odm oem product vendor system system_ext system_a system_ext_a vendor_a product_a odm_a system_b system_ext_b vendor_b product_b odm_b) DO (
        if exist level2\%%A\ (
            bin\windows\du -sk level2\%%A | bin\windows\cut -f1 | bin\windows\gawk "{$1*=1024;$1=int($1*1.08)};echo $1"> level2\config\%%A_dir_size.txt
            set /p size=<"level2\config\%%A_dir_size.txt"
            IF !size! LSS 1048576 (
                SET size=1048576
                echo 1048576> level2\config\%%A_dir_size.txt
            )
            bin\windows\make_ext4fs -J -L %%A -T -1 -S level2\config\%%A_file_contexts -C level2\config\%%A_fs_config -l !size! -a %%A level2\%%A.img level2\%%A\
            bin\windows\ext4\resize2fs.exe -M level2\%%A.img
        )
    )
)

set /p supertype=< level2\config\super_type.txt

if %supertype% EQU 3 (

if exist level1\Image\super.img (
    set /p supersize=<"level2\config\super_size.txt"
    bin\windows\du -cb level2/*.img | bin\windows\grep total | bin\windows\cut -f1>level2\superusage.txt
    set /p superusage1=<"level2\superusage.txt"
    set command=bin\windows\super\lpmake --metadata-size 65536 --super-name super --metadata-slots 3 --device %supername%:!supersize! --group amlogic_dynamic_partitions_a:!superusage1!

    FOR %%A IN (system_a system_ext_a vendor_a product_a odm_a) DO (
        if exist level2\%%A.img (
            bin\windows\du -skb level2\%%A.img | bin\windows\cut -f1> level2\%%A_size.txt
            set /p size=<"level2\%%A_size.txt"
            echo %%A | bin\windows\sed "s/.\{3\}$//">level2\%%A.txt
            set /p name=<"level2\%%A.txt"
            if !size! GTR 0 (
                set command=!command! --partition %%A:readonly:!size!:amlogic_dynamic_partitions_a --image %%A=level2\%%A.img
            )
            del level2\*.txt
        )
    )
    set /a superusage2=!supersize!-!superusage1!
    set command=!command! --group amlogic_dynamic_partitions_b:!superusage2!

    FOR %%A IN (system_b system_ext_b vendor_b product_b odm_b) DO (
        if exist level2\%%A.img (
            bin\windows\du -skb level2\%%A.img | bin\windows\cut -f1> level2\%%A_size.txt
            set /p size=<"level2\%%A_size.txt"
            if !size! EQU 0 (
                set command=!command! --partition %%A:readonly:!size!:amlogic_dynamic_partitions_b
            )
            del level2\*.txt
        )
    )

    if !superusage1! GEQ !supersize! (
        echo Unable to create super image, recreated images are too big.
        echo Cleanup some files before retrying
        echo Needed space: !superusage1!
        echo Available maximum space: !supersize!
        pause
        exit
    )

    set command=!command! --virtual-ab --sparse --output level1\Image\super.img
    !command!
)
) else (
    set /p supersize=<"level2\config\super_size.txt"
    bin\windows\du -cb level2/*.img | bin\windows\grep total | bin\windows\cut -f1>level2\superusage.txt
    set /p superusage=<"level2\superusage.txt"
    set command=bin\windows\super\lpmake --metadata-size 65536 --super-name super --metadata-slots 2 --device super:!supersize! --group amlogic_dynamic_partitions:!superusage!

    FOR %%A IN (odm oem product vendor system system_ext) DO (
        if exist level2\%%A.img (
            bin\windows\du -skb level2\%%A.img | bin\windows\cut -f1> level2\%%A_size.txt
            set /p size=<"level2\%%A_size.txt"
            echo %%A | bin\windows\sed "s/.\{3\}$//">level2\%%A.txt
            set /p name=<"level2\%%A.txt"
            if !size! GTR 0 (
                set command=!command! --partition %%A:readonly:!size!:amlogic_dynamic_partitions --image %%A=level2\%%A.img
            )
            del level2\*.txt
        )
    )

    if !superusage! GEQ !supersize! (
        echo Unable to create super image, recreated images are too big.
        echo Cleanup some files before retrying
        echo Needed space: !superusage!
        echo Available maximum space: !supersize!
        pause
        exit
    )

    set command=!command! --sparse --output level1\Image\super.img
    !command!

)

echo Done.
pause
exit

:level3

if exist level3 goto pass3
echo Unpack level 3 first
pause
exit

:pass3

FOR %%A IN (recovery boot recovery_a boot_a) DO (
    if exist level3\%%A\ (
        call bin\windows\aik\cleanup.bat
        if exist level3\%%A\ramdisk\ (
            move level3\%%A\ramdisk bin\windows\aik\
        )
        move level3\%%A\split_img bin\windows\aik\
        call bin\windows\aik\repackimg.bat
        move bin\windows\aik\image-new.img bin\windows\aik\%%A.img
        call bin\windows\aik\unpackimg.bat bin\windows\aik\%%A.img
        if exist bin\windows\aik\ramdisk\ (
            move bin\windows\aik\ramdisk level3\%%A\
        )
        move bin\windows\aik\split_img  level3\%%A\
        move bin\windows\aik\%%A.img level1\Image\%%A.img
        call bin\windows\aik\cleanup.bat
    )
)

echo Done.
pause
exit
