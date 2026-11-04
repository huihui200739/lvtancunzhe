mobilenetv2_openimage.ms
来源：MindSpore 官方模型库 https://download.mindspore.cn/model_zoo/official/lite/mobilenetv2_openimage_lite/1.5/mobilenetv2.ms
对应示例：MindSpore models 仓库 official/lite/image_classification（Apache License 2.0）
SHA-256：d2e92f251021d17ed29f0d4484f050285534873b644e7dfa4cbd4e26ce999d94
任务：Open Images 410 类图像标签分类（输出前 410 维与示例 labels_name_map 对应）。输入 1×224×224×3（NHWC），ImageNet 均值方差归一化。
本应用只用它判断画面里“可能有什么”，据此建议存入单；不识别数量、不判断行为真实性，也不参与任何核算。
