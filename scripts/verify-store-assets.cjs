'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
function verify(file, width, height, color, maxBytes = 8 * 1024 * 1024) {
  const png = fs.readFileSync(path.join(root, file));
  assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', file);
  assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [width, height], file);
  assert.equal(png[24], 8, file);
  if (color !== undefined) assert.equal(png[25], color, file);
  assert.ok(png.length <= maxBytes, file);
}
const kit = 'PRODUCTION/';
verify(kit + 'google-play/icon-512.png', 512, 512, 6, 1024 * 1024);
verify(kit + 'google-play/feature-graphic.png', 1024, 500, 2);
verify(kit + 'app-store/icon-1024.png', 1024, 1024, 2);
for (const [folder, width, height] of [
  ['google-play/phone', 1080, 1920],
  ['google-play/tablet-7', 1296, 2304],
  ['google-play/tablet-10', 1620, 2880],
  ['app-store/iphone', 1179, 2556],
  ['app-store/ipad-13', 2064, 2752],
]) {
  for (const name of ['01-home', '02-courses', '03-activities', '04-homework']) {
    verify(kit + folder + '/' + name + '.png', width, height, 2);
  }
}
const catalog = 'ios/Runner/Assets.xcassets/AppIcon.appiconset/';
for (const spec of JSON.parse(fs.readFileSync(path.join(root, catalog, 'Contents.json'))).images) {
  const size = parseFloat(spec.size) * parseInt(spec.scale);
  verify(catalog + spec.filename, size, size, 2);
}
for (const [density, size] of Object.entries({mdpi:48, hdpi:72, xhdpi:96, xxhdpi:144, xxxhdpi:192})) {
  verify('android/app/src/main/res/mipmap-' + density + '/ic_launcher.png', size, size);
}
console.log('Verified 20 listing screenshots, both store icons, feature graphic and native launcher icon sizes.');
