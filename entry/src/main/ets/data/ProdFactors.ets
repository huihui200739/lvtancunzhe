import { REVIEWED_BEHAVIOR_FACTORS } from './ReviewedBehaviorFactors';
import { CarbonFactor } from '../models/CarbonFactor';
import { BehaviorCategory, FactorUsableAs, GasScope, ReviewStatus } from '../common/Domain';

/**
 * 生产因子库（已核验）。
 *
 * 准入要求（计划书 5.5）：来源可打开、引用段落可定位、单位与公式相容、
 * 地区适用有说明、CO₂ 与 CO₂e 口径清楚、数据许可已核查。
 *
 * 电力类因子，来源为生态环境部、国家统计局
 * 《关于发布 2023 年电力二氧化碳排放因子的公告》附件《2023 年电力二氧化碳排放因子》，
 * 已于 2026-10-15 由本地提取原文正文核对（表 1 / 表 2 / 表 3 / 表 4 / 表 5）。
 *
 * 其他已核对的限定场景见 ReviewedBehaviorFactors.ets。未取得依据的公交、地铁、PET、节水和混合餐食仍不开放正式核算。
 */

const SRC_TITLE = '生态环境部、国家统计局《关于发布2023年电力二氧化碳排放因子的公告》附件《2023年电力二氧化碳排放因子》';
const SRC_URL = 'https://www.mee.gov.cn/xxgk2018/xxgk/xxgk01/202512/W020251231726284332528.pdf';
const LICENSE = '政府公开信息，可在注明来源、数据年份与表号的前提下引用。';

/** 电力类因子共用字段 */
function elecFactor(code: string, subItem: string, label: string, value: number,
  region: string, locator: string, note: string): CarbonFactor {
  return {
    code: code,
    version: '2023.1',
    category: BehaviorCategory.WATER_ENERGY,
    subItem: subItem,
    scenarioLabel: label,
    value: value,
    gasScope: GasScope.CO2,
    perUnit: 'kWh',
    distanceBasis: 'na',
    usableAs: FactorUsableAs.SINGLE,
    region: region,
    dataYear: 2023,
    boundary: '电力消费间接排放；基于地理位置的发电量平均值口径，未包含电力全生命周期（上游燃料、建设等）排放。',
    methodology: '单位发电量（含火电、水电、风电、核电、太阳能发电等全部电力类型发电量）的二氧化碳排放量。',
    sourceTitle: SRC_TITLE,
    sourceUrl: SRC_URL,
    sourceLocator: locator,
    publishedAt: '2026-01-05',
    licenseNote: LICENSE,
    reviewStatus: ReviewStatus.VERIFIED,
    reviewer: '原文数值核对（2026-10-15）',
    verifiedBy: '自动交叉比对；团队独立签核另行登记',
    note: note
  };
}

/** 生产因子库 */
const ELECTRICITY_FACTORS: CarbonFactor[] = [
  elecFactor('EF_ELEC_HENAN_2023', 'grid_elec_henan', '河南电网用电', 0.5897, '河南省',
    '表3 2023年省级电力平均二氧化碳排放因子 · 河南',
    '本项选用河南省因子，理由：用户与项目场景位于河南省内，省级因子与本地区电网结构相符。'),
  elecFactor('EF_ELEC_HUAZHONG_2023', 'grid_elec_huazhong', '华中区域电网用电', 0.5271, '华中区域',
    '表2 2023年区域电力平均二氧化碳排放因子 · 华中',
    '跨省场景或省级因子不适用时的区域口径备选。'),
  elecFactor('EF_ELEC_CN_2023', 'grid_elec_cn', '全国电网用电', 0.5306, '全国',
    '表1 2023年全国电力平均二氧化碳排放因子 · 全国',
    '无法确定省份时的全国口径。'),
  elecFactor('EF_ELEC_CN_NONFOSSIL_EXCLUDED_2023', 'grid_elec_cn_market', '全国电网用电（不含市场化交易非化石电量）', 0.6096, '全国',
    '表4 2023年全国电力平均二氧化碳排放因子（不包括市场化交易的非化石能源电量）',
    '适用于基于市场方式核算电力消费间接排放的场景；若用户已购买绿电，对应电量按 0 核算。'),
  elecFactor('EF_ELEC_CN_FOSSIL_2023', 'grid_elec_cn_fossil', '全国化石能源电力', 0.8273, '全国',
    '表5 2023年全国化石能源电力二氧化碳排放因子',
    '仅适用于需区分电力性质且只核算化石能源电力消费间接排放的场景。')
];

export const PROD_FACTORS: CarbonFactor[] = ELECTRICITY_FACTORS.concat(REVIEWED_BEHAVIOR_FACTORS);
