!define BYOK_COMPAT_HOOK_DIR "${__FILEDIR__}"

!macro NSIS_HOOK_PREINSTALL
  InitPluginsDir
  Push $OUTDIR
  SetOutPath "$PLUGINSDIR"
  File /oname=byok-compat.ps1 "${BYOK_COMPAT_HOOK_DIR}\Apply-Compatibility.ps1"
  Pop $0
  SetOutPath "$0"
  byok_compat_check:
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "$PLUGINSDIR\byok-compat.ps1" -CheckOnly'
  Pop $0
  Pop $1
  ${If} $0 == 10
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Please close Cursor, then click Retry to install the compatibility build." /SD IDCANCEL IDRETRY byok_compat_check
    Abort
  ${ElseIf} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "Compatibility preflight failed: $1" /SD IDOK
    Abort
  ${EndIf}
!macroend

!macro NSIS_HOOK_POSTINSTALL
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "$PLUGINSDIR\byok-compat.ps1"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONEXCLAMATION "The application was installed, but compatibility setup needs attention. Close Cursor and run $INSTDIR\compatibility\Apply-Compatibility.ps1. Error: $1" /SD IDOK
  ${EndIf}
!macroend
