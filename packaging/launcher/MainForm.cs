using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
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
    private bool _isInstalling;
    private const string RepoOwner = "DARC0625";
    private const string RepoName = "MIRROR_STAGE";
    private const string RepoBranch = "main";
    private static readonly string RepoArchiveUrl = $"https://codeload.github.com/{RepoOwner}/{RepoName}/zip/refs/heads/{RepoBranch}";
    private static readonly string RepoApiBase = $"https://api.github.com/repos/{RepoOwner}/{RepoName}";
    private const string DefaultArchiveUrl = "https://www.darc.kr/mirror-stage-latest.zip";
    private const string DefaultVersionInfoUrl = "https://www.darc.kr/mirror-stage-version.json";
    private readonly LauncherConfig _config;
    private readonly string _archiveUrl;
    private readonly string? _versionInfoUrl;

    public MainForm()
    {
        Text = "MIRROR STAGE Launcher";
        MinimumSize = new Size(780, 520);
        StartPosition = FormStartPosition.CenterScreen;

        _httpClient = new HttpClient();
        _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("MirrorStageLauncher/1.0");
        _config = LauncherConfig.Load();
        var configArchive = string.IsNullOrWhiteSpace(_config.SourceArchiveUrl) ? null : _config.SourceArchiveUrl;
        var configVersion = string.IsNullOrWhiteSpace(_config.VersionInfoUrl) ? null : _config.VersionInfoUrl;
        _archiveUrl = configArchive ?? DefaultArchiveUrl ?? RepoArchiveUrl;
        _versionInfoUrl = configVersion ?? DefaultVersionInfoUrl;

        _moduleOptions = new[]
        {
            new ModuleOption(
                "ego",
                "EGO (지휘본부)",
                "NestJS/Flutter 기반 제어 센터",
                "ego/",
                "packaging/install-mirror-stage-ego.ps1",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MIRROR_STAGE"),
                ModuleType.Ego),
            new ModuleOption(
                "reflector",
                "REFLECTOR (필드 에이전트)",
                "Python 기반 원격 에이전트",
                "reflector/",
                "packaging/install-mirror-stage-reflector.ps1",
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
            var tempDir = Path.Combine(Path.GetTempPath(), "MirrorStageLauncher", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            try
            {
                var archivePath = Path.Combine(tempDir, "mirror_stage_source.zip");
                await DownloadFileAsync(_archiveUrl, archivePath, "소스 아카이브");
                var extractDir = Path.Combine(tempDir, "bundle");
                ExtractBundle(module, archivePath, extractDir);

                var invocation = PrepareModuleInvocation(module, extractDir);
                AppendLog($"{module.DisplayName} 설치 스크립트를 실행합니다...");
                var exitCode = await ExecuteInstallerAsync(invocation.ScriptPath, invocation.Arguments);
                AppendLog($"설치 스크립트 종료 코드: {exitCode}");

                if (exitCode == 0)
                {
                    var version = await FetchLatestCommitShaAsync();
                    WriteInstalledVersion(module, version ?? DateTime.UtcNow.ToString("yyyyMMddHHmmss"));
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

    private async Task<string> DownloadFileAsync(string url, string destinationPath, string description)
    {
        AppendLog($"{description} 다운로드 중... {url}");
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
            var trimmedPath = TrimArchivePrefix(entry.FullName);
            if (string.IsNullOrWhiteSpace(trimmedPath) || IsBlockedEntry(trimmedPath))
            {
                continue;
            }
            if (!ShouldExtractEntry(module, trimmedPath))
            {
                continue;
            }

            var normalized = trimmedPath.Replace('/', Path.DirectorySeparatorChar);
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

        static bool IsSkipped(string name)
        {
            var skipSegments = new[] {"/.git/", "/node_modules/", "/.dart_tool/", "/build/"};
            return skipSegments.Any(name.Contains);
        }

        if (IsSkipped(entryName))
        {
            return false;
        }

        if (entryName.StartsWith(module.SourceRoot, StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return string.Equals(entryName, module.InstallerScriptPath, StringComparison.OrdinalIgnoreCase);
    }

    private (string ScriptPath, string Arguments) PrepareModuleInvocation(ModuleOption module, string extractDir)
    {
        switch (module.Type)
        {
            case ModuleType.Ego:
            {
                var sourceDir = Path.Combine(extractDir, NormalizeRelativeDirectory(module.SourceRoot));
                if (!Directory.Exists(sourceDir))
                {
                    throw new DirectoryNotFoundException("번들에서 ego 디렉터리를 찾을 수 없습니다.");
                }
                var targetDir = Path.Combine(module.InstallRoot, "ego");
                CopyDirectory(sourceDir, targetDir);
                RemoveInternalMetadata(targetDir);
                var scriptPath = Path.Combine(extractDir, NormalizeRelativeDirectory(module.InstallerScriptPath));
                return (scriptPath, $"-InstallRoot \"{module.InstallRoot}\"");
            }
            case ModuleType.Reflector:
            {
                var scriptPath = Path.Combine(extractDir, NormalizeRelativeDirectory(module.InstallerScriptPath));
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

    private static string NormalizeRelativeDirectory(string relativePath)
    {
        var trimmed = relativePath.Trim('/');
        return trimmed.Replace('/', Path.DirectorySeparatorChar);
    }

    private static string TrimArchivePrefix(string entryName)
    {
        var normalized = entryName.Replace("\\", "/");
        var slashIndex = normalized.IndexOf('/');
        return slashIndex >= 0 ? normalized[(slashIndex + 1)..] : normalized;
    }

    private static bool IsBlockedEntry(string entryName)
    {
        var normalized = entryName.Replace("\\", "/");
        if (string.IsNullOrWhiteSpace(normalized))
        {
            return true;
        }

        if (normalized.StartsWith(".git/", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("/.git/", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return normalized.StartsWith(".github/", StringComparison.OrdinalIgnoreCase);
    }

    private async Task<string?> FetchLatestCommitShaAsync()
    {
        var candidates = new List<(string Url, bool IsCustom)>
        {
            (_versionInfoUrl ?? string.Empty, true),
            ($"{RepoApiBase}/commits/{RepoBranch}", false)
        }.Where(c => !string.IsNullOrWhiteSpace(c.Url)).ToList();

        foreach (var candidate in candidates)
        {
            try
            {
                var request = new HttpRequestMessage(HttpMethod.Get, candidate.Url);
                var response = await _httpClient.SendAsync(request);
                response.EnsureSuccessStatusCode();
                await using var stream = await response.Content.ReadAsStreamAsync();
                using var document = await JsonDocument.ParseAsync(stream);
                if (candidate.IsCustom)
                {
                    if (document.RootElement.TryGetProperty("sha", out var shaElementCustom))
                    {
                        var customSha = shaElementCustom.GetString();
                        if (!string.IsNullOrWhiteSpace(customSha))
                        {
                            return NormalizeSha(customSha);
                        }
                    }
                }
                else if (document.RootElement.TryGetProperty("sha", out var shaElement))
                {
                    var sha = shaElement.GetString();
                    if (!string.IsNullOrWhiteSpace(sha))
                    {
                        return NormalizeSha(sha);
                    }
                }
            }
            catch (Exception ex)
            {
                AppendLog($"최신 커밋 정보를 가져오지 못했습니다({candidate.Url}): {ex.Message}");
            }
        }
        return null;
    }

    private static string NormalizeSha(string sha)
    {
        var trimmed = sha.Trim();
        return trimmed.Length > 7 ? trimmed[..7] : trimmed;
    }

    private record ModuleOption(string Id, string DisplayName, string Description, string SourceRoot, string InstallerScriptPath, string InstallRoot, ModuleType Type)
    {
        public override string ToString() => DisplayName;
    }

    private enum ModuleType
    {
        Ego,
        Reflector
    }

    private record LauncherConfig(string? SourceArchiveUrl, string? VersionInfoUrl)
    {
        public static LauncherConfig Load()
        {
            try
            {
                var baseDir = AppContext.BaseDirectory;
                var configPath = Path.Combine(baseDir, "launcher-config.json");
                if (!File.Exists(configPath))
                {
                    return new LauncherConfig(null, null);
                }

                var text = File.ReadAllText(configPath);
                var config = JsonSerializer.Deserialize<LauncherConfig>(text, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
                return config ?? new LauncherConfig(null, null);
            }
            catch
            {
                return new LauncherConfig(null, null);
            }
        }
    }
}
