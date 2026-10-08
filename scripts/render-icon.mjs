// Rasterize the existing vector brand mark for Apple's asset catalog.
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
const require=createRequire(realpathSync(new URL('../../PinHaoYun_backend/node_modules/next/package.json',import.meta.url)));
const sharp=require('sharp');
const root=new URL('../',import.meta.url);
const image=await sharp(readFileSync(new URL('Artwork/AppIcon.svg',root))).resize(1024,1024).flatten({background:'#ffffff'}).png().toBuffer();
for(const name of ['AppIcon.appiconset','BrandMark.imageset']) {
 const folder=new URL('App/Resources/Assets.xcassets/'+name+'/',root);
 writeFileSync(new URL('icon.png',folder),image);
 writeFileSync(new URL('Contents.json',folder),JSON.stringify({images:[name==='AppIcon.appiconset'?{filename:'icon.png',idiom:'universal',platform:'ios',size:'1024x1024'}:{filename:'icon.png',idiom:'universal'}],info:{author:'xcode',version:1}},null,2)+'\n');
}
writeFileSync(new URL('App/Resources/Assets.xcassets/Contents.json',root),JSON.stringify({info:{author:'xcode',version:1}})+'\n');
console.log('Rendered existing vector cloud-and-puzzle brand mark.');
