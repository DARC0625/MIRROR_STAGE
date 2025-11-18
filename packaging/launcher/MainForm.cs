using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace MirrorStageLauncher;

public class MainForm : Form
{
    private readonly HttpClient _httpClient;
    private readonly TextBox _logBox;
    private readonly Button _installButton;
    private readonly Label _statusLabel;
    private readonly ComboBox _moduleSelector;
    private readonly ModuleOption[] _moduleOptions;
    private ReleaseInfo? _releaseInfo;
    private bool _isInstalling;

    public MainForm()
    {
        Text = "MIRROR STAGE Launcher";
        MinimumSize = new Size(780, 520);
        StartPosition = FormStartPosition.CenterScreen;

        _httpClient = new HttpClient();
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("MirrorStageLauncher/1.0");

        _moduleOptions = new[]
        {
            new ModuleOption(
                "ego",
                "EGO (지휘본부)",
                "NestJS/Flutter 기반 제어 센터",
                "mirror-stage-ego-bundle.zip",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MIRROR_STAGE"),
                ModuleType.Ego),
            new ModuleOption(
                "reflector",
                "REFLECTOR (필드 에이전트)",
                "Python 기반 원격 에이전트",
                "mirror-stage-reflector-bundle.zip",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MIRROR_STAGE_REFLECTOR"),
                ModuleType.Reflector)
        };

        var description = new Label
        {
            Text = "EGO/REFLECTOR 설치·업데이트 런처입니다. 설치 대상을 선택하고 버튼을 눌러주세요.",
            Dock = DockStyle.Top,
            Height = 32,
            TextAlign = ContentAlignment.MiddleLeft
        };

        _moduleSelector = new ComboBox
        {
            Dock = DockStyle.Top,
            DropDownStyle = ComboBoxStyle.DropDownList,
            Height = 32
        };
        _moduleSelector.Items.AddRange(_moduleOptions);
        _moduleSelector.SelectedIndex = 0;
        _moduleSelector.SelectedIndexChanged += (_, _) => UpdateStatusLabel();

        _statusLabel = new Label
        {
            Text = "상태: 확인 중",
            Dock = DockStyle.Top,
            Height = 30,
            ForeColor = Color.SteelBlue,
            TextAlign = ContentAlignment.MiddleLeft
        };

        _logBox = new TextBox
        {
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            Dock = DockStyle.Fill,
            BackColor = Color.FromArgb(21, 21, 23),
            ForeColor = Color.FromArgb(214, 218, 224),
            Font = new Font("Consolas", 9)
        };

        _installButton = new Button
        {
            Text = "설치 / 업데이트",
            Width = 160,
            Height = 38,
            BackColor = Color.FromArgb(0, 123, 205),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat
        };
        _installButton.Click += async (_, _) => await RunInstallationAsync();

        var openInstallLink = new LinkLabel
        {
            Text = "설치 폴더 열기",
            AutoSize = true,
            LinkColor = Color.CornflowerBlue,
        };
        openInstallLink.LinkClicked += (_, _) => OpenInstallFolder();

        var openLogLink = new LinkLabel
        {
            Text = "로그 보기",
            AutoSize = true,
            LinkColor = Color.CornflowerBlue,
        };
        openLogLink.LinkClicked += (_, _) => OpenLatestLog();

        var bottomPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 52,
            FlowDirection = FlowDirection.LeftToRight
        };
        bottomPanel.Controls.Add(_installButton);
        bottomPanel.Controls.Add(openInstallLink);
        bottomPanel.Controls.Add(openLogLink);

        Controls.Add(_logBox);
        Controls.Add(bottomPanel);
        Controls.Add(_statusLabel);
        Controls.Add(_moduleSelector);
        Controls.Add(description);

