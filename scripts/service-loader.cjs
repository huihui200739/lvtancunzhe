const fs=require('fs'),path=require('path'),vm=require('vm'),crypto=require('crypto');
const ts=require('./typescript-runtime.cjs')();
module.exports=function loader(dev){
 const root=path.resolve(__dirname,'../entry/src/main/ets'),cache=new Map();
 function load(file){
  if(file==='BuildProfile')return{default:{DEV_FACTOR_MODE:String(dev)}};
  if(file.startsWith('@kit.'))return{util:{generateRandomUUID:()=>crypto.randomUUID()},buffer:Buffer,hilog:{info(){},warn(){},error(){}},fileIo:{},picker:{}};
  if(file.endsWith('/LedgerDb.ets'))return{};
  if(cache.has(file))return cache.get(file).exports;
  const mod={exports:{}};cache.set(file,mod);
  const js=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
  const req=name=>load(name==='BuildProfile'||name.startsWith('@kit.')?name:path.resolve(path.dirname(file),name+'.ets'));
  vm.runInThisContext('(function(require,module,exports){'+js+'\n})',{filename:file})(req,mod,mod.exports);return mod.exports;
 }
 return file=>load(path.join(root,file+'.ets'));
};
