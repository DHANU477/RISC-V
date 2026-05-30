@echo off
set VIVADO_BIN=D:\Xillinx\Vivado\2024.1\bin
set LOG_FILE=sim_output.log

echo Starting simulation... > %LOG_FILE%

REM Compiling all RISC-V modules
%VIVADO_BIN%\xvlog ..\ALU\ALU.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog ..\DATA_MEMORY\DATA_MEMORY.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog ..\DECODER\DECODER.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog ..\IMMEDIATE_GENERATOR\IMMEDIATE_GENERATOR.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog ..\LOAD_ALIGN\LOAD_ALIGN.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog ..\pc\pc.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog ..\REGISTER_FILE\REGISTER_FILE.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog ..\TOP_MODULE\TOP_MODULE.v >> %LOG_FILE% 2>&1
%VIVADO_BIN%\xvlog top_tb.v >> %LOG_FILE% 2>&1

REM Elaborating the design
%VIVADO_BIN%\xelab -debug typical top_tb -s system_sim >> %LOG_FILE% 2>&1

REM Running the simulation
if %ERRORLEVEL% EQU 0 (
    %VIVADO_BIN%\xsim system_sim -R >> %LOG_FILE% 2>&1
) else (
    echo Elaboration failed. >> %LOG_FILE%
)

echo Simulation finished.
