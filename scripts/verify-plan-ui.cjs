const assert = require('node:assert/strict');
const load = require('./service-loader.cjs')(false);
const { PlanDraftState } = load('services/PlanDraftState');
const original = { startDay: '2026-10-18', targetKg: 15, gasScope: 'CO2', budgetMinutes: 120, budgetCost: 20,
  availableDays: ['2026-10-20', '2026-10-19'], acceptedCategories: ['travel', 'food'],
  usualTravelSubItem: 'drive_gasoline', usualTravelKm: 5, excludedTemplateIds: [] };
const key = PlanDraftState.key(original);
const reordered = structuredClone(original); reordered.availableDays.reverse(); reordered.acceptedCategories.reverse();
reordered.startDay = '2026-10-19'; reordered.excludedTemplateIds = ['P01'];
assert.equal(PlanDraftState.key(reordered), key);
assert.deepEqual(original.availableDays, ['2026-10-20', '2026-10-19']);
console.log('PASS 日期滚动、选择顺序与内部排除不制造表单修改，比较不改变原数据');
for (const [field,value] of Object.entries({targetKg:150,gasScope:'CO2e',budgetMinutes:60,budgetCost:0,
  availableDays:['2026-10-20'],acceptedCategories:['food'],usualTravelSubItem:'walk',usualTravelKm:8})) {
 const changed = structuredClone(original); changed[field] = value;
 assert.notEqual(PlanDraftState.key(changed), key, field);
 changed[field] = structuredClone(original[field]);
 assert.equal(PlanDraftState.key(changed), key, field+' restored');
}
console.log('PASS 真实目标/偏好修改可识别，改回原值后恢复为未修改');
const plan={planId:'a',planVersion:1,constraintsJson:JSON.stringify(original)};
assert.equal(PlanDraftState.planChanged({...plan},plan),false);
for(const changed of [{...plan,planId:'b'},{...plan,planVersion:2},{...plan,constraintsJson:'{}'}])assert.equal(PlanDraftState.planChanged(plan,changed),true);
assert.equal(PlanDraftState.planChanged(null,plan),true);
console.log('PASS 同一计划更新不覆盖草稿，恢复不同计划或不同条件需重新加载表单');
assert.deepEqual(PlanDraftState.outsideWeek(['2026-10-17','2026-10-18'],['2026-10-18','2026-10-19']),['2026-10-17']);
const zero={...original,budgetMinutes:0};
for(const value of [-1,NaN])assert.notEqual(PlanDraftState.key({...zero,budgetMinutes:value}),PlanDraftState.key(zero));
console.log('PASS 超出本周的已选日期保留可见，非法预算不会伪装成已保存的零预算');

console.log('PASS 4 plan UI state checks');
