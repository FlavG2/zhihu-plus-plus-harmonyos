import { router } from '@kit.ArkUI';
import {
  ZhihuCommentableTarget,
  serializeZhihuContentTarget
} from '../models/ZhihuContentModels';

/**
 * 统一的知乎内容深链导航分发：把解析出的 ZhihuCommentableTarget 跳转到对应原生页面。
 * 对齐安卓 MainActivity.navigate(destination, popup=true)，也供 Deep Link 与剪贴板识别卡片复用。
 */
export function openZhihuContentTarget(
  target: ZhihuCommentableTarget,
  title: string = '',
  fallbackUrl: string = ''
): void {
  if (target.kind === 'question') {
    router.pushUrl({
      url: 'pages/Question',
      params: { questionId: target.id, title: target.title ?? '' }
    }).catch(() => {});
    return;
  }
  if (target.kind === 'pin') {
    router.pushUrl({
      url: 'pages/Pin',
      params: { pinId: target.id, fallbackUrl }
    }).catch(() => {});
    return;
  }
  router.pushUrl({
    url: 'pages/Article',
    params: {
      target: serializeZhihuContentTarget(target),
      fallbackTitle: title,
      fallbackUrl
    }
  }).catch(() => {});
}
