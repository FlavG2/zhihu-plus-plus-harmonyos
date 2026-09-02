import { hdsMaterial } from '@kit.UIDesignKit';
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import {
  MATERIAL_LEVEL_ADAPTIVE,
  MATERIAL_LEVEL_EXQUISITE,
  MATERIAL_LEVEL_GENTLE,
  MATERIAL_LEVEL_SMOOTH
} from './AppearanceSettingsRepository';

/**
 * HDS 沉浸材质安全封装。
 *
 * 注意：本文件必须是 .ets —— hdsMaterial 声明在 @hms.hds.hdsMaterial.d.ets 中，
 * ArkTS 不允许在 .ts 文件里导入它（编译期会报
 * "can not be imported in .ts file"）。纯逻辑工具（如 DesignMetrics）才可放 .ts。
 *
 * 背景：hdsMaterial 自 API 6.1.0(23) 起提供，但 IMMERSIVE 材质依赖设备能力，
 * 并非所有机型都支持。直接写死 MaterialType.IMMERSIVE 在不支持的设备上拿不到
 * 预期玻璃质感，因此统一做能力检测 + 降级。
 *
 * 官方没有 supportsImmersiveMaterial() 这类便捷接口，只能用
 * getSystemMaterialTypes() 返回的「设备支持的材质类型数组」自行判定。
 *
 * ⚠️ 两套独立材质系统（不可混用）：
 * 1) hdsMaterial（@kit.UIDesignKit, API 23+）：仅用于 HdsNavDestination.titleBar /
 *    HdsTabs.barFloatingStyle。本类 supportsImmersive/resolveType/resolveLevel 走它。
 * 2) uiMaterial（@kit.ArkUI, API 26+/鸿蒙7+）：通过 CommonMethod#systemMaterial()
 *    可作用于任意容器（Row/Column 等），是 PiliPlus 风格「沉浸光感顶栏」的底座。
 *    本类 uiImmersiveAvailable/uiImmersiveMaterial 走它。
 *    minAPIVersion=23 的工程里 targetAPIVersion=26 可编译通过，但运行在 API<26 的设备上
 *    不会生效——必须用条件渲染（if 分支）避免在低版本设备上调用 .systemMaterial()。
 */
export class ZhihuMaterial {
  private static immersiveSupported: boolean | undefined = undefined;
  private static uiImmersiveCached: boolean | undefined = undefined;

  /** 设备是否支持沉浸（IMMERSIVE）材质；结果缓存，异常一律按不支持处理 */
  static supportsImmersive(): boolean {
    if (ZhihuMaterial.immersiveSupported !== undefined) {
      return ZhihuMaterial.immersiveSupported;
    }
    let supported: boolean = false;
    try {
      const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      supported = types.includes(hdsMaterial.MaterialType.IMMERSIVE);
    } catch (_) {
      supported = false;
    }
    ZhihuMaterial.immersiveSupported = supported;
    return supported;
  }

  /**
   * 解析实际可用的材质类型：优先沉浸，设备不支持时退回 ADAPTIVE（跟随系统策略）。
   * 不回退 SMOOTH —— SMOOTH 属于 MaterialLevel（强度），不属于 MaterialType（类型）。
   */
  static resolveType(): hdsMaterial.MaterialType {
    return ZhihuMaterial.supportsImmersive()
      ? hdsMaterial.MaterialType.IMMERSIVE
      : hdsMaterial.MaterialType.ADAPTIVE;
  }

  /** 材质强度映射（与设置页 materialLevel 一致） */
  static resolveLevel(level: number): hdsMaterial.MaterialLevel {
    if (level === MATERIAL_LEVEL_EXQUISITE) {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (level === MATERIAL_LEVEL_GENTLE) {
      return hdsMaterial.MaterialLevel.GENTLE;
    }
    if (level === MATERIAL_LEVEL_SMOOTH) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  /** 默认强度（自适应） */
  static defaultLevel(): number {
    return MATERIAL_LEVEL_ADAPTIVE;
  }

  /** 供设置/调试展示当前实际材质类型 */
  static describe(): string {
    return ZhihuMaterial.supportsImmersive() ? 'IMMERSIVE' : 'ADAPTIVE(降级)';
  }

  // ==================== uiMaterial（API 26+/鸿蒙7+，任意容器可挂） ====================

  /**
   * 设备是否可用 uiMaterial 沉浸光感材质（API 26+ 且设备能力支持）。
   * 双重门：① sdkApiVersion >= 26（编译期 targetAPIVersion=26 不保证运行期满足）
   *         ② uiMaterial.isImmersiveMaterialSupported() 设备能力判定。
   * 结果缓存；异常一律按不可用处理。
   *
   * ⚠️ 调用方必须用条件渲染（if 分支）包裹 .systemMaterial() 的容器构建，
   *    本方法返回 false 时不能让代码路径走到 .systemMaterial() —— 否则在
   *    API<26 设备上会因属性方法不存在而崩溃（try-catch 抓不住链式方法缺失）。
   */
  static uiImmersiveAvailable(): boolean {
    if (ZhihuMaterial.uiImmersiveCached !== undefined) {
      return ZhihuMaterial.uiImmersiveCached;
    }
    let ok: boolean = false;
    try {
      if (deviceInfo.sdkApiVersion >= 26) {
        ok = uiMaterial.isImmersiveMaterialSupported();
      }
    } catch (_) {
      ok = false;
    }
    ZhihuMaterial.uiImmersiveCached = ok;
    return ok;
  }

  /**
   * 构造一个 uiMaterial 沉浸光感材质实例；不可用时返回 undefined。
   * - style: THIN（薄材质，顶栏场景）
   * - interactive: true（可交互，否则触摸穿透）
   * - lightEffect: {}（启用沉浸光感高光，对齐 PiliPlus 风格）
   *
   * 用法：Row(...).systemMaterial(ZhihuMaterial.uiImmersiveMaterial())
   *       必须先通过 uiImmersiveAvailable() 门控，且整段在 if 分支内。
   */
  static uiImmersiveMaterial(): uiMaterial.Material | undefined {
    if (!ZhihuMaterial.uiImmersiveAvailable()) {
      return undefined;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      interactive: true,
      lightEffect: {}
    });
  }

  /** 供设置页展示当前 uiMaterial 可用性文案 */
  static uiImmersiveDescribe(): string {
    return ZhihuMaterial.uiImmersiveAvailable() ? '可用（沉浸光感）' : '不可用（需鸿蒙7+）';
  }
}
