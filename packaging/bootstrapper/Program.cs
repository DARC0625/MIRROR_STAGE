using System.Diagnostics;
using System.Reflection;

var exeDir = AppContext.BaseDirectory;
var scriptPath = Path.Combine(exeDir, "install-mirror-stage-ego.ps1");
if (!File.Exists(scriptPath))
{
    Console.Error.WriteLine("install-mirror-stage-ego.ps1 not found next to bootstrapper (expected at {0})", scriptPath);
    return 1;
}

var installRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MIRROR_STAGE");
var arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" -InstallRoot \"{installRoot}\"";

var psi = new ProcessStartInfo
{
    FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"),
    Arguments = arguments,
    UseShellExecute = false,
    RedirectStandardOutput = false,
    RedirectStandardError = false,
    WorkingDirectory = exeDir,
};

try
{
    using var process = Process.Start(psi);
    if (process == null)
    {
        Console.Error.WriteLine("Failed to start PowerShell bootstrapper.");
        return 1;
    }
    process.WaitForExit();
    return process.ExitCode;
}
catch (Exception ex)
{
    Console.Error.WriteLine("Bootstrapper failed: {0}", ex);
    return 1;
}
