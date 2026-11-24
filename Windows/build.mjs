// Сборка Windows-версии Embers (запускается на macOS, Linux или Windows).
//   node build.mjs assets   — только подготовить ресурсы (для `npm run dev`)
//   node build.mjs          — собрать Embers-Windows-x64.zip
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const res = (...p) => path.join(root, 'resources', ...p);
const run = (cmd, args, opts = {}) => execFileSync(cmd, args, { stdio: 'inherit', cwd: root, ...opts });

// 1. База игр — общая с версией для Mac.
fs.mkdirSync(res(), { recursive: true });
fs.copyFileSync(path.join(root, '..', 'Embers', 'Resources', 'games.json'), res('games.json'));
// 2. Крошечная программа-пустышка (нужен Go: https://go.dev/dl/).
function buildHelper() {
  console.log('> fakegame.exe');
  run('go', ['build', '-trimpath', '-ldflags', '-H=windowsgui -s -w', '-o', res('fakegame.exe'), 'helper/fakegame.go'],
    { env: { ...process.env, GOOS: 'windows', GOARCH: 'amd64', CGO_ENABLED: '0' } });
}
if (process.argv[2] === 'assets') {
  // для `npm run dev`: помощник нужен только на Windows, на других системах пропускаем без ошибки
  try { buildHelper(); } catch { console.log('(Go не найден, fakegame.exe не собран: запуск игр заработает только на Windows после установки Go)'); }
  process.exit(0);
}
buildHelper();

// 3. Упаковка Electron под Windows x64.
console.log('> electron packager');
const { packager } = await import('@electron/packager');
const [appPath] = await packager({
  dir: root, out: path.join(root, 'dist'), name: 'Embers', platform: 'win32', arch: 'x64',
  overwrite: true, prune: true, asar: true,
  extraResource: [res('fakegame.exe'), res('games.json')],
  ignore: [/^\/dist($|\/)/, /^\/helper($|\/)/, /^\/build\.mjs$/, /^\/README/, /^\/\.gitignore$/, /^\/package-lock\.json$/, /^\/resources\/(fakegame\.exe|games\.json)$/],
});

// Оставляем только языки Chromium, которые нужны интерфейсу (английский и русский): -45 МБ.
for (const f of fs.readdirSync(path.join(appPath, 'locales'))) {
  if (!['en-US.pak', 'ru.pak'].includes(f)) fs.rmSync(path.join(appPath, 'locales', f));
}

// 4. Иконка и данные о файле в Embers.exe (без Wine, на чистом JS).
console.log('> icon');
const ResEdit = await import('resedit');
const exePath = path.join(appPath, 'Embers.exe');
const exe = ResEdit.NtExecutable.from(fs.readFileSync(exePath));
const resources = ResEdit.NtExecutableResource.from(exe);
const iconFile = ResEdit.Data.IconFile.from(fs.readFileSync(res('icon.ico')));
ResEdit.Resource.IconGroupEntry.replaceIconsForResource(
  resources.entries, 1, 1033, iconFile.icons.map((i) => i.data));
const vi = ResEdit.Resource.VersionInfo.fromEntries(resources.entries)[0];
vi.setStringValues({ lang: 1033, codepage: 1200 }, {
  FileDescription: 'Embers', ProductName: 'Embers', InternalName: 'Embers',
  OriginalFilename: 'Embers.exe', CompanyName: 'Embers', LegalCopyright: 'MIT License',
});
vi.removeStringValue({ lang: 1033, codepage: 1200 }, 'LegalTrademarks');
vi.outputToResourceEntries(resources.entries);
resources.outputResource(exe);
fs.writeFileSync(exePath, Buffer.from(exe.generate()));

// 5. Архив: папка Embers + README.
console.log('> zip');
const stage = path.join(root, 'dist', 'stage');
fs.rmSync(stage, { recursive: true, force: true });
fs.mkdirSync(stage, { recursive: true });
fs.cpSync(appPath, path.join(stage, 'Embers'), { recursive: true });
for (const f of ['README.md', 'README.ru.md']) {
  const p = path.join(root, '..', 'docs', 'windows', f);
  if (fs.existsSync(p)) fs.copyFileSync(p, path.join(stage, f));
}
const zip = path.join(root, 'dist', 'Embers-Windows-x64.zip');
fs.rmSync(zip, { force: true });
run('zip', ['-qr', '-9', zip, '.'], { cwd: stage });
console.log('OK', zip, (fs.statSync(zip).size / 1048576).toFixed(1) + ' MB');
