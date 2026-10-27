/* Regression checks execute the actual ETS services after TypeScript transpilation.
 * The database is a read-only fixture; no app records are changed. */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert/strict');
const ts = require('./typescript-runtime.cjs')();
const root = path.resolve(__dirname, '../entry/src/main/ets');
function loader(dev) {
  const cache = new Map();
  function load(file) {
    if (file === 'BuildProfile') return { default: { DEV_FACTOR_MODE: String(dev) } };
    if (file.endsWith('/LedgerDb.ets')) return {};
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} }; cache.set(file, mod);
    const source = fs.readFileSync(file, 'utf8');
    const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
    const localRequire = (name) => load(name === 'BuildProfile' ? name : path.resolve(path.dirname(file), name + '.ets'));
    vm.runInThisContext('(function(require,module,exports){' + js + '\n})', { filename: file })(localRequire, mod, mod.exports);
    return mod.exports;
  }
  return (file) => load(path.join(root, file + '.ets'));
}
let checks = 0;
function check(name, fn) { fn(); checks++; console.log('PASS ' + name); }
(async () => {
 const load = loader(true), prodLoad = loader(false);
 const { StatsService } = load('services/StatsService');
 const { CsvService } = load('services/CsvService');
 const D = load('common/Domain');
 const rows = [
  { dayKey:'2026-10-14', category:D.BehaviorCategory.WATER_ENERGY, gasScope:D.GasScope.CO2, reductionKg:1.8 },
  { dayKey:'2026-10-15', category:D.BehaviorCategory.WATER_ENERGY, gasScope:D.GasScope.CO2, reductionKg:-0.3 },
  { dayKey:'2026-10-14', category:D.BehaviorCategory.FOOD, gasScope:D.GasScope.CO2E, reductionKg:2 },
  { dayKey:'2026-10-15', category:D.BehaviorCategory.TRAVEL, gasScope:D.GasScope.CO2E, reductionKg:-1 },
  { dayKey:'2026-10-15', category:D.BehaviorCategory.TRAVEL, gasScope:D.GasScope.CO2E, reductionKg:0.25 }
 ];
 const db = { queryStatRows: async () => rows };
 const s = await StatsService.summary(db, D.TimeDimension.DAY, '2026-10-14', '2026-10-15', null, 'CO2');
 check('CO2 汇总隔离 CO2e；净值、负向和计数准确', () => { assert.equal(s.totalNetKg,1.5);assert.equal(s.totalNegativeKg,0.3);assert.equal(s.recordCount,2);assert.equal(s.gasScopes.length,2); });
 const e = await StatsService.summary(db,D.TimeDimension.DAY,'2026-10-14','2026-10-15',null,'CO2e');
 check('切换 CO2e 同步分桶与分类，不串口径',()=>{assert.equal(e.totalNetKg,1.25);assert.equal(e.recordCount,3);assert.equal(e.categories.length,2);assert.equal(e.buckets.reduce((a,b)=>a+b.netKg,0),1.25);});
 const category = await StatsService.summary(db,D.TimeDimension.MONTH,'2026-10-15','2026-10-15',D.BehaviorCategory.TRAVEL,'CO2e');
 check('类别和日期筛选独立生效，负值保留',()=>{assert.equal(category.totalNetKg,-0.75);assert.equal(category.recordCount,2);});
 const empty=await StatsService.summary(db,D.TimeDimension.DAY,'2027-01-01','2027-01-07');
 check('空区间正常返回零',()=>{assert.equal(empty.totalNetKg,0);assert.equal(empty.recordCount,0);assert.equal(empty.allZero,true);});
 const defaultScope=await StatsService.summary(db,D.TimeDimension.DAY,'2026-10-14','2026-10-15');
 check('未显式选口径时仍不跨口径相加',()=>assert.equal(defaultScope.totalNetKg,1.5));
 const csv=await CsvService.categorySummaryCsv(db);
 check('分类 CSV 包含两种口径与各自小计',()=>{assert.equal(csv.ok,true);assert.ok(csv.data.includes('气体口径'));assert.ok(csv.data.includes('CO2e'));assert.ok(csv.data.includes('CO2,1.8000,0.3000,1.5000,2'));assert.ok(csv.data.includes('CO2e,2.2500,1.0000,1.2500,3'));});
 const periods=await CsvService.periodSummaryCsv(db,D.TimeDimension.DAY,'2026-10-14','2026-10-15');
 check('期间 CSV 两种口径都导出，无静默丢记录',()=>{assert.equal(periods.ok,true);assert.equal(periods.data.trim().split('\r\n').length,5);});
 const { CalcEngine }=load('services/CalcEngine');const { FactorRepository }=load('services/FactorRepository');const repo=FactorRepository.createDefault();
 const { CalcEngine:ProdEngine }=prodLoad('services/CalcEngine');const { FactorRepository:ProdRepo }=prodLoad('services/FactorRepository');const prod=ProdRepo.createDefault();
 const { TEST_FACTORS }=prodLoad('data/TestFactors');
 const result=CalcEngine.calculateTravel('TEST_TRAVEL_DRIVE_GASOLINE','TEST_TRAVEL_BUS',10,D.BaselineType.USER_DECLARED,repo,2);
 check('载客换算数值与冻结输入一致',()=>{assert.equal(result.ok,true);assert.equal(result.reductionKg,0.333);assert.equal(result.scenarioResults[0].passengers,2);assert.equal(result.scenarioResults[0].effectiveQuantity,5);assert.ok(result.formulaText.includes('载客 2 人'));});
 const negative=CalcEngine.calculateTravel('TEST_TRAVEL_DRIVE_GASOLINE','TEST_TRAVEL_BUS',10,D.BaselineType.USER_DECLARED,repo,10);
 check('净增排保留负号',()=>{assert.equal(negative.isNetIncrease,true);assert.ok(negative.reductionKg<0);});
 check('正式仓库排除所有测试条目',()=>{assert.equal(prod.find('TEST_TRAVEL_BUS'),undefined);assert.ok(prod.listUsable().every(f=>f.reviewStatus==='verified'));});
 const pending=new ProdRepo(TEST_FACTORS,false);
 const blocked=ProdEngine.calculateSingle(D.BehaviorCategory.FOOD,'TEST_FOOD_RICE',1,'kg','',pending);
 check('正式模式强制拦截未核验因子',()=>{assert.equal(blocked.ok,false);assert.equal(blocked.errorCode,'E_FACTOR_NOT_VERIFIED');});
 const { DateUtil,NumUtil }=load('common/Format');
 check('非法日期和部分数字不会被静默接受',()=>{assert.equal(DateUtil.isValidDay('2026-02-30'),false);assert.equal(DateUtil.isValidDay('2026-10-16'),true);assert.equal(DateUtil.isValidDay('2026-1-2'),false);assert.ok(Number.isNaN(NumUtil.parseQuantity('5公里')));assert.equal(NumUtil.parseQuantity('0.25'),0.25);});
 console.log(`PASS ${checks} regression checks`);
})().catch(e=>{console.error(e);process.exitCode=1;});
