import common from '@ohos.app.ability.common';
import { DEFAULT_SESSION_SNAPSHOT, SessionSnapshot, ZhihuSessionData } from '../models/ZhihuModels';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';

export class SessionStore {
  static snapshot(): SessionSnapshot {
    return AppStorage.get<SessionSnapshot>('sessionSnapshot') ?? DEFAULT_SESSION_SNAPSHOT;
  }

  static load(context: common.Context): SessionSnapshot {
    return ZhihuSessionRepository.snapshot(context);
  }

  static save(context: common.Context, data: ZhihuSessionData): SessionSnapshot {
    return ZhihuSessionRepository.save(context, data);
  }

  static reset(context: common.Context): SessionSnapshot {
    return ZhihuSessionRepository.clear(context);
  }
}
