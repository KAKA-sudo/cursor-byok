param(
    [string]$ProfileRoot = [Environment]::GetFolderPath('UserProfile'),
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'

# Installation must not race with Cursor writing its settings/database.
if ([IO.Path]::GetFullPath($ProfileRoot).TrimEnd('\') -eq [Environment]::GetFolderPath('UserProfile').TrimEnd('\')) {
    if (Get-Process -Name 'Cursor' -ErrorAction SilentlyContinue) {
        Write-Output 'Please close Cursor before installing this compatibility build.'
        exit 10
    }
}
if ($CheckOnly) { exit 0 }

$backupRoot = Join-Path $ProfileRoot ('AppData\Local\Cursor BYOK Repair\installer-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$settingsPath = Join-Path $ProfileRoot 'AppData\Roaming\Cursor\User\settings.json'
if (Test-Path -LiteralPath $settingsPath) {
    $settings = [IO.File]::ReadAllText($settingsPath)
    $updated = [regex]::Replace($settings, '("cursor\.general\.disableHttp1SSE"\s*:\s*)true', '${1}false')
    if ($updated -ne $settings) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Copy-Item -LiteralPath $settingsPath -Destination (Join-Path $backupRoot 'cursor-settings-original.json')
        [IO.File]::WriteAllText($settingsPath, $updated, [Text.UTF8Encoding]::new($false))
    }
}

$statePath = Join-Path $ProfileRoot 'AppData\Roaming\Cursor\User\globalStorage\state.vscdb'
if (-not (Test-Path -LiteralPath $statePath)) {
    Write-Output 'No existing Cursor cache; BYOK will supply compatibility gates on first connection.'
    exit 0
}

# Windows supplies SQLite. The installer does not need Python or Node.js.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ByokInstallerSqlite {
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_open_v2(byte[] path, out IntPtr db, int flags, IntPtr vfs);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_close(IntPtr db);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_busy_timeout(IntPtr db, int milliseconds);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int size, out IntPtr stmt, IntPtr tail);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_step(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_column_text(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_column_bytes(IntPtr stmt, int column);
    [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
    private static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] text, int size, IntPtr destructor);
    private static byte[] Utf8(string text) { return Encoding.UTF8.GetBytes(text + "\0"); }
    private static void Check(int result) { if (result != 0) throw new Exception("SQLite error " + result); }
    public static IntPtr Open(string path) {
        IntPtr db;
        int result = sqlite3_open_v2(Utf8(path), out db, 2, IntPtr.Zero);
        if (result != 0) { if (db != IntPtr.Zero) sqlite3_close(db); Check(result); }
        sqlite3_busy_timeout(db, 5000);
        return db;
    }
    public static void Close(IntPtr db) { Check(sqlite3_close(db)); }
    public static string Read(IntPtr db) {
        IntPtr statement;
        Check(sqlite3_prepare_v2(db, Utf8("SELECT value FROM ItemTable WHERE key='workbench.experiments.statsigBootstrap'"), -1, out statement, IntPtr.Zero));
        try {
            int result = sqlite3_step(statement);
            if (result == 101) return null;
            if (result != 100) throw new Exception("SQLite read error " + result);
            int size = sqlite3_column_bytes(statement, 0);
            byte[] bytes = new byte[size];
            Marshal.Copy(sqlite3_column_text(statement, 0), bytes, 0, size);
            return Encoding.UTF8.GetString(bytes);
        } finally { sqlite3_finalize(statement); }
    }
    public static void Write(IntPtr db, string value) {
        IntPtr statement;
        Check(sqlite3_prepare_v2(db, Utf8("UPDATE ItemTable SET value=? WHERE key='workbench.experiments.statsigBootstrap'"), -1, out statement, IntPtr.Zero));
        try {
            byte[] bytes = Encoding.UTF8.GetBytes(value);
            Check(sqlite3_bind_text(statement, 1, bytes, bytes.Length, new IntPtr(-1)));
            int result = sqlite3_step(statement);
            if (result != 101) throw new Exception("SQLite update error " + result);
        } finally { sqlite3_finalize(statement); }
    }
}
'@

$database = [ByokInstallerSqlite]::Open($statePath)
try {
    $raw = [ByokInstallerSqlite]::Read($database)
    if ([string]::IsNullOrEmpty($raw)) { Write-Output 'No existing bootstrap cache to update.'; exit 0 }
    $cache = $raw | ConvertFrom-Json
    if (-not $cache.PSObject.Properties['feature_gates']) { Write-Output 'No existing feature gate cache to update.'; exit 0 }
    $name = 'agent_host_local_loop'
    switch ($cache.hash_used) {
        'djb2' {
            [uint64]$hash = 0
            foreach ($character in $name.ToCharArray()) { $hash = (($hash * 31) + [uint16]$character) -band 0xffffffffL }
            $gateKey = $hash.ToString()
        }
        'sha256' {
            $hasher = [Security.Cryptography.SHA256]::Create()
            try { $gateKey = [Convert]::ToBase64String($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($name))) } finally { $hasher.Dispose() }
        }
        default { $gateKey = $name }
    }
    $gate = $cache.feature_gates.PSObject.Properties[$gateKey]
    if ($null -ne $gate -and $gate.Value.value -ne $false) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $backupRoot 'cursor-statsig-bootstrap-original.json'), $raw, [Text.UTF8Encoding]::new($false))
        $gate.Value.value = $false
        [ByokInstallerSqlite]::Write($database, ($cache | ConvertTo-Json -Depth 100 -Compress))
    }
    Write-Output 'Compatibility settings applied. Original values were backed up when changed.'
} finally {
    [ByokInstallerSqlite]::Close($database)
}