        Shown += (_, _) => UpdateStatusLabel();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _httpClient.Dispose();
        }
        base.Dispose(disposing);
    }

    private ModuleOption CurrentModule => (ModuleOption)_moduleSelector.SelectedItem!;

    private void UpdateStatusLabel()
    {
        var module = CurrentModule;
        var (status, installed) = GetInstallStatus(module);
        _statusLabel.Text = $"상태: {status}";
        _installButton.Text = installed ? "업데이트" : "설치";
    }

    private (string Status, bool Installed) GetInstallStatus(ModuleOption module)
    {
        bool installed = module.Type switch
        {
            ModuleType.Ego => Directory.Exists(Path.Combine(module.InstallRoot, "ego", "backend")),
            ModuleType.Reflector => Directory.Exists(Path.Combine(module.InstallRoot, "reflector")),
            _ => false
        };

        if (!installed)
        {
            return ("미설치", false);
        }

        var version = GetInstalledVersion(module);
        if (string.IsNullOrWhiteSpace(version))
        {
            return ("설치됨", true);
        }
        return ($"설치됨 (v{version})", true);
    }

    private void AppendLog(string line)
    {
        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(AppendLog), line);
            return;
        }
        var builder = new StringBuilder();
        builder.Append('[').Append(DateTime.Now.ToString("HH:mm:ss")).Append("] ").Append(line);
        _logBox.AppendText(builder.ToString() + Environment.NewLine);
    }

    private async Task RunInstallationAsync()
    {
        if (_isInstalling)
        {
            return;
        }

        var module = CurrentModule;
        _isInstalling = true;
        _installButton.Enabled = false;
        AppendLog($"[{module.DisplayName}] 설치를 준비합니다...");

        try
        {
            var release = await EnsureReleaseInfoAsync();
            var asset = release.Assets.FirstOrDefault(a => string.Equals(a.Name, module.BundleAssetName, StringComparison.OrdinalIgnoreCase));
            if (asset == null)
            {
                throw new InvalidOperationException($"릴리스에 {module.BundleAssetName} 파일이 없습니다. 릴리스를 먼저 생성하세요.");
            }

            var tempDir = Path.Combine(Path.GetTempPath(), "MirrorStageLauncher", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            try
            {
                var bundlePath = await DownloadAssetAsync(asset.BrowserDownloadUrl, Path.Combine(tempDir, module.BundleAssetName));
                var extractDir = Path.Combine(tempDir, "bundle");
                ExtractBundle(module, bundlePath, extractDir);

                var invocation = PrepareModuleInvocation(module, extractDir);
                AppendLog($"{module.DisplayName} 설치 스크립트를 실행합니다...");
                var exitCode = await ExecuteInstallerAsync(invocation.ScriptPath, invocation.Arguments);
                AppendLog($"설치 스크립트 종료 코드: {exitCode}");

                if (exitCode == 0)
                {
                    WriteInstalledVersion(module, release.TagName ?? "latest");
                    MessageBox.Show(this, $"{module.DisplayName} 설치가 완료되었습니다.", "완료", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else
                {
                    MessageBox.Show(this, "설치 중 오류가 발생했습니다. 로그를 확인하세요.", "실패", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            finally
            {
                try { Directory.Delete(tempDir, true); } catch { /* ignore */ }
            }
        }
        catch (Exception ex)
        {
            AppendLog($"오류: {ex.Message}");
            MessageBox.Show(this, ex.Message, "실패", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            _installButton.Enabled = true;
            _isInstalling = false;
            UpdateStatusLabel();
        }
    }

    private async Task<string> DownloadAssetAsync(string url, string destinationPath)
    {
        AppendLog($"번들을 다운로드하는 중... {url}");
        using var response = await _httpClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        await using var network = await response.Content.ReadAsStreamAsync();
        await using var fs = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.ReadWrite);
        await network.CopyToAsync(fs);
        return destinationPath;
    }

    private void ExtractBundle(ModuleOption module, string zipPath, string extractDir)
    {
        Directory.CreateDirectory(extractDir);
        using var archive = ZipFile.OpenRead(zipPath);
        foreach (var entry in archive.Entries)
        {
            if (!ShouldExtractEntry(module, entry.FullName))
            {
                continue;
            }

            var normalized = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            var destinationPath = Path.Combine(extractDir, normalized);
            var destinationDir = Path.GetDirectoryName(destinationPath);
            if (!string.IsNullOrEmpty(destinationDir))
            {
                Directory.CreateDirectory(destinationDir);
            }
            entry.ExtractToFile(destinationPath, overwrite: true);
        }
    }

    private static bool ShouldExtractEntry(ModuleOption module, string entryName)
    {
        entryName = entryName.Replace("\\", "/");
        if (string.IsNullOrWhiteSpace(entryName) || entryName.EndsWith("/"))
        {
            return false;
        }
        if (module.Type == ModuleType.Ego)
        {
            return entryName.StartsWith("ego/") || entryName.EndsWith("install-mirror-stage-ego.ps1");
        }
        if (module.Type == ModuleType.Reflector)
        {
            return entryName.StartsWith("reflector/") || entryName.EndsWith("install-mirror-stage-reflector.ps1");
        }
        return false;
    }

    private (string ScriptPath, string Arguments) PrepareModuleInvocation(ModuleOption module, string extractDir)
    {
        switch (module.Type)
        {
            case ModuleType.Ego:
            {
                var sourceDir = Path.Combine(extractDir, "ego");
                if (!Directory.Exists(sourceDir))
                {
                    throw new DirectoryNotFoundException("번들에서 ego 디렉터리를 찾을 수 없습니다.");
                }
                var targetDir = Path.Combine(module.InstallRoot, "ego");
                CopyDirectory(sourceDir, targetDir);
                RemoveInternalMetadata(targetDir);
                var scriptPath = Path.Combine(extractDir, "install-mirror-stage-ego.ps1");
                return (scriptPath, $"-InstallRoot \"{module.InstallRoot}\"");
            }
            case ModuleType.Reflector:
            {
                var scriptPath = Path.Combine(extractDir, "install-mirror-stage-reflector.ps1");
                if (!File.Exists(scriptPath))
                {
                    throw new FileNotFoundException("번들에 설치 스크립트가 없습니다.", scriptPath);
                }
                return (scriptPath, $"-InstallRoot \"{module.InstallRoot}\"");
            }
            default:
                throw new NotSupportedException("Unknown module type");
        }
    }

    private async Task<int> ExecuteInstallerAsync(string scriptPath, string arguments)
    {
        var tcs = new TaskCompletionSource<int>();
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" {arguments}",
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? Environment.CurrentDirectory
        };

        var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, e) => { if (!string.IsNullOrEmpty(e.Data)) AppendLog(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (!string.IsNullOrEmpty(e.Data)) AppendLog(e.Data); };
        process.Exited += (_, _) =>
        {
            tcs.TrySetResult(process.ExitCode);
            process.Dispose();
        };

        if (!process.Start())
        {
            throw new InvalidOperationException("PowerShell 프로세스를 시작할 수 없습니다.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        return await tcs.Task.ConfigureAwait(false);
    }

    private async Task<ReleaseInfo> EnsureReleaseInfoAsync()
    {
        if (_releaseInfo != null)
        {
            return _releaseInfo;
        }

        var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/repos/DARC0625/MIRROR_STAGE/releases/latest");
        var response = await _httpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync();
        var release = JsonSerializer.Deserialize<ReleaseInfo>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });
        if (release == null)
        {
            throw new InvalidOperationException("릴리스 정보를 파싱할 수 없습니다.");
        }
        _releaseInfo = release;
        AppendLog($"최신 릴리스: {release.TagName}");
        return release;
    }

    private void OpenInstallFolder()
    {
        var module = CurrentModule;
        var path = module.Type switch
        {
            ModuleType.Ego => Path.Combine(module.InstallRoot, "ego"),
            ModuleType.Reflector => Path.Combine(module.InstallRoot, "reflector"),
            _ => module.InstallRoot
        };
        if (!Directory.Exists(path))
        {
            MessageBox.Show(this, "아직 설치되지 않았습니다.", "정보", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        Process.Start("explorer.exe", path);
    }

    private void OpenLatestLog()
    {
        var module = CurrentModule;
        var logDir = module.Type switch
        {
            ModuleType.Ego => Path.Combine(module.InstallRoot, "logs"),
            ModuleType.Reflector => Path.Combine(module.InstallRoot, "logs"),
            _ => module.InstallRoot
        };
        if (!Directory.Exists(logDir))
        {
            MessageBox.Show(this, "로그 폴더가 없습니다.", "정보", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        var latest = new DirectoryInfo(logDir).GetFiles("*.log").OrderByDescending(f => f.LastWriteTimeUtc).FirstOrDefault();
        if (latest == null)
        {
            MessageBox.Show(this, "로그 파일을 찾을 수 없습니다.", "정보", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        Process.Start(new ProcessStartInfo
        {
            FileName = latest.FullName,
            UseShellExecute = true
        });
    }

    private static void CopyDirectory(string sourceDir, string destinationDir)
    {
        if (Directory.Exists(destinationDir))
        {
            Directory.Delete(destinationDir, true);
        }
        Directory.CreateDirectory(destinationDir);
        foreach (var file in Directory.GetFiles(sourceDir, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(sourceDir, file);
            var targetPath = Path.Combine(destinationDir, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(targetPath)!);
            File.Copy(file, targetPath, true);
        }
    }

    private static void RemoveInternalMetadata(string directory)
    {
        var patterns = new[] { ".git", "node_modules", ".dart_tool", "build" };
        foreach (var pattern in patterns)
        {
            var matches = Directory.Exists(directory)
                ? Directory.GetDirectories(directory, pattern, SearchOption.AllDirectories)
                : Array.Empty<string>();
            foreach (var match in matches)
            {
                try
                {
                    Directory.Delete(match, true);
                }
                catch
                {
                    // ignore
                }
            }
        }
    }

    private string? GetInstalledVersion(ModuleOption module)
    {
        var marker = Path.Combine(module.InstallRoot, $".{module.Id}.version");
        return File.Exists(marker) ? File.ReadAllText(marker).Trim() : null;
    }

    private void WriteInstalledVersion(ModuleOption module, string version)
    {
        var marker = Path.Combine(module.InstallRoot, $".{module.Id}.version");
        Directory.CreateDirectory(Path.GetDirectoryName(marker)!);
        File.WriteAllText(marker, version);
    }

    private record ModuleOption(string Id, string DisplayName, string Description, string BundleAssetName, string InstallRoot, ModuleType Type)
    {
        public override string ToString() => DisplayName;
    }

    private enum ModuleType
    {
        Ego,
        Reflector
    }

    private record ReleaseInfo(string? TagName, AssetInfo[] Assets);

    private record AssetInfo
    {
        public string Name { get; init; } = string.Empty;

        [JsonPropertyName("browser_download_url")]
        public string BrowserDownloadUrl { get; init; } = string.Empty;
    }
}
