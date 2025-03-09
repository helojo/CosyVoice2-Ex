# 命令行参数
param (
    [switch]$MakeZip = $false,
    [switch]$NoModel = $false,
    [switch]$NoEnv = $false,
    [string]$Tag = (Get-Date).ToString("yyyy-MM-dd")
)

# 设置变量
$ProjectName = "CosyVoice2-Ex"
$CondaEnvName = "cosyvoice"
$ProjectRoot = $PSScriptRoot
$TempDir = Join-Path $ProjectRoot ".build_temp"
$OutputDir = Join-Path $TempDir "${ProjectName}_Portable"
$EnvTarFile = Join-Path $TempDir "env.tar.gz"
$EnvHashFile = Join-Path $TempDir "env_hash.txt"

# 设置编码为UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# 获取conda环境的包列表hash（排除注释行）
function Get-CondaEnvHash {
    param (
        [string]$EnvName
    )
    $packageList = (conda list -n $EnvName | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($packageList))
    return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
}

# 显示进度条
function Show-BuildProgress {
    param (
        [string]$Status,
        [int]$PercentComplete
    )
    Write-Progress -Activity "打包进度" -Status $Status -PercentComplete $PercentComplete
}

Write-Host "开始打包便携版..."
Show-BuildProgress -Status "初始化..." -PercentComplete 0


# 创建临时目录
if (-not (Test-Path $TempDir)) {
    New-Item -Path $TempDir -ItemType Directory | Out-Null
}

Show-BuildProgress -Status "准备输出目录..." -PercentComplete 10
# 创建输出目录
if (Test-Path $OutputDir) {
    Write-Host "清理旧的输出目录..."
    Remove-Item -Path $OutputDir -Recurse -Force
}
New-Item -Path $OutputDir -ItemType Directory | Out-Null
New-Item -Path (Join-Path $OutputDir "env") -ItemType Directory | Out-Null

# 检查conda环境是否需要更新
Show-BuildProgress -Status "检查conda环境..." -PercentComplete 20

if ($NoEnv) {
    Write-Host "已启用NoEnv，跳过复制conda环境..."
} else {
    $NeedUpdateEnv = $true
    if (Test-Path $EnvTarFile) {
        Write-Host "检查conda环境是否有更新..." -NoNewline
        $CurrentHash = Get-CondaEnvHash -EnvName $CondaEnvName
        if (Test-Path $EnvHashFile) {
            $OldHash = Get-Content $EnvHashFile
            if ($CurrentHash -eq $OldHash) {
                Write-Host "依赖未变动，使用缓存文件" -NoNewline
                $NeedUpdateEnv = $false
            }
        }
        Write-Host ""
    }

    # 导出或复制conda环境
    if ($NeedUpdateEnv) {
        Show-BuildProgress -Status "导出conda环境..." -PercentComplete 30
        Write-Host "正在导出conda环境..."
        conda pack -n $CondaEnvName -o $EnvTarFile
        # 保存环境hash
        Get-CondaEnvHash -EnvName $CondaEnvName > $EnvHashFile
    }

    Show-BuildProgress -Status "解压环境..." -PercentComplete 40
    Write-Host "正在解压环境..."
    tar -xzf $EnvTarFile -C (Join-Path $OutputDir "env")
}

# 设置需要排除的目录
$ExcludeDirs = @(
    "\.build_temp",
    "\.git",
    "__pycache__",
    "\.pytest_cache",
    "\.idea",
    ".*\.egg-info",
    "\.ipynb_checkpoints",
    "\.vscode",
    "\.history",
    "env"
)

# 复制项目文件，排除指定目录
Show-BuildProgress -Status "复制项目文件..." -PercentComplete 60
Write-Host "正在复制项目文件..." -NoNewline

# 根据NoModel参数决定是否排除模型目录
if ($NoModel) {
    Write-Host "启用-NoModel参数，跳过复制模型文件..." -NoNewline
    $ExcludeDirs += "pretrained_models"
}
Write-Host ""

