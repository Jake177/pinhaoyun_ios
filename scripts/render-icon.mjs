// Export the selected vector mark separately for in-app and Home Screen use.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,realpathSync} from 'node:fs';
const require=createRequire(realpathSync(new URL('../../PinHaoYun_backend/node_modules/next/package.json',import.meta.url)));
const sharp=require('sharp');
const root=new URL('../',import.meta.url);
const source=readFileSync(new URL('Artwork/BrandMark.svg',root),'utf8');
const dark=source.replaceAll('#2874ED','#568EFF').replaceAll('#18BED1','#38D6DF');
const tinted=source.replaceAll('#2874ED','#E4E4E4').replaceAll('#18BED1','#A8A8A8');
const background='#10213D';
const lightIcon=dark.replace('Transparent background and seam.','Opaque navy Home Screen canvas with a clear puzzle seam.').replace('<path ',`<rect width="1024" height="1024" fill="${background}"/><path `);
writeFileSync(new URL('Artwork/AppIcon.svg',root),lightIcon);

const assets=new URL('App/Resources/Assets.xcassets/',root);
const appearance=value=>[{appearance:'luminosity',value}];
const info={author:'xcode',version:1};
const markImages=[];
for(const [name,svg,mode] of [['icon.png',source,null],['icon-dark.png',dark,'dark']]) {
 const folder=new URL('BrandMark.imageset/',assets);
 const image=await sharp(Buffer.from(svg)).resize(1024,1024).png().toBuffer();
 const pixel=await sharp(image).extract({left:0,top:0,width:1,height:1}).ensureAlpha().raw().toBuffer();
 assert.equal(pixel[3],0,'In-app brand mark must not contain a baked background');
 writeFileSync(new URL(name,folder),image);
 markImages.push({filename:name,idiom:'universal',...(mode?{appearances:appearance(mode)}:{})});
}
writeFileSync(new URL('BrandMark.imageset/Contents.json',assets),JSON.stringify({images:markImages,info,properties:{'template-rendering-intent':'original'}},null,2)+'\n');

const iconImages=[];
for(const [name,svg,mode] of [['icon.png',lightIcon,null],['icon-dark.png',dark,'dark'],['icon-tinted.png',tinted,'tinted']]) {
 let exporter=sharp(Buffer.from(svg)).resize(1024,1024);
 if(!mode)exporter=exporter.flatten({background});
 const image=await exporter.png().toBuffer();
 const metadata=await sharp(image).metadata();
 assert.equal(metadata.width,1024);assert.equal(metadata.height,1024);
 if(!mode)assert.equal(metadata.hasAlpha,false,'Default Home Screen icon must be opaque');
 else {
  const pixel=await sharp(image).extract({left:0,top:0,width:1,height:1}).ensureAlpha().raw().toBuffer();
  assert.equal(pixel[3],0,'Dark/tinted mark must allow the system background through');
 }
 writeFileSync(new URL('AppIcon.appiconset/'+name,assets),image);
 iconImages.push({filename:name,idiom:'universal',platform:'ios',size:'1024x1024',...(mode?{appearances:appearance(mode)}:{})});
}
writeFileSync(new URL('AppIcon.appiconset/Contents.json',assets),JSON.stringify({images:iconImages,info},null,2)+'\n');
console.log('Exported transparent light/dark brand marks and default/dark/tinted Home Screen icons; alpha checks passed.');
