# Сборка сайта для хостинга: из index.html делает dist/ без внешних CDN.
# - Tailwind собирается один раз (npx tailwindcss@3) и встраивается в <style>.
# - Шрифты Raleway и Unbounded скачиваются с Google Fonts в dist/fonts (кириллица + латиница).
# Запуск из папки проекта:  powershell -ExecutionPolicy Bypass -File build\build.ps1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root  = Split-Path $PSScriptRoot -Parent
$build = $PSScriptRoot
$dist  = Join-Path $root 'dist'
$utf8  = New-Object Text.UTF8Encoding $false
$src   = [IO.File]::ReadAllText((Join-Path $root 'index.html'))

# 1. Конфиг Tailwind берётся прямо из index.html, чтобы не держать его в двух местах.
$m = [regex]::Match($src, 'tailwind\.config = (\{[\s\S]*?\n    \});')
if (-not $m.Success) { throw 'Не найден tailwind.config в index.html' }
$content = (Join-Path $root 'index.html') -replace '\\', '/'
$cfg = "function c(v) { return 'rgb(var(' + v + ') / <alpha-value>)'; }`nmodule.exports = Object.assign({ content: ['$content'] }, $($m.Groups[1].Value));`n"
[IO.File]::WriteAllText((Join-Path $build 'tailwind.config.js'), $cfg, $utf8)
[IO.File]::WriteAllText((Join-Path $build 'input.css'), "@tailwind base;`n@tailwind components;`n@tailwind utilities;`n", $utf8)
$css = Join-Path $build 'tailwind.out.css'
& npx --yes tailwindcss@3 -c (Join-Path $build 'tailwind.config.js') -i (Join-Path $build 'input.css') -o $css --minify
if ($LASTEXITCODE -ne 0) { throw 'Tailwind не собрался' }

# 2. Шрифты: берём CSS Google Fonts, оставляем нужные наборы символов, файлы кладём локально.
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $dist 'fonts') | Out-Null
$fm = [regex]::Match($src, 'href="(https://fonts\.googleapis\.com/css2\?[^"]+)"')
$ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$gcss = (Invoke-WebRequest ($fm.Groups[1].Value -replace '&amp;', '&') -UserAgent $ua -UseBasicParsing).Content
$faces = @()
foreach ($blk in [regex]::Matches($gcss, '/\* ([\w-]+) \*/\s*(@font-face \{[\s\S]*?\})')) {
  if ($blk.Groups[1].Value -notin 'cyrillic', 'cyrillic-ext', 'latin', 'latin-ext') { continue }
  $face = $blk.Groups[2].Value
  $url = [regex]::Match($face, 'url\((https://[^)]+\.woff2)\)').Groups[1].Value
  $name = ([regex]::Match($face, "font-family: '([^']+)'").Groups[1].Value -replace ' ', '') + '-' + [IO.Path]::GetFileName($url)
  $file = Join-Path $dist "fonts\$name"
  if (-not (Test-Path $file)) { Invoke-WebRequest $url -OutFile $file -UseBasicParsing }
  $faces += $face.Replace($url, "fonts/$name")
}
if (-not $faces.Count) { throw 'Шрифты не найдены' }

# 3. dist/index.html: убираем CDN Tailwind и Google Fonts, вставляем собранные стили.
$out = [regex]::Replace($src, '\s*<link rel="preconnect" href="https://fonts\.googleapis\.com">\s*<link rel="preconnect" href="https://fonts\.gstatic\.com" crossorigin>\s*<link href="https://fonts\.googleapis\.com/css2[^>]+>', '')
$inline = "<style>`n" + ($faces -join "`n") + "`n" + [IO.File]::ReadAllText($css) + "`n  </style>"
$out = [regex]::Replace($out, '<script src="https://cdn\.tailwindcss\.com"></script>\s*<script>\s*function c\(v\)[\s\S]*?</script>', { param($x) $inline })
if ($out -match 'cdn\.tailwindcss|fonts\.googleapis') { throw 'В dist остались внешние ссылки' }
[IO.File]::WriteAllText((Join-Path $dist 'index.html'), $out, $utf8)
Copy-Item (Join-Path $root 'img') (Join-Path $dist 'img') -Recurse
Remove-Item $css, (Join-Path $build 'input.css'), (Join-Path $build 'tailwind.config.js')
"Готово: $dist ($($faces.Count) файлов шрифтов)"