# 递归复制文件，排除指定目录
Get-ChildItem -Path $ProjectRoot -Recurse | 
    Where-Object { 
        $item = $_
        -not ($ExcludeDirs | Where-Object { $item.FullName -match [regex]::Escape($_) })
    } | 
    ForEach-Object {
        $targetPath = $_.FullName.Replace($ProjectRoot, $OutputDir)
        if ($_.PSIsContainer) {
            if (-not (Test-Path $targetPath)) {
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
            }
        } else {
            $targetDir = Split-Path -Parent $targetPath
            if (-not (Test-Path $targetDir)) {
                New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path $_.FullName -Destination $targetPath -Force
        }
    }

# 创建启动脚本
Show-BuildProgress -Status "创建启动脚本..." -PercentComplete 70
Write-Host "创建启动脚本..."

# WebUI启动脚本
$webuiScript = @"
@echo off
>nul chcp 65001

title CosyVoice2-Ex WebUI Build $Tag
color 0f

echo.
<nul set /p="╔════════════════════════════════════════════════════════════════════════════════════╗" & echo.
<nul set /p="║                                                                                    ║" & echo.
<nul set /p="║   ██████╗  ██████╗ ███████╗██╗   ██╗██╗   ██╗ ██████╗ ██╗ ██████╗███████╗██████╗   ║" & echo.
<nul set /p="║  ██╔════╝ ██╔═══██╗██╔════╝╚██╗ ██╔╝██║   ██║██╔═══██╗██║██╔════╝██╔════╝╚════██╗  ║" & echo.
<nul set /p="║  ██║      ██║   ██║███████╗ ╚████╔╝ ██║   ██║██║   ██║██║██║     █████╗   █████╔╝  ║" & echo.
<nul set /p="║  ██║      ██║   ██║╚════██║  ╚██╔╝  ╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ██╔═══╝   ║" & echo.
<nul set /p="║  ╚██████╗ ╚██████╔╝███████║   ██║    ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗███████╗  ║" & echo.
<nul set /p="║   ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝     ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚══════╝  ║" & echo.
<nul set /p="║                                                                                    ║" & echo.
<nul set /p="╚════════════════════════════════════════════════════════════════════════════════════╝" & echo.
echo                            CosyVoice2-Ex WebUI 服务正在启动...
echo                        https://github.com/journey-ad/CosyVoice2-Ex
echo.

:: 设置基础路径
set BASE_DIR=%~dp0
set CONDA_ENV=%BASE_DIR%env

:: 激活conda环境
call "%CONDA_ENV%\Scripts\activate.bat"

:: 设置环境变量
set PYTHONPATH=%BASE_DIR%
set HF_HOME=%BASE_DIR%hf_download
set PATH=%CONDA_ENV%\Scripts;%CONDA_ENV%\Library\bin;%PATH%

:: 运行程序
echo 正在启动WebUI服务，请稍候...
python webui.py --port 8080 --open --log_level INFO
pause
"@
Set-Content -Path (Join-Path $OutputDir "运行-CosyVoice2-Ex.bat") -Value $webuiScript -Encoding UTF8


# API服务启动脚本
$apiScript = @"
@echo off
>nul chcp 65001

title CosyVoice2-Ex API Build $Tag
color 1f

echo.
<nul set /p="╔════════════════════════════════════════════════════════════════════════════════════╗" & echo.
<nul set /p="║                                                                                    ║" & echo.
<nul set /p="║   ██████╗  ██████╗ ███████╗██╗   ██╗██╗   ██╗ ██████╗ ██╗ ██████╗███████╗██████╗   ║" & echo.
<nul set /p="║  ██╔════╝ ██╔═══██╗██╔════╝╚██╗ ██╔╝██║   ██║██╔═══██╗██║██╔════╝██╔════╝╚════██╗  ║" & echo.
<nul set /p="║  ██║      ██║   ██║███████╗ ╚████╔╝ ██║   ██║██║   ██║██║██║     █████╗   █████╔╝  ║" & echo.
<nul set /p="║  ██║      ██║   ██║╚════██║  ╚██╔╝  ╚██╗ ██╔╝██║   ██║██║██║     ██╔══╝  ██╔═══╝   ║" & echo.
<nul set /p="║  ╚██████╗ ╚██████╔╝███████║   ██║    ╚████╔╝ ╚██████╔╝██║╚██████╗███████╗███████╗  ║" & echo.
<nul set /p="║   ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝     ╚═══╝   ╚═════╝ ╚═╝ ╚═════╝╚══════╝╚══════╝  ║" & echo.
<nul set /p="║                                                                                    ║" & echo.
<nul set /p="╚════════════════════════════════════════════════════════════════════════════════════╝" & echo.
echo                           CosyVoice2-Ex API 服务正在启动...
echo                      https://github.com/journey-ad/CosyVoice2-Ex
echo.

:: 设置基础路径
set BASE_DIR=%~dp0
set CONDA_ENV=%BASE_DIR%env

:: 激活conda环境
call "%CONDA_ENV%\Scripts\activate.bat"

:: 设置环境变量
set PYTHONPATH=%BASE_DIR%
set HF_HOME=%BASE_DIR%hf_download
set PATH=%CONDA_ENV%\Scripts;%CONDA_ENV%\Library\bin;%PATH%

:: 运行程序
echo 正在启动API服务，请稍候...
python api.py
pause
"@
Set-Content -Path (Join-Path $OutputDir "启动接口服务.bat") -Value $apiScript -Encoding UTF8

# 创建README
Show-BuildProgress -Status "创建README..." -PercentComplete 80
Write-Host "创建README文件..."
$readme = @"
CosyVoice2-Ex 便携版 Build $Tag
项目地址：https://github.com/journey-ad/CosyVoice2-Ex
================================

【使用说明】
1. 双击 运行-CosyVoice2-Ex.bat 启动WebUI界面
2. 双击 启动接口服务.bat 启动API服务
3. 首次运行可能需要等待环境配置，请耐心等待
4. 模型文件将在首次运行时自动下载到 pretrained_models 目录，也可以手动下载 https://www.modelscope.cn/models/iic/CosyVoice2-0.5B

【注意事项】
- 仅支持 Windows 系统 + NVIDIA 显卡，确保已安装显卡驱动
- 如果需要修改启动端口，可以编辑 bat 脚本

【使用限制】
- 请勿侵犯他人知识产权或其他合法权益
- 遵守相关法律法规，禁止用于制作违法违规内容
- 禁止用于制作虚假信息或误导性内容
- 使用本项目所产生的一切后果由使用者自行承担，项目开发者不承担任何法律责任
- 使用本项目即表示您已阅读并同意以上声明

【开源协议】
本项目基于 Apache 2.0 协议开源

                                 Apache License
                           版本 2.0，2004年1月
                        http://www.apache.org/licenses/

   使用、复制和分发的条款和条件

   1. 定义
      "许可证"是指根据本文档第1到第9部分所定义的使用、复制和分发的条款和条件。

      "许可人"是指版权所有者或由版权所有者授权的授予许可证的实体。

      "法律实体"是指实施实体和所有其他控制、受控制或与该实体共同控制的实体的联合。
      就本定义而言，"控制"是指(i)直接或间接领导或管理该实体的权力，无论是通过合同还是其他方式，
      或(ii)拥有百分之五十(50%)或更多的已发行股份，或(iii)该实体的实益所有权。

      "您"(或"您的")是指行使本许可证授予的权限的个人或法律实体。

      "源代码"形式是指进行修改的首选形式，包括但不限于软件源代码、文档源代码和配置文件。

      "目标"形式是指源代码形式机械转换或翻译后的任何形式，包括但不限于编译后的目标代码、
      生成的文档以及转换为其他媒体类型。

      "作品"是指根据许可证提供的版权作品，无论是源代码形式还是目标形式，
      如包含在或附加到作品中的版权声明所示（下面的附录中提供了一个示例）。

      "衍生作品"是指基于作品（或从作品衍生）的任何作品，无论是源代码形式还是目标形式，
      其编辑修订、注释、详细描述或其他修改作为一个整体代表原创的版权作品。就本许可证而言，
      衍生作品不应包括与作品及其衍生作品的接口保持可分离的作品，或仅仅是链接（或按名称绑定）到作品及其衍生作品的接口。

   2. 版权许可证的授予
      在遵守本许可证条款和条件的前提下，每个贡献者特此授予您永久性的、全球性的、非独占的、免费的、
      免版税的、不可撤销的版权许可证，以源代码形式或目标形式复制、准备衍生作品、公开展示、公开表演、
      再许可和分发作品及其衍生作品。

   3. 专利许可证的授予
      在遵守本许可证条款和条件的前提下，每个贡献者特此授予您永久性的、全球性的、非独占的、免费的、
      免版税的、不可撤销的（除本节说明外）专利许可证，以制造、委托制造、使用、许诺销售、销售、进口
      和以其他方式转让作品。

   4. 再分发
      您可以在任何媒介中复制和分发作品或其衍生作品的副本，无论是否修改，也无论是源代码形式还是目标形式，
      只要您满足以下条件：

      (a) 您必须向作品或衍生作品的任何其他接收者提供本许可证的副本；

      (b) 您必须使任何修改过的文件带有明显的声明，说明您修改了这些文件；

      (c) 您必须在分发的任何衍生作品的源代码形式中，保留作品源代码形式中的所有版权、专利、商标和归属声明，
          但不包括不属于衍生作品任何部分的声明；

      (d) 如果作品包含"NOTICE"文本文件作为其分发的一部分，那么您分发的任何衍生作品必须
          包含该NOTICE文件中包含的归属声明的可读副本。

   5. 提交贡献
      除非您明确声明，否则您有意提交以包含在作品中的任何贡献都应遵守本许可证的条款和条件，
      无任何额外的条款或条件。

   6. 商标
      本许可证不授予使用许可人的商号、商标、服务标记或产品名称的权限，除非在描述作品来源和复制NOTICE文件内容时
      需要合理和习惯使用。

   7. 免责声明
      除非适用法律要求或书面同意，许可人以"按原样"基础提供作品（和每个贡献者提供其贡献），
      不提供任何明示或暗示的保证或条件，包括但不限于所有权、非侵权、适销性或特定用途适用性的保证或条件。

   8. 责任限制
      在任何情况下，任何贡献者都不对您承担任何损害赔偿责任，包括任何直接的、间接的、特殊的、
      偶然的或后果性的损害，除非适用法律要求或书面同意。

   9. 接受保证或附加责任
      在重新分发作品或其衍生作品时，您可以选择提供并收取费用，以获得支持、保证、赔偿或其他符合本许可证的
      责任义务和/或权利。但是，在承担此类义务时，您只能代表您自己并独自负责。

   条款和条件结束

   附录：如何将Apache许可证应用到您的作品

      要将Apache许可证应用到您的作品，请附加以下标准声明，用方括号"[]"中的字段替换为您自己的标识信息。
      （不要包含方括号！）文本应该用文件格式的适当注释语法括起来。

   Copyright [2024] [版权所有者名称]

   根据Apache许可证2.0版（"许可证"）获得许可；
   除非遵守许可证，否则您不得使用此文件。
   您可以在以下位置获得许可证副本：

       http://www.apache.org/licenses/LICENSE-2.0

   除非适用法律要求或书面同意，否则根据许可证分发的软件是基于"按原样"基础分发的，
   不附带任何明示或暗示的保证或条件。
   请参阅许可证以了解许可证下的特定语言和限制。 
"@
Set-Content -Path (Join-Path $OutputDir "便携版使用说明.txt") -Value $readme -Encoding UTF8

if ($MakeZip) {
    # 打包成zip
    Show-BuildProgress -Status "创建压缩包..." -PercentComplete 90
    Write-Host "正在创建最终压缩包..."
    $ZipFile = Join-Path $ProjectRoot "${ProjectName}_Portable.zip"
    Compress-Archive -Path (Join-Path $OutputDir "*") -DestinationPath $ZipFile -Force

    Show-BuildProgress -Status "完成" -PercentComplete 100
    Write-Host "打包完成！"
    Write-Host "输出文件：$ZipFile"
} else {
    Show-BuildProgress -Status "完成" -PercentComplete 100
    Write-Host "打包完成！"
    Write-Host "输出目录：$OutputDir"
}

pause
