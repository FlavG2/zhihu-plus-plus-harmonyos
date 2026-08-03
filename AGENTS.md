# Agent Notes

## HarmonyOS Build Check

- This repository does not currently include a local `hvigorw` wrapper at the root.
- Use the DevEco Studio bundled Hvigor wrapper:

```powershell
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=entry assembleHap --no-daemon
```

- If Hvigor reports a missing cached `hvigor.js` under `C:\Users\XLW\.hvigor\project_caches\...\workspace`, remove only that reported `workspace` cache directory and retry.
- In this environment, `DEVECO_SDK_HOME` may be unset or invalid. Set it for the current command to the DevEco SDK path:

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
```

- If packaging/signing fails with `spawn java ENOENT`, prepend DevEco Studio's bundled JBR to `PATH` for the current command:

```powershell
$env:PATH = 'C:\Program Files\Huawei\DevEco Studio\jbr\bin;' + $env:PATH
```

- Full working check command used in this workspace:

```powershell
$env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
$env:PATH = 'C:\Program Files\Huawei\DevEco Studio\jbr\bin;' + $env:PATH
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p module=entry assembleHap --no-daemon
```

- Existing ArkTS warnings about deprecated APIs and functions that may throw are currently expected; treat new compile errors as actionable.
