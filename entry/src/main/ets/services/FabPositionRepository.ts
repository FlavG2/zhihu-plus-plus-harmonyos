import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

const FAB_POSITIONS_FILE: string = 'zhihu_fab_positions';

export interface FabPos {
  x: number;
  y: number;
}

/**
 * 可拖动 FAB 的坐标持久化（独立 preferences 文件，避免污染外观配置）。
 * 坐标以 vp 存储，键为 `${prefKey}_x` / `${prefKey}_y`。
 */
export class FabPositionRepository {
  private static preferences(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context, { name: FAB_POSITIONS_FILE });
  }

  /** 读取 FAB 坐标（vp）。缺省值由调用方给定（通常落右下角）。 */
  static getPos(context: common.Context, prefKey: string, defaultX: number, defaultY: number): FabPos {
    const store = this.preferences(context);
    const x = store.getSync(`${prefKey}_x`, defaultX) as number;
    const y = store.getSync(`${prefKey}_y`, defaultY) as number;
    return { x, y };
  }

  static setPos(context: common.Context, prefKey: string, x: number, y: number): void {
    const store = this.preferences(context);
    store.putSync(`${prefKey}_x`, x);
    store.putSync(`${prefKey}_y`, y);
    store.flushSync();
  }
}
