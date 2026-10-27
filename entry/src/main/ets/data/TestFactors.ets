import { CarbonFactor } from '../models/CarbonFactor';
import { BehaviorCategory, FactorUsableAs, GasScope, ReviewStatus } from '../common/Domain';

/**
 * 测试因子库（数值未核验，仅供开发联调）。
 *
 * 计划书 5.5：「软件测试用数值与生产因子分库管理」。
 * 计划书 5.4：「不将无依据的参考数值写入生产库」。
 *
 * 本文件的每个数值都带 TEST_ 前缀编码，reviewStatus 一律为 PENDING，
 * 只有在 BuildConfig.DEV_FACTOR_MODE = true 时才会被 FactorRepository 载入，
 * 且界面会持续显示「当前使用测试因子，数值未核验」提示。
 *
 * 待办（10 月 20 日首批因子核验 / 10 月 25 日生产复核）：
 *   出行：以方法学或主管部门发布值为准，补齐 vkm 与 pkm 口径；
 *   节水：补自来水单位供水量碳排放因子；
 *   回收：补纸类 / PET 具体处理路径的减排因子；
 *   光盘：补指定食品类型的减少浪费因子。
 * 核验通过后把条目移入 ProdFactors.ets，删除这里的同名项。
 */

function testFactor(code: string, category: BehaviorCategory, subItem: string, label: string,
  value: number, gasScope: GasScope, perUnit: string, distanceBasis: string,
  usableAs: FactorUsableAs, boundary: string): CarbonFactor {
  return {
    code: code,
    version: 'TEST.1',
    category: category,
    subItem: subItem,
    scenarioLabel: label,
    value: value,
    gasScope: gasScope,
    perUnit: perUnit,
    distanceBasis: distanceBasis,
    usableAs: usableAs,
    region: '测试数据集（非实际适用地区）',
    dataYear: 0,
    boundary: boundary,
    methodology: '测试用占位方法，未引用任何正式方法学。',
    sourceTitle: '【测试数据】无正式来源',
    sourceUrl: '',
    sourceLocator: '不适用',
    publishedAt: '',
    licenseNote: '测试数值，不得用于参赛材料、演示视频或任何对外结论。',
    reviewStatus: ReviewStatus.PENDING,
    reviewer: '开发调试',
    verifiedBy: '未复核',
    note: '测试数值，等待正式核验。'
  };
}

/** 测试因子库：覆盖四类行为，保证开发期可端到端联调。 */
export const TEST_FACTORS: CarbonFactor[] = [
  // —— 出行 ——
  testFactor('TEST_TRAVEL_DRIVE_GASOLINE', BehaviorCategory.TRAVEL, 'drive_gasoline', '燃油私家车', 0.192,
    GasScope.CO2E, 'km', 'vkm', FactorUsableAs.BASELINE, '车辆行驶单位里程的直接燃料燃烧排放（测试口径）。'),
  testFactor('TEST_TRAVEL_BUS', BehaviorCategory.TRAVEL, 'bus', '公共汽车', 0.0627,
    GasScope.CO2E, 'km', 'pkm', FactorUsableAs.ACTUAL, '按人公里折算的公共汽车出行排放（测试口径）。'),
  testFactor('TEST_TRAVEL_METRO', BehaviorCategory.TRAVEL, 'metro', '地铁', 0.0410,
    GasScope.CO2E, 'km', 'pkm', FactorUsableAs.ACTUAL, '按人公里折算的地铁出行排放（测试口径）。'),
  testFactor('TEST_TRAVEL_WALK', BehaviorCategory.TRAVEL, 'walk', '步行', 0,
    GasScope.CO2E, 'km', 'pkm', FactorUsableAs.ACTUAL, '步行无直接排放（测试口径）。'),
  testFactor('TEST_TRAVEL_BIKE', BehaviorCategory.TRAVEL, 'bike', '自行车', 0,
    GasScope.CO2E, 'km', 'pkm', FactorUsableAs.ACTUAL, '骑行无直接排放（测试口径）。'),

  // —— 节水节电 ——
  testFactor('TEST_ELEC_HENAN', BehaviorCategory.WATER_ENERGY, 'grid_elec_henan_test', '河南电网用电', 0.5897,
    GasScope.CO2, 'kWh', 'na', FactorUsableAs.SINGLE, '沿用已核验电力因子的数值作为测试输入。'),
  testFactor('TEST_WATER_TAP', BehaviorCategory.WATER_ENERGY, 'tap_water', '自来水', 0.3000,
    GasScope.CO2E, 'm3', 'na', FactorUsableAs.SINGLE, '单位供水量碳排放（测试口径）。'),

  // —— 旧物回收 ——
  testFactor('TEST_RECYCLE_PAPER', BehaviorCategory.RECYCLING, 'waste_paper', '废纸分类回收', 0.9000,
    GasScope.CO2E, 'kg', 'na', FactorUsableAs.SINGLE, '相对于原生浆生产 avoided 排放（测试口径）。'),
  testFactor('TEST_RECYCLE_PLASTIC', BehaviorCategory.RECYCLING, 'waste_plastic_pet', '塑料瓶（PET）回收', 1.5000,
    GasScope.CO2E, 'kg', 'na', FactorUsableAs.SINGLE, '相对于原生 PET 生产 avoided 排放（测试口径）。'),

  // —— 光盘行动 ——
  testFactor('TEST_FOOD_RICE', BehaviorCategory.FOOD, 'food_rice', '减少米饭浪费', 2.5000,
    GasScope.CO2E, 'kg', 'na', FactorUsableAs.SINGLE, '米饭从生产到废弃的温室气体排放（测试口径）。'),
  testFactor('TEST_FOOD_PLATE', BehaviorCategory.FOOD, 'food_plate', '按需取餐减少综合餐食浪费', 1.8000,
    GasScope.CO2E, 'kg', 'na', FactorUsableAs.SINGLE, '综合餐食平均排放（测试口径）。')
];
