import cryptoFramework from '@ohos.security.cryptoFramework';
import common from '@ohos.app.ability.common';
import { util } from '@kit.ArkTS';
import { ZhihuSessionRepository } from './ZhihuSessionRepository';

const ZSE_93: string = '101_3_3.0';
const ALPHABET: string = '6fpLRqJO8M/c3jnYxFkUVC4ZIG12SiH=5v0mXDazWBTsuw7QetbKdoPyAl+hN9rgE';
const ZK: number[] = [
  1170614578, 1024848638, 1413669199, 3951632832, 3528873006, 2921909214, 4151847688, 3997739139,
  1933479194, 3323781115, 3888513386, 460404854, 3747539722, 2403641034, 2615871395, 2119585428,
  2265697227, 2035090028, 2773447226, 4289380121, 4217216195, 2200601443, 3051914490, 1579901135,
  1321810770, 456816404, 2903323407, 4065664991, 330002838, 3506006750, 363569021, 2347096187
];
const ZB: number[] = [
  20, 223, 245, 7, 248, 2, 194, 209, 87, 6, 227, 253, 240, 128, 222, 91, 237, 9, 125, 157, 230, 93,
  252, 205, 90, 79, 144, 199, 159, 197, 186, 167, 39, 37, 156, 198, 38, 42, 43, 168, 217, 153, 15,
  103, 80, 189, 71, 191, 97, 84, 247, 95, 36, 69, 14, 35, 12, 171, 28, 114, 178, 148, 86, 182, 32,
  83, 158, 109, 22, 255, 94, 238, 151, 85, 77, 124, 254, 18, 4, 26, 123, 176, 232, 193, 131, 172, 143,
  142, 150, 30, 10, 146, 162, 62, 224, 218, 196, 229, 1, 192, 213, 27, 110, 56, 231, 180, 138, 107,
  242, 187, 54, 120, 19, 44, 117, 228, 215, 203, 53, 239, 251, 127, 81, 11, 133, 96, 204, 132, 41,
  115, 73, 55, 249, 147, 102, 48, 122, 145, 106, 118, 74, 190, 29, 16, 174, 5, 177, 129, 63, 113, 99,
  31, 161, 76, 246, 34, 211, 13, 60, 68, 207, 160, 65, 111, 82, 165, 67, 169, 225, 57, 112, 244, 155,
  51, 236, 200, 233, 58, 61, 47, 100, 137, 185, 64, 17, 70, 234, 163, 219, 108, 170, 166, 59, 149, 52,
  105, 24, 212, 78, 173, 45, 0, 116, 226, 119, 136, 206, 135, 175, 195, 25, 92, 121, 208, 126, 139, 3,
  75, 141, 21, 130, 98, 241, 40, 154, 66, 184, 49, 181, 46, 243, 88, 101, 183, 8, 23, 72, 188, 104,
  179, 210, 134, 250, 201, 164, 89, 216, 202, 220, 50, 221, 152, 140, 33, 235, 214
];

export class ZhihuSignerBridge {
  private static readonly encoder: util.TextEncoder = new util.TextEncoder('utf-8');
  private static readonly KEY16: number[] = this.toNumberArray(this.encoder.encodeInto('059053f7d15e01d7'));

  private static encodeUtf8(value: string): Uint8Array {
    return this.encoder.encodeInto(value);
  }

  private static toNumberArray(bytes: Uint8Array): number[] {
    const result: number[] = [];
    for (let index = 0; index < bytes.length; index += 1) {
      result.push(bytes[index]);
    }
    return result;
  }

  private static extractPathWithQuery(url: string): string {
    const schemeIndex = url.indexOf('//');
    const pathStart = schemeIndex >= 0 ? url.indexOf('/', schemeIndex + 2) : url.indexOf('/');
    if (pathStart < 0) {
      return '/';
    }
    const pathname = url.slice(pathStart);
    return pathname.length > 0 ? pathname : '/';
  }

