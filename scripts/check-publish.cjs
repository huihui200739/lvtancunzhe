/* Review the exact Git index rather than recursively uploading the local workspace. */
const {execFileSync}=require('child_process');
const fs=require('fs');
const path=require('path');
const root=path.resolve(__dirname,'..');
const files=execFileSync('git',['ls-files','-z'],{cwd:root,encoding:'utf8'}).split('\0').filter(Boolean);
if(!files.length)throw Error('Git index is empty; stage the intended project files first.');
const roots=new Set(['.gitignore','README.md','CONTRIBUTING.md','AGENTS.md','build.sh','build-profile.json5','code-linter.json5','hvigorfile.ts','oh-package.json5','oh-package-lock.json5','package.json','package-lock.json']);
const prefixes=['AppScope/','entry/src/','hvigor/','scripts/','docs/team/','.github/'];
const entryFiles=new Set(['entry/build-profile.json5','entry/hvigorfile.ts','entry/oh-package.json5','entry/obfuscation-rules.txt']);
const errors=[];let bytes=0;
for(const file of files){
 const p=path.join(root,file),s=fs.lstatSync(p);bytes+=s.size;
 if(!roots.has(file)&&!entryFiles.has(file)&&!prefixes.some(prefix=>file.startsWith(prefix)))errors.push(`${file}: outside publish allowlist`);
 if(s.isSymbolicLink()||!s.isFile())errors.push(`${file}: unsupported file type`);
 if(/(?:^|\/)(?:node_modules|oh_modules|build|\.hvigor|\.idea|signature|backups)(?:\/|$)|(?:\.db(?:-[\w]+)?|\.sqlite\w*|\.p12|\.pfx|\.p7b|\.keystore|\.jks|\.pem|\.key|\.hap|\.zip|\.tar\.gz|\.log)$/i.test(file))errors.push(`${file}: local data/build/signing artifact`);
 if(s.size>5*1024*1024)errors.push(`${file}: unexpectedly large tracked file`);
 const data=fs.readFileSync(p);
 if(data.includes(0)||/\.(?:png|jpeg|jpg)$/i.test(file))continue;
 const text=data.toString('utf8');
 if(/gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}/.test(text))errors.push(`${file}: possible credential`);
 if(/\/Users\/[A-Za-z0-9._-]+\//.test(text))errors.push(`${file}: personal absolute path`);
}
if(errors.length){console.error(errors.join('\n'));process.exit(1);}
console.log(`PASS publish index: ${files.length} files, ${bytes} bytes; allowlist and credential/local-artifact checks`);
