import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { Result, ErrorCode } from '../common/AppError';
import { OPEN_IMAGE_LABELS } from '../data/OpenImageLabels';
import { OPEN_IMAGE_THRESHOLDS } from '../data/OpenImageThresholds';
import { PhotoAssist, PhotoInsight } from './PhotoAssist';

/** 一次端侧识别的结果与耗时；耗时为实测值，界面原样展示 */
export interface PhotoRecognition {
  insight: PhotoInsight;
  elapsedMs: number;
}

const MODEL_FILE = 'model/mobilenetv2_openimage.ms';
const SIDE = 224;
const MEAN: number[] = [0.485, 0.456, 0.406];
const STD: number[] = [0.229, 0.224, 0.225];

/**
 * 端侧图像识别：MindSpore Lite 在本机 CPU 上运行随包的 MobileNetV2 模型，照片不上传、不联网。
 * 预处理与官方示例一致：短边缩到 256 → 中心裁 224 → RGB/255 → 按 ImageNet 均值方差归一化（NHWC）。
 */
export class PhotoRecognizer {
  private static model: mindSporeLite.Model | null = null;

  private static async loadModel(context: common.Context): Promise<mindSporeLite.Model> {
    if (PhotoRecognizer.model !== null) {
      return PhotoRecognizer.model;
    }
    const raw: Uint8Array = context.resourceManager.getRawFileContentSync(MODEL_FILE);
    const buffer = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer;
    const options: mindSporeLite.Context = { target: ['cpu'], cpu: { threadNum: 2 } };
    PhotoRecognizer.model = await mindSporeLite.loadModelFromBuffer(buffer, options);
    return PhotoRecognizer.model;
  }

  /** 识别相册/相机返回的照片 URI */
  static async recognizeUri(context: common.Context, uri: string): Promise<Result<PhotoRecognition>> {
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const source = image.createImageSource(file.fd);
      return await PhotoRecognizer.recognizeSource(context, source);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `读取照片失败：${PhotoRecognizer.errText(e)}`);
    } finally {
      if (file !== null) {
        fileIo.closeSync(file);
      }
    }
  }

  /** 识别随包的演示样张（模拟器没有摄像头内容时用于演示） */
  static async recognizeRawfile(context: common.Context, path: string): Promise<Result<PhotoRecognition>> {
    try {
      const raw: Uint8Array = context.resourceManager.getRawFileContentSync(path);
      const source = image.createImageSource(raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer);
      return await PhotoRecognizer.recognizeSource(context, source);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `读取样张失败：${PhotoRecognizer.errText(e)}`);
    }
  }

  private static async recognizeSource(context: common.Context, source: image.ImageSource): Promise<Result<PhotoRecognition>> {
    const started = Date.now();
    let pixelMap: image.PixelMap | null = null;
    try {
      const info = source.getImageInfoSync();
      const w = info.size.width;
      const h = info.size.height;
      if (w <= 0 || h <= 0) {
        return Result.failure(ErrorCode.E_IO, '照片尺寸无效。');
      }
      // 先按原尺寸解码，再显式缩放：解码时的 desiredSize 不保证放大小图，放大失败会让裁剪越界。
      pixelMap = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888, editable: true });
      const scale = 256 / Math.min(w, h);
      pixelMap.scaleSync(scale, scale, image.AntiAliasingLevel.MEDIUM);
      const scaled = pixelMap.getImageInfoSync().size;
      if (scaled.width < SIDE || scaled.height < SIDE) {
        return Result.failure(ErrorCode.E_IO, `照片缩放后尺寸不足（${scaled.width}×${scaled.height}）。`);
      }
      pixelMap.cropSync({ x: Math.floor((scaled.width - SIDE) / 2), y: Math.floor((scaled.height - SIDE) / 2),
        size: { width: SIDE, height: SIDE } });
      const rgba = new ArrayBuffer(SIDE * SIDE * 4);
      await pixelMap.readPixelsToBuffer(rgba);
      const px = new Uint8Array(rgba);
      const input = new Float32Array(SIDE * SIDE * 3);
      for (let i = 0, j = 0; i < SIDE * SIDE; i++, j += 4) {
        input[i * 3] = (px[j] / 255 - MEAN[0]) / STD[0];
        input[i * 3 + 1] = (px[j + 1] / 255 - MEAN[1]) / STD[1];
        input[i * 3 + 2] = (px[j + 2] / 255 - MEAN[2]) / STD[2];
      }
      const model = await PhotoRecognizer.loadModel(context);
      const inputs = model.getInputs();
      inputs[0].setData(input.buffer);
      const outputs = await model.predict(inputs);
      const raw = new Float32Array(outputs[0].getData());
      const values: number[] = [];
      for (let i = 0; i < Math.min(raw.length, OPEN_IMAGE_LABELS.length); i++) {
        values.push(raw[i]);
      }
      const scores = PhotoAssist.normalize(values, OPEN_IMAGE_THRESHOLDS);
      const recognition: PhotoRecognition = { insight: PhotoAssist.suggest(scores, OPEN_IMAGE_LABELS), elapsedMs: Date.now() - started };
      return Result.success(recognition);
    } catch (e) {
      return Result.failure(ErrorCode.E_IO, `端侧识别失败：${PhotoRecognizer.errText(e)}`);
    } finally {
      if (pixelMap !== null) {
        pixelMap.release();
      }
      source.release();
    }
  }

  private static errText(e: object): string {
    const msg = (e as Error).message;
    return msg !== undefined ? msg : JSON.stringify(e);
  }
}