  private static readU32Be(bytes: Uint8Array, offset: number): number {
    return (((bytes[offset] << 24) >>> 0) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0;
  }

  private static writeU32Be(value: number, output: Uint8Array, offset: number): void {
    output[offset] = (value >>> 24) & 0xFF;
    output[offset + 1] = (value >>> 16) & 0xFF;
    output[offset + 2] = (value >>> 8) & 0xFF;
    output[offset + 3] = value & 0xFF;
  }

  private static rotateLeft(value: number, shift: number): number {
    return ((value << shift) | (value >>> (32 - shift))) >>> 0;
  }

  private static gTransform(tt: number): number {
    const transformed =
      ((ZB[(tt >>> 24) & 0xFF] & 0xFF) << 24) |
      ((ZB[(tt >>> 16) & 0xFF] & 0xFF) << 16) |
      ((ZB[(tt >>> 8) & 0xFF] & 0xFF) << 8) |
      (ZB[tt & 0xFF] & 0xFF);
    const ti = transformed >>> 0;
    return (
      ti ^
      this.rotateLeft(ti, 2) ^
      this.rotateLeft(ti, 10) ^
      this.rotateLeft(ti, 18) ^
      this.rotateLeft(ti, 24)
    ) >>> 0;
  }

  private static encryptBlock(input: Uint8Array): Uint8Array {
    const state: number[] = new Array<number>(36).fill(0);
    state[0] = this.readU32Be(input, 0);
    state[1] = this.readU32Be(input, 4);
    state[2] = this.readU32Be(input, 8);
    state[3] = this.readU32Be(input, 12);

    for (let index = 0; index < 32; index += 1) {
      const transformed = this.gTransform((state[index + 1] ^ state[index + 2] ^ state[index + 3] ^ ZK[index]) >>> 0);
      state[index + 4] = (state[index] ^ transformed) >>> 0;
    }

    const output = new Uint8Array(16);
    this.writeU32Be(state[35], output, 0);
    this.writeU32Be(state[34], output, 4);
    this.writeU32Be(state[33], output, 8);
    this.writeU32Be(state[32], output, 12);
    return output;
  }

  private static encryptBlocks(data: Uint8Array, initialVector: Uint8Array): Uint8Array {
    let vector = initialVector;
    const output = new Uint8Array(data.length);
    for (let offset = 0; offset < data.length; offset += 16) {
      const mixed = new Uint8Array(16);
      for (let index = 0; index < 16; index += 1) {
        mixed[index] = (data[offset + index] ^ vector[index]) & 0xFF;
      }
      vector = this.encryptBlock(mixed);
      output.set(vector, offset);
    }
    return output;
  }

  private static customEncode(input: Uint8Array): string {
    let bytes = Array.from(input);
    const remainder = bytes.length % 3;
    if (remainder !== 0) {
      bytes = bytes.concat(new Array<number>(3 - remainder).fill(0));
    }

    let output = '';
    let rollingIndex = 0;
    for (let pointer = bytes.length - 1; pointer >= 0; pointer -= 3) {
      let value = 0;

      const b0 = bytes[pointer] & 0xFF;
      const m0 = (58 >>> (8 * (rollingIndex % 4))) & 0xFF;
      rollingIndex += 1;
      value |= (b0 ^ m0) & 0xFF;

      const b1 = bytes[pointer - 1] & 0xFF;
      const m1 = (58 >>> (8 * (rollingIndex % 4))) & 0xFF;
      rollingIndex += 1;
      value |= ((b1 ^ m1) & 0xFF) << 8;

      const b2 = bytes[pointer - 2] & 0xFF;
      const m2 = (58 >>> (8 * (rollingIndex % 4))) & 0xFF;
      rollingIndex += 1;
      value |= ((b2 ^ m2) & 0xFF) << 16;

      output += ALPHABET[value & 63];
      output += ALPHABET[(value >>> 6) & 63];
      output += ALPHABET[(value >>> 12) & 63];
      output += ALPHABET[(value >>> 18) & 63];
    }

    return output;
  }

  static encryptZseV4(input: string): string {
    const contentBytes = this.toNumberArray(this.encodeUtf8(input));
    const plain: number[] = [210, 0];
    contentBytes.forEach((value: number) => {
      plain.push(value);
    });
    const padding = 16 - (plain.length % 16);
    for (let index = 0; index < padding; index += 1) {
      plain.push(padding);
    }

    const plainBytes = Uint8Array.from(plain);
    const first = new Uint8Array(16);
    for (let index = 0; index < 16; index += 1) {
      first[index] = (plainBytes[index] ^ this.KEY16[index] ^ 42) & 0xFF;
    }

    const cipher = new Uint8Array(plainBytes.length);
    const firstBlock = this.encryptBlock(first);
    cipher.set(firstBlock, 0);
    if (plainBytes.length > 16) {
      const remainder = plainBytes.slice(16);
      cipher.set(this.encryptBlocks(remainder, firstBlock), 16);
    }
    return this.customEncode(cipher);
  }

  static md5LowerHex(content: string): string {
    const md = cryptoFramework.createMd('MD5');
    md.updateSync({ data: this.encodeUtf8(content) });
    const digest = md.digestSync().data;
    return Array.from(digest)
      .map((value: number) => value.toString(16).padStart(2, '0'))
      .join('');
  }

  static buildSignedHeaders(context: common.Context, url: string, body?: string): Record<string, string> {
    const cookies = ZhihuSessionRepository.load(context).cookies;
    const pathname = this.extractPathWithQuery(url);
    const source = [ZSE_93, pathname, cookies.d_c0 ?? '', body]
      .filter((item: string | undefined) => item !== undefined)
      .join('+');
    const sign = this.encryptZseV4(this.md5LowerHex(source));
    const headers: Record<string, string> = {
      'x-zse-93': ZSE_93,
      'x-zse-96': `2.0_${sign}`,
      'x-requested-with': 'fetch'
    };
    if (typeof cookies._xsrf === 'string' && cookies._xsrf.length > 0) {
      headers['x-xsrftoken'] = cookies._xsrf;
    }
    return headers;
  }
}
