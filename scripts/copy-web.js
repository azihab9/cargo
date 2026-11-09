const fs = require('node:fs');
const path = require('node:path');

const projectRoot = path.resolve(__dirname, '..');
const source = path.join(projectRoot, 'index.html');
const webDirectory = path.join(projectRoot, 'www');
const destination = path.join(webDirectory, 'index.html');

if (!fs.existsSync(source)) {
  console.error('index.html tidak ditemukan di root repository.');
  process.exit(1);
}

fs.mkdirSync(webDirectory, { recursive: true });
fs.copyFileSync(source, destination);

console.log('CargoFlow web app disalin ke www/index.html');
