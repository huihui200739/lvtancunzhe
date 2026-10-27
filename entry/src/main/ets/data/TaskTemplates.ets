import { TaskTemplate } from '../models/PlanModels';
import { BehaviorCategory, QuantityUnit } from '../common/Domain';

/**
 * 任务模板池（第 6.1 节）。
 * 首版 8 个模板，覆盖四类行为。预计效果由核验后的因子实时计算，
 * 不在模板中硬编码减排数字。
 *
 * factorSubItem 指向因子子项；若仓库中查不到可用因子，
 * 该模板自动降级为「参与任务」：单独显示、只给参与积分、不计入目标可达性。
 */
export const TASK_TEMPLATES: TaskTemplate[] = [
  {
    templateId: 'P01',
    name: '一次公交替代驾车',
    category: BehaviorCategory.TRAVEL,
    applicableWhen: '用户声明本次原计划驾车，且公交可达；与 P02 互斥。',
    evidenceRule: '记录同一行程的距离、方式与日期。',
    measureUnit: QuantityUnit.KM,
    factorSubItem: 'bus',
    substituteScenario: '驾车',
    defaultQuantity: 5,
    extraMinutes: 15,
    extraCost: 2,
    allowedWeekdays: [],
    mutexGroup: 'travel_replace_car',
    maxTimesPerWeek: 3,
    hasComparableQuantity: true,
    explainTemplate: '你填写的通常方式为{usualWay}，{weekday}可乘公交，预计额外时间{minutes}分钟、额外费用{cost}元，在本周预算内，因此推荐此任务。'
  },
  {
    templateId: 'P02',
    name: '一次步行或骑行替代驾车',
    category: BehaviorCategory.TRAVEL,
    applicableWhen: '用户声明该次驾车可被步行或骑行替代且距离可接受；不鼓励新增出行；与 P01 互斥。',
    evidenceRule: '记录出行方式与距离。',
    measureUnit: QuantityUnit.KM,
    factorSubItem: 'bike',
    substituteScenario: '驾车',
    defaultQuantity: 2,
    extraMinutes: 10,
    extraCost: 0,
    allowedWeekdays: [],
    mutexGroup: 'travel_replace_car',
    maxTimesPerWeek: 4,
    hasComparableQuantity: true,
    explainTemplate: '{weekday}的短距离出行改为骑行，无需额外费用，预计额外时间{minutes}分钟。'
  },
  {
    templateId: 'P03',
    name: '一次有依据的节电',
    category: BehaviorCategory.WATER_ENERGY,
    applicableWhen: '有对照用电量，或可说明设备功率与使用时长。',
    evidenceRule: '填写减少的用电量（kWh）与估算依据。未开空调的小时数不能直接等同于实测节电量。',
    measureUnit: QuantityUnit.KWH,
    factorSubItem: 'grid_elec_henan',
    substituteScenario: '对照用电',
    defaultQuantity: 1,
    extraMinutes: 2,
    extraCost: 0,
    allowedWeekdays: [],
    mutexGroup: '',
    maxTimesPerWeek: 7,
    hasComparableQuantity: true,
    explainTemplate: '{weekday}减少用电{quantity}kWh，按河南电网因子折算，预计额外{minutes}分钟，无额外费用。'
  },
  {
    templateId: 'P04',
    name: '一次有依据的节水',
    category: BehaviorCategory.WATER_ENERGY,
    applicableWhen: '有计量，或能说明明确容量与次数的对照。',
    evidenceRule: '填写减少的用水量（m³）。无依据时仅作参与任务。',
    measureUnit: QuantityUnit.CUBIC_METER,
    factorSubItem: 'tap_water',
    substituteScenario: '对照用水',
    defaultQuantity: 0.1,
    extraMinutes: 2,
    extraCost: 0,
    allowedWeekdays: [],
    mutexGroup: '',
    maxTimesPerWeek: 7,
    hasComparableQuantity: true,
    explainTemplate: '{weekday}减少用水{quantity}m³，按单位供水量因子折算。'
  },
  {
    templateId: 'P05',
    name: '一次有依据的废纸再生利用',
    category: BehaviorCategory.RECYCLING,
    applicableWhen: '匹配已核验的纸类与处理路径。',
    evidenceRule: '须有实际用于再生纸生产的路径和重量依据；仅投放回收箱不满足核算条件；同一批材料只记一次。',
    measureUnit: QuantityUnit.KG,
    factorSubItem: 'waste_paper_utilized',
    substituteScenario: '原生浆生产',
    defaultQuantity: 1,
    extraMinutes: 5,
    extraCost: 0,
    allowedWeekdays: [],
    mutexGroup: 'recycle_paper_batch',
    maxTimesPerWeek: 3,
    hasComparableQuantity: true,
    explainTemplate: '{weekday}核对废纸实际再生利用{quantity}kg 的路径和重量依据，同一批材料只计一次。'
  },
  {
    templateId: 'P06',
    name: '一次塑料瓶分类回收',
    category: BehaviorCategory.RECYCLING,
    applicableWhen: '匹配已核验材料与处理路径。',
    evidenceRule: '填写重量，或使用有出处的单瓶换算；不通用估重。',
    measureUnit: QuantityUnit.KG,
    factorSubItem: 'waste_plastic_pet',
    substituteScenario: '原生 PET 生产',
    defaultQuantity: 0.5,
    extraMinutes: 5,
    extraCost: 0,
    allowedWeekdays: [],
    mutexGroup: 'recycle_plastic_batch',
    maxTimesPerWeek: 3,
    hasComparableQuantity: true,
    explainTemplate: '{weekday}收集塑料瓶{quantity}kg 送回收点，按 PET 回收因子折算。'
  },
  {
    templateId: 'P07',
    name: '按需采购苹果，避免买多浪费',
    category: BehaviorCategory.FOOD,
    applicableWhen: '确实减少原本会浪费的苹果采购，明确原采购量与本次量。',
    evidenceRule: '填写减少采购的零售整果重量、原本与本次采购对照及称重依据；吃完已购食物不直接计为上游减排。',
    measureUnit: QuantityUnit.KG,
    factorSubItem: 'food_apple_procurement',
    substituteScenario: '原本会买多后浪费的采购量',
    defaultQuantity: 0.2,
    extraMinutes: 1,
    extraCost: 0,
    allowedWeekdays: [],
    mutexGroup: '',
    maxTimesPerWeek: 7,
    hasComparableQuantity: true,
    explainTemplate: '{weekday}按需采购苹果，减少原本会浪费的采购量{quantity}kg；仅在有采购对照和整果重量依据时核算，采用全球均值代理。'
  },
  {
    templateId: 'P08',
    name: '一次按需取餐',
    category: BehaviorCategory.FOOD,
    applicableWhen: '按个人可执行意愿安排，缺少可比较数量时只给参与积分。',
    evidenceRule: '记录是否完成；不强制称重。',
    measureUnit: QuantityUnit.TIMES,
    factorSubItem: '',
    substituteScenario: '对照综合餐食浪费',
    defaultQuantity: 1,
    extraMinutes: 0,
    extraCost: 0,
    allowedWeekdays: [],
    mutexGroup: '',
    maxTimesPerWeek: 7,
    hasComparableQuantity: false,
    explainTemplate: '{weekday}按需取餐，不产生可比较数量，因此只计参与积分。'
  }
];

/** 参与任务固定积分 */
export const PARTICIPATION_POINTS = 3;
