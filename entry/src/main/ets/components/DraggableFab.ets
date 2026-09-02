import common from '@ohos.app.ability.common';
import display from '@ohos.display';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FabPositionRepository } from '../services/FabPositionRepository';

const FAB_SIZE: number = 56; // vp，圆形按钮直径
const FAB_EDGE_MARGIN: number = 16; // vp，贴边留白

/**
 * 可复用的可拖动悬浮按钮（对齐安卓 DraggableRefreshButton）。
 * - 图标由 `symbol` 字符串内部自绘（不通过 @BuilderParam 传图标，规避跨组件 builder 的 this 绑定崩溃）。
 * - PanGesture 拖动，松手 clamp 到可视范围并贴最近左右边（animateTo 300ms）。
 * - 坐标持久化到 FabPositionRepository（键 `${prefKey}_x` / `_y`）。
 */
@Component
export struct DraggableFab {
  prefKey: string = 'default_fab';
  symbol: string = 'forward_end_fill';
  loading: boolean = false;
  initiallyOnLeft: boolean = false;
  onFabClick: () => void = () => {};
  bottomAvoidance: number = 90; // vp，距屏幕底部的避让高度（避开系统底栏/安全区）

  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State dragging: boolean = false;

  private context: common.Context = getContext() as common.Context;
  private screenW: number = 360;
  private screenH: number = 800;
  private startX: number = 0;
  private startY: number = 0;

  aboutToAppear(): void {
    this.context = getContext(this) as common.Context;
    // 屏参回退：aboutToAppear 阶段偶发 getDefaultDisplaySync 返回 width=0，
    // 直接用 0 算 defaultX 会得到负值把按钮推到屏外不可见，故无效时回退安全值。
    let w = 360;
    let h = 800;
    try {
      const d = display.getDefaultDisplaySync();
      if (d && d.width > 0 && d.densityPixels > 0) {
        // px -> vp：1vp = density px（避免 aboutToAppear 阶段 getUIContext() 尚未就绪）
        w = d.width / d.densityPixels;
        h = d.height / d.densityPixels;
      }
    } catch (_e) {
      // 取不到屏幕尺寸则保留保守默认值
    }
    this.screenW = w;
    this.screenH = h;
    const defaultX = this.initiallyOnLeft
      ? FAB_EDGE_MARGIN
      : this.clampX(this.screenW - FAB_SIZE - FAB_EDGE_MARGIN);
    const defaultY = this.clampY(Math.max(FAB_EDGE_MARGIN, this.screenH - FAB_SIZE - this.bottomAvoidance));
    let x = defaultX;
    let y = defaultY;
    try {
      const pos = FabPositionRepository.getPos(this.context, this.prefKey, defaultX, defaultY);
      x = this.clampX(pos.x);
      y = this.clampY(pos.y);
    } catch (_e) {
      // 读取持久坐标失败则回退到默认位置（默认右下角可视区）
    }
    this.offsetX = x;
    this.offsetY = y;
  }

  private clampX(x: number): number {
    return Math.min(Math.max(0, x), this.screenW - FAB_SIZE);
  }

  private clampY(y: number): number {
    return Math.min(Math.max(0, y), this.screenH - FAB_SIZE);
  }

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.loading) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color('#FFFFFF')
        } else {
          SymbolGlyph($r('sys.symbol.forward_end_fill'))
            .fontSize(26)
            .fontColor(['#FFFFFF'])
        }
      }
      .width(FAB_SIZE)
      .height(FAB_SIZE)
    }
    .width(FAB_SIZE)
    .height(FAB_SIZE)
    .backgroundColor($r('app.color.brand_blue'))
    .shadow({ radius: 12, color: '#00000040', offsetX: 0, offsetY: 4 })
    .scale({ x: this.dragging ? 1.08 : 1, y: this.dragging ? 1.08 : 1 })
    .position({ x: this.offsetX, y: this.offsetY })
    .onAreaChange((_o: Area, n: Area) => {
      const gp = n.globalPosition;
      hilog.info(0x0912, 'SkipFabDebug', 'Fab size=(%{public}s,%{public}s) globalPos=(%{public}s,%{public}s)',
        `${n.width}`, `${n.height}`, `${gp?.x ?? -1}`, `${gp?.y ?? -1}`);
    })
    .onVisibleAreaChange([0.0, 0.5, 1.0], (isVisible: boolean, ratio: number) => {
      hilog.info(0x0912, 'SkipFabDebug', 'Fab visible=%{public}s ratio=%{public}s', `${isVisible}`, `${ratio}`);
    })
    .zIndex(20)
    .gesture(
      PanGesture({ direction: PanDirection.All, distance: 4 })
        .onActionStart(() => {
          this.startX = this.offsetX;
          this.startY = this.offsetY;
          this.dragging = true;
        })
        .onActionUpdate((e: GestureEvent) => {
          this.offsetX = this.clampX(this.startX + e.offsetX);
          this.offsetY = this.clampY(this.startY + e.offsetY);
        })
        .onActionEnd(() => {
          this.dragging = false;
          const y = this.clampY(this.offsetY);
          const toLeft = this.offsetX < this.screenW / 2;
          const targetX = toLeft ? FAB_EDGE_MARGIN : (this.screenW - FAB_SIZE - FAB_EDGE_MARGIN);
          animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
            this.offsetX = targetX;
            this.offsetY = y;
          });
          FabPositionRepository.setPos(this.context, this.prefKey, targetX, y);
        })
    )
    .onClick(() => {
      if (!this.loading) {
        this.onFabClick();
      }
    })
  }
}
