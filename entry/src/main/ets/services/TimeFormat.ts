// 相对时间格式化（对齐安卓官方版卡片「发布于 X 前」）
// 入参为 epoch 秒；返回「刚刚 / X分钟前 / X小时前 / 昨天 / X天前 / X月X日」，无效返回空串。

export function formatRelativeTime(epochSeconds?: number): string {
  if (epochSeconds === undefined || epochSeconds <= 0) {
    return '';
  }
  const now = Math.floor(Date.now() / 1000);
  const diff = now - epochSeconds;
  if (diff < 0) {
    return '';
  }
  if (diff < 60) {
    return '刚刚';
  }
  const minutes = Math.floor(diff / 60);
  if (minutes < 60) {
    return `${minutes}分钟前`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours}小时前`;
  }
  const days = Math.floor(hours / 24);
  if (days === 1) {
    return '昨天';
  }
  if (days < 7) {
    return `${days}天前`;
  }
  const d = new Date(epochSeconds * 1000);
  const month = d.getMonth() + 1;
  const day = d.getDate();
  return `${month}月${day}日`;
}
